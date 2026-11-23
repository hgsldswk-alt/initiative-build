import StoreKit
import SwiftUI
import UIKit

private enum BoardSheet: Identifiable {
    case rosters, add, edit(Combatant), health(Combatant), paywall, share, settings
    var id: String {
        switch self {
        case .rosters: return "rosters"
        case .add: return "add"
        case .edit(let combatant): return "edit-" + combatant.id.uuidString
        case .health(let combatant): return "hp-" + combatant.id.uuidString
        case .paywall: return "paywall"
        case .share: return "share"
        case .settings: return "settings"
        }
    }
}

struct RootView: View {
    @StateObject private var store = BoardStore()
    @StateObject private var access = StoreAccess()
    @Environment(\.scenePhase) private var scene
    @Environment(\.requestReview) private var requestReview
    @Environment(\.dynamicTypeSize) private var dynamicType
    @ScaledMetric(relativeTo: .largeTitle) private var tableNowSize = 64.0
    @ScaledMetric(relativeTo: .title) private var tableNextSize = 32.0
    @State private var sheet: BoardSheet?
    @State private var table = false
    @State private var tablePriorIdle = false
    @State private var name = ""
    @State private var score = ""
    @State private var quickError: BoardError?
    @State private var deepLink: URL?

    private enum Field: Hashable { case name, score }
    @FocusState private var focus: Field?

    private var encounter: Encounter { store.board.play.active }
    private var canUseHP: Bool { access.hasPro || encounter.proInBattle }

    var body: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width > 600 && proxy.size.width > proxy.size.height
            Group {
                if !store.ready { boot }
                else if let summary = store.board.play.summary { results(summary) }
                else if encounter.turn != nil { live(wide: wide) }
                else { setup }
            }
            .frame(maxWidth: wide && table ? 900 : 640, maxHeight: .infinity)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(background.ignoresSafeArea())
        .foregroundStyle(table ? .white : Palette.ink)
        .preferredColorScheme(table ? .dark : .light)
        .tint(Palette.accent)
        .task {
            await store.open()
            if Launch.has("-paywall") { sheet = .paywall }
            if Launch.value("-scene") == "table", encounter.turn != nil { setTable(true) }
        }
        .task { await access.run() }
        .task(id: scene) {
            guard scene == .active else { return }
            await access.refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) }
                catch { return }
                await access.refresh()
                await offerReview()
            }
        }
        .task(id: encounter.id.uuidString + "-\(access.hasPro)-\(store.busy)-\(encounter.turn != nil)") {
            await preserveActivePro()
        }
        .task(id: ReviewTrigger(ready: store.ready, summary: store.board.play.summary != nil,
                               active: encounter.turn != nil, pending: access.pending || access.working,
                               modal: sheet != nil, error: store.error != nil, foreground: scene == .active,
                               eligible: store.board.play.review.eligible)) {
            await offerReview()
        }
        .onOpenURL { url in
            guard url.scheme == "initiativeboard", url.host == "resume" else { return }
            deepLink = url
            if store.ready { resumeFromLink() }
        }
        .onChange(of: store.ready) { _, isReady in
            if isReady, deepLink != nil { resumeFromLink() }
        }
        .onChange(of: scene) { _, phase in
            if table { UIApplication.shared.isIdleTimerDisabled = phase == .active || tablePriorIdle }
        }
        .onDisappear { if table { setTable(false) } }
        .sheet(item: $sheet, onDismiss: { store.error = nil }) { selection in
            switch selection {
            case .rosters: RosterView(store: store, access: access, onPro: showPro)
            case .add, .edit:
                let member: Combatant? = {
                    if case .edit(let member) = selection { return member }
                    return nil
                }()
                CombatantEditor(member: member, live: encounter.turn != nil,
                                canEditHP: canUseHP, store: store, onPro: showPro)
            case .health(let member): HealthView(member: member, store: store)
            case .settings: BoardSettings(store: store, access: access, onPro: showPro)
            case .paywall: Paywall(access: access)
            case .share:
                if let summary = store.board.play.summary {
                    ShareCardView(summary: summary, total: store.board.play.validEncounters.count)
                }
            }
        }
        .alert(L.t("error.title"), isPresented: Binding(get: { store.error != nil && store.ready && sheet == nil },
                                                        set: { if !$0 { store.error = nil } })) {
            Button(L.t("close"), role: .cancel) { store.error = nil }
        } message: {
            if let error = store.error { Text(L.t("error." + error.rawValue)) }
        }
    }

    private struct ReviewTrigger: Equatable {
        var ready: Bool
        var summary: Bool
        var active: Bool
        var pending: Bool
        var modal: Bool
        var error: Bool
        var foreground: Bool
        var eligible: Bool
    }

    private func preserveActivePro() async {
        guard access.hasPro, encounter.turn != nil, !encounter.proInBattle,
              store.board.play.summary == nil, !store.busy else { return }
        _ = await store.save { $0.play.active.proInBattle = true }
    }

    private func offerReview() async {
        guard !Launch.testing, scene == .active, store.ready, !store.busy,
              encounter.turn == nil, encounter.members.isEmpty, sheet == nil, focus == nil, name.isEmpty, score.isEmpty,
              store.board.play.summary == nil, store.error == nil, !access.pending, !access.working,
              store.board.play.review.eligible, !store.board.play.review.attemptedVersions.contains(Launch.version) else { return }
        let saved = await store.save { _ = $0.play.review.takeRequest(version: Launch.version, idle: true) }
        if saved, scene == .active, sheet == nil, encounter.turn == nil, encounter.members.isEmpty,
           !access.pending, !access.working { requestReview() }
    }

    private var background: Color {
        if table { return Palette.deep }
        return store.board.appearance == "rose" ? Palette.tint : Palette.paper
    }

    private var boot: some View {
        VStack(spacing: 16) {
            if let error = store.error {
                Text(L.t("error." + error.rawValue)).multilineTextAlignment(.center)
                BoardButton("retry", id: "boot.retry") {
                    store.error = nil
                    Task { await store.open() }
                }
            } else {
                ProgressView(L.t("loading")).accessibilityIdentifier("boot.loading")
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var setup: some View {
        VStack(spacing: 8) {
            top(title: L.t("app.title"), subtitle: L.t("setup.subtitle")) {
                BoardButton("rosters", id: "home.rosters") { focus = nil; sheet = .rosters }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    quickEntry
                    HStack {
                        Text(L.t("order")).font(.headline).accessibilityAddTraits(.isHeader)
                        Spacer()
                        BoardButton(encounter.ascending ? "sort.low" : "sort.high", id: "home.sort") {
                            update { $0.active.sort(!$0.active.ascending) }
                        }
                    }
                    orderRows(publicOnly: false)
                    if encounter.members.isEmpty {
                        Text(L.t("setup.empty")).font(.subheadline).foregroundStyle(Palette.muted).modifier(Panel())
                    }
                }.padding(.bottom, 4)
            }.scrollDismissesKeyboard(.interactively)
            VStack(spacing: 2) {
                BoardButton("start", id: "home.start", kind: .primary) {
                    focus = nil
                    let pro = access.hasPro
                    update { try $0.active.start(pro: pro) }
                }.disabled(store.busy || encounter.members.isEmpty)
                if focus == nil {
                    HStack {
                        BoardButton("settings", id: "home.settings") { sheet = .settings }
                        Spacer()
                        if !access.value.purchasedPro {
                            BoardButton("pro", id: "home.pro", action: showPro)
                        }
                    }
                }
            }
        }
    }

    private var quickEntry: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.t("add.title")).font(.headline).accessibilityAddTraits(.isHeader)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 7) {
                    quickName.frame(minWidth: 105)
                    quickScore.frame(width: 75)
                    BoardButton("add", id: "home.add", kind: .bordered, action: addQuick).frame(width: 64)
                }.fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 7) {
                    quickName
                    HStack(alignment: .bottom) {
                        quickScore
                        BoardButton("add", id: "home.add", kind: .bordered, action: addQuick)
                    }
                }
            }
            if let quickError {
                Text(L.t("error." + quickError.rawValue)).font(.footnote).foregroundStyle(Palette.accent)
                    .accessibilityIdentifier("home.inputError")
            } else {
                Text(L.t("setup.keyboard")).font(.footnote).foregroundStyle(Palette.muted)
            }
        }.modifier(Panel())
    }

    private var quickName: some View {
        BoardField(key: "name", placeholder: "name.placeholder", id: "home.name", value: $name)
            .focused($focus, equals: .name).submitLabel(.next).onSubmit { focus = .score }
    }

    private var quickScore: some View {
        BoardField(key: "initiative", placeholder: "score.placeholder", id: "home.score", value: $score)
            .focused($focus, equals: .score).keyboardType(.numbersAndPunctuation)
            .submitLabel(.done).onSubmit(addQuick)
    }

    private func addQuick() {
        let wasEditing = focus != nil
        let member: Combatant
        do {
            member = try Combatant(name: name, score: Combatant.parseScore(score)).validated()
        } catch {
            quickError = error as? BoardError ?? .score
            return
        }
        Task {
            let saved = await store.save { board in try board.change { try $0.active.put(member) } }
            if saved {
                quickError = nil
                name = ""
                score = ""
                focus = wasEditing ? .name : nil
            }
        }
    }

    private func live(wide: Bool) -> some View {
        VStack(spacing: 10) {
            top(title: L.f("round", encounter.turn?.round ?? 1),
                subtitle: table ? L.t("table") : encounter.name ?? L.t("live.title")) {
                BoardButton(table ? "exit" : "table", id: table ? "table.exit" : "live.table",
                            kind: table ? .tablePlain : .plain) { setTable(!table) }
            }
            if wide && !dynamicType.isAccessibilitySize {
                HStack(alignment: .top, spacing: 18) {
                    turnCards.frame(maxWidth: .infinity, alignment: .top)
                    ScrollView { turnList }.frame(maxWidth: .infinity)
                }
            } else if dynamicType.isAccessibilitySize {
                ScrollView { VStack(spacing: 10) { turnCards; turnList } }
            } else {
                turnCards
                ScrollView { turnList }
            }
            Spacer(minLength: 0)
            if !table {
                BoardButton("finish", id: "live.finish") { update { $0.finish() } }.disabled(store.busy)
            }
            HStack(spacing: 8) {
                if !table {
                    BoardButton("undo", id: "live.undo", kind: .bordered) {
                        Task { _ = await store.save { $0.undo() } }
                    }.frame(maxWidth: 96).disabled(store.board.history.isEmpty || store.busy)
                }
                BoardButton("nextTurn", id: table ? "table.advance" : "live.advance", kind: table ? .tablePrimary : .primary) {
                    Task { await store.advance() }
                }.disabled(encounter.current == nil || store.busy)
            }
        }.padding(.bottom, 4)
    }

    private var turnCards: some View {
        VStack(spacing: 8) {
            turnCard("now", member: encounter.current, prominent: true)
            turnCard("upNext", member: encounter.next, prominent: false)
        }
    }

    private var turnList: some View {
        VStack(spacing: 5) {
            HStack {
                Text(L.t("order")).font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                if !table {
                    BoardButton("rosters", id: "live.rosters") { sheet = .rosters }
                    BoardButton("add.live", id: "live.add") { sheet = .add }
                }
            }
            orderRows(publicOnly: table)
        }
    }

    private func turnCard(_ key: String, member: Combatant?, prominent: Bool) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L.t(key)).font(.caption.bold()).textCase(.uppercase).tracking(0.8)
                    .foregroundStyle(prominent ? Palette.light : Palette.accent)
                Text(member.map { table ? $0.publicName : $0.name } ?? L.t("turn.empty"))
                    .font(table ? .system(size: prominent ? tableNowSize : tableNextSize) : (prominent ? .largeTitle : .title3))
                    .bold().foregroundStyle(prominent ? .white : Palette.ink)
                    .lineLimit(dynamicType.isAccessibilitySize ? nil : 2)
                    .accessibilityIdentifier(key == "now" ? "turn.now" : "turn.next")
            }
            Spacer(minLength: 0)
            if !table, let value = member?.score {
                Text(value, format: .number.grouping(.never)).font(.title3.bold()).monospacedDigit()
                    .foregroundStyle(prominent ? .white : Palette.ink)
            }
        }
        .padding(prominent && table ? EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0)
                 : EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            if prominent && table { Rectangle().fill(Palette.light.opacity(0.25)).frame(height: 1) }
        }
        .background(prominent ? Palette.deep : Palette.tint, in: RoundedRectangle(cornerRadius: 18))
    }

    private func orderRows(publicOnly: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(encounter.ordered.enumerated()), id: \.element.id) { index, member in
                if index > 0 { Divider().overlay(publicOnly ? Palette.light.opacity(0.22) : Palette.line) }
                if publicOnly { rowText(member, index: index, publicOnly: true).padding(.horizontal, 10) }
                else {
                    HStack(spacing: 0) {
                        Button {
                            focus = nil
                            sheet = .edit(member)
                        } label: {
                            rowText(member, index: index, publicOnly: false)
                                .padding(.leading, 10).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("member.edit.\(index)")
                        .accessibilityAction(named: Text(L.t("move.up"))) { move(member.id, to: index - 1) }
                        .accessibilityAction(named: Text(L.t("move.down"))) { move(member.id, to: index + 1) }
                        if encounter.turn != nil, let hp = member.hp, let maxHP = member.maxHP {
                            Button {
                                sheet = canUseHP ? .health(member) : .paywall
                            } label: {
                                Text(L.f("hp.value", hp, maxHP)).font(.caption.weight(.semibold))
                                    .padding(.horizontal, 4).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                            }
                            .accessibilityIdentifier("member.hp.\(index)")
                        }
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(Palette.muted)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                            .draggable(member.id.uuidString)
                            .accessibilityHidden(true)
                    }
                    .dropDestination(for: String.self) { values, _ in
                        guard let value = values.first, let id = UUID(uuidString: value) else { return false }
                        move(id, to: index)
                        return true
                    }
                    .background(member.id == encounter.current?.id ? Palette.tint : .clear)
                }
            }
        }
        .background(publicOnly ? Color.clear : Palette.surface, in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            if !publicOnly { RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.line).allowsHitTesting(false) }
        }
    }

    private func rowText(_ member: Combatant, index: Int, publicOnly: Bool) -> some View {
        HStack(spacing: 8) {
            if !publicOnly {
                Text(index + 1, format: .number).font(.caption.monospacedDigit()).foregroundStyle(Palette.muted)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(publicOnly ? member.publicName : member.name).font(.subheadline.weight(.semibold))
                if !publicOnly, let status = rowStatus(member, publicOnly: false) {
                    Text(L.t(status)).font(.caption).foregroundStyle(Palette.muted)
                }
            }
            Spacer(minLength: 0)
            if publicOnly, let status = rowStatus(member, publicOnly: true) {
                Text(L.t(status)).font(.caption).foregroundStyle(Palette.light)
            }
            if !publicOnly {
                if let score = member.score {
                    Text(score, format: .number.grouping(.never)).font(.subheadline.monospacedDigit().bold())
                } else { Text(L.t("missing")).font(.caption).foregroundStyle(Palette.accent) }
            }
        }
        .frame(minHeight: 48)
        .accessibilityElement(children: .combine)
    }

    private func rowStatus(_ member: Combatant, publicOnly: Bool) -> String? {
        if publicOnly && !member.visible { return nil }
        if member.id == encounter.current?.id { return "now" }
        if encounter.turn?.deferred.contains(member.id) == true { return "deferred" }
        if encounter.turn?.acted.contains(member.id) == true { return "acted" }
        if member.id == encounter.next?.id { return "upNext" }
        if !publicOnly && !member.visible { return "hidden.host" }
        return nil
    }

    private func move(_ id: UUID, to index: Int) {
        var ids = encounter.ordered.map(\.id)
        guard ids.indices.contains(index), let source = ids.firstIndex(of: id), source != index else { return }
        ids.remove(at: source)
        ids.insert(id, at: index)
        update { $0.active.reorder(ids) }
    }

    private func results(_ summary: Summary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                top(title: L.t("results.title"), subtitle: summary.encounter.name ?? L.t("live.title")) {
                    BoardButton("finish.undo", id: "summary.undo") { Task { _ = await store.save { $0.undo() } } }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(L.f("round", summary.encounter.turn?.round ?? 1)).font(.largeTitle.bold())
                    Text(L.f("participants", summary.encounter.participants.count)).foregroundStyle(Palette.muted)
                }.modifier(Panel())
                if summary.milestone {
                    Text(L.t("milestone.title")).font(.headline).modifier(Panel(fill: Palette.tint))
                }
                BoardButton("share.card", id: "summary.share", kind: .bordered) { sheet = .share }
                BoardButton("code.copy", id: "summary.code", kind: .bordered) {
                    copySummaryCode(summary)
                }
                ShareNotice()
                BoardButton("newEncounter", id: "summary.new", kind: .primary) {
                    Task { _ = await store.save { $0.play.nextEncounter(); $0.history.removeAll() } }
                }.disabled(store.busy)
            }
        }
    }

    @State private var copiedSummary = false

    private func ShareNotice() -> some View {
        Group {
            if copiedSummary { Text(L.t("code.copied")).accessibilityIdentifier("share.requested") }
        }
    }

    private func copySummaryCode(_ summary: Summary) {
        do {
            let members = summary.encounter.ordered
            let code = try BoardFiles.code(Roster(name: summary.encounter.name ?? L.t("live.title"), members: members))
            if !Launch.testing { UIPasteboard.general.string = code }
            copiedSummary = true
        } catch { store.error = error as? BoardError ?? .format }
    }

    private func top<Trailing: View>(title: String, subtitle: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title.bold()).accessibilityAddTraits(.isHeader)
                Text(subtitle).font(.subheadline).foregroundStyle(table ? Palette.light : Palette.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }.padding(.vertical, 4)
    }

    private func update(_ change: @escaping (inout PlayState) throws -> Void) {
        Task { _ = await store.save { board in try board.change(change) } }
    }

    private func showPro() { focus = nil; sheet = .paywall }

    private func setTable(_ enabled: Bool) {
        guard enabled != table else { return }
        if enabled {
            tablePriorIdle = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
        } else { UIApplication.shared.isIdleTimerDisabled = tablePriorIdle }
        table = enabled
    }

    private func resumeFromLink() {
        if let deepLink, deepLink.path.isEmpty || UUID(uuidString: deepLink.lastPathComponent) == encounter.id {
            focus = nil
            sheet = nil
            setTable(false)
        }
        deepLink = nil
    }
}
