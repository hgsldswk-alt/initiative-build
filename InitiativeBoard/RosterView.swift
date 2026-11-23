import SwiftUI
import UniformTypeIdentifiers
import UIKit

private struct BackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw BoardError.format }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct RosterView: View {
    @ObservedObject var store: BoardStore
    @ObservedObject var access: StoreAccess
    var onPro: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var input: String?
    @State private var codeRoster: Roster?
    @State private var fileBackup: BoardFiles.Backup?
    @State private var editing: Roster?
    @State private var draftName = ""
    @State private var draftMembers = ""
    @State private var issue: BoardError?
    @State private var note: String?
    @State private var importing = false
    @State private var exporting = false
    @State private var exportingData: BackupDocument?

    private var inBattle: Bool { store.board.play.active.turn != nil && store.board.play.summary == nil }
    private var rosters: [Roster] { store.board.rosters }
    private var canCreate: Bool { access.hasPro || rosters.allSatisfy(\.staged) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SheetHeader(key: "rosters") {
                    if input != nil || fileBackup != nil || editing != nil { clear() } else { dismiss() }
                }
                if let input { codeEntry(input) }
                else if let fileBackup { filePreview(fileBackup) }
                else if let editing { editor(editing) }
                else { list }
                if let issue = issue ?? store.error {
                    Text(L.t("error." + issue.rawValue)).font(.footnote).foregroundStyle(Palette.accent)
                        .accessibilityIdentifier("roster.error")
                }
                if let note {
                    Text(L.t(note)).font(.footnote).accessibilityIdentifier("share.requested")
                }
            }.padding(20)
        }
        .background(Palette.paper)
        .scrollDismissesKeyboard(.interactively)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .data]) { result in
            if case let .success(url) = result {
                Task {
                    do { fileBackup = try await store.importFile(url) }
                    catch { issue = error as? BoardError ?? .format }
                }
            } else if case let .failure(error) = result, (error as NSError).code != NSUserCancelledError {
                issue = .storage
            }
        }
        .fileExporter(isPresented: $exporting, document: exportingData, contentType: .json,
                      defaultFilename: L.t("backup.filename")) { result in
            if case .success = result { note = "backup.saved" }
            if case let .failure(error) = result, (error as NSError).code != NSUserCancelledError { issue = .storage }
        }
    }

    private var list: some View {
        Group {
            if rosters.isEmpty { Text(L.t("roster.empty")).foregroundStyle(Palette.muted).modifier(Panel()) }
            ForEach(Array(rosters.enumerated()), id: \.element.id) { index, roster in rosterRow(roster, index: index) }
            if !store.board.savedDrafts.isEmpty {
                Text(L.t("roster.savedDrafts")).font(.headline)
                ForEach(Array(store.board.savedDrafts.enumerated()), id: \.element.id) { index, draft in
                    BoardButton(draft.name == nil ? "roster.savedDraft" : "roster.restore", id: "draft.load.\(index)", kind: .bordered) {
                        restoreDraft(draft)
                    }
                    if let name = draft.name { Text(name).font(.footnote) }
                }
            }
            BoardButton("roster.new", id: "roster.new", kind: .bordered) {
                if canCreate {
                    beginEdit(Roster(name: store.board.play.active.name ?? "",
                                     members: Roster.template(store.board.play.active.ordered)))
                } else { onPro() }
            }
            HStack {
                BoardButton("code.paste", id: "roster.paste", kind: .bordered) {
                    clear()
                    input = Launch.testing ? ProcessInfo.processInfo.environment["INITIATIVE_TEST_CODE"] ?? "" : UIPasteboard.general.string ?? ""
                    validateCode(report: false)
                }
                BoardButton("backup.import", id: "roster.import", kind: .bordered) { clear(); importing = true }
            }
            BoardButton("backup.export", id: "roster.export", kind: .bordered) { exportBackup() }
            BoardButton("pro", id: "roster.pro", action: onPro)
        }
    }

    private func rosterRow(_ roster: Roster, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                Task {
                    if inBattle {
                        note = "roster.inProgress"
                    } else if await store.save({ $0.load(roster) }) {
                        dismiss()
                    }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(roster.name).font(.headline)
                        Text(L.f("participants", roster.members.count)).font(.footnote).foregroundStyle(Palette.muted)
                        if roster.staged { Text(L.t("roster.staged")).font(.footnote).foregroundStyle(Palette.accent) }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Palette.accent)
                }.frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("roster.load.\(index)")
            HStack {
                BoardButton("code.copy", id: "roster.copy.\(index)") { copyCode(roster) }
                Spacer()
                BoardButton("edit", id: "roster.edit.\(index)") {
                    let freeRoster = rosters.first(where: { !$0.staged }) ?? rosters.first
                    if access.hasPro || freeRoster?.id == roster.id { beginEdit(roster) }
                    else { onPro() }
                }
            }
        }.modifier(Panel())
    }

    private func beginEdit(_ roster: Roster) {
        clear()
        editing = roster
        draftName = roster.name
        draftMembers = roster.members.map(\.name).joined(separator: "\n")
    }

    private func editor(_ roster: Roster) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            BoardField(key: "roster.name", placeholder: "roster.name", id: "roster.name", value: $draftName)
            Text(L.t("roster.lines")).font(.subheadline)
            TextEditor(text: $draftMembers).frame(minHeight: 130).padding(4)
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.line).allowsHitTesting(false) }
                .accessibilityLabel(L.t("roster.lines")).accessibilityIdentifier("roster.members")
            BoardButton("save", id: "roster.save", kind: .primary) { saveRoster(roster) }.disabled(store.busy)
            if rosters.contains(where: { $0.id == roster.id }) {
                BoardButton("remove", id: "roster.remove") {
                    Task {
                        if await store.save({ $0.rosters.removeAll { $0.id == roster.id } }) { clear() }
                    }
                }.disabled(store.busy)
            }
        }
    }

    private func saveRoster(_ roster: Roster) {
        let title = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        let names = draftMembers.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard Combatant.validName(title), !names.isEmpty, names.allSatisfy(Combatant.validName) else { issue = .name; return }
        guard names.count <= Encounter.maxMembers else { issue = .limit; return }
        var unmatched = roster.members
        let members = names.map { name -> Combatant in
            if let matched = unmatched.firstIndex(where: { $0.name == name }) { return unmatched.remove(at: matched) }
            return Combatant(name: name)
        }
        var edited = roster
        edited.name = title
        edited.members = members
        if rosters.allSatisfy(\.staged) { edited.staged = false }
        Task {
            if await store.save({ board in
                if let index = board.rosters.firstIndex(where: { $0.id == roster.id }) {
                    board.rosters[index] = edited
                } else { board.rosters.append(edited) }
            }) { clear() }
        }
    }

    private func codeEntry(_ value: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.t("code.instructions")).foregroundStyle(Palette.muted)
            TextEditor(text: Binding(get: { input ?? value }, set: {
                input = $0
                codeRoster = nil
                issue = nil
            }))
            .font(.system(.body, design: .monospaced)).frame(minHeight: 100)
            .autocorrectionDisabled().textInputAutocapitalization(.never).padding(4)
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.line).allowsHitTesting(false) }
            .accessibilityLabel(L.t("code.label")).accessibilityIdentifier("code.input")
            if let roster = codeRoster {
                Text(roster.name).font(.headline).accessibilityIdentifier("code.preview")
                ForEach(roster.members) { Text($0.name) }
                BoardButton("roster.add", id: "code.add", kind: .primary) { saveImport(roster) }
                    .disabled(store.busy)
            } else {
                BoardButton("code.preview", id: "code.previewButton", kind: .primary) { validateCode(report: true) }
            }
        }.modifier(Panel())
    }

    private func validateCode(report: Bool) {
        guard let input, !input.isEmpty else { if report { issue = .format }; return }
        do { codeRoster = try BoardFiles.readCode(input); issue = nil }
        catch { if report { issue = error as? BoardError ?? .format } }
    }

    private func saveImport(_ roster: Roster) {
        let canCreate = canCreate
        Task {
            if await store.save({ board in
                if inBattle || canCreate {
                    var copy = roster
                    copy.staged = inBattle
                    board.rosters.append(copy)
                } else { board.load(roster) }
            }) {
                clear()
                note = inBattle ? "roster.staged" : "roster.added"
                if !inBattle && !canCreate { dismiss() }
            }
        }
    }

    private func filePreview(_ backup: BoardFiles.Backup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.t("backup.preview")).font(.headline)
            ForEach(Array(backup.rosters.enumerated()), id: \.offset) { _, roster in
                Text(roster.name)
            }
            if let encounter = backup.encounter { Text(encounter.name ?? L.t("live.title")).foregroundStyle(Palette.muted) }
            Text(L.f("backup.drafts", backup.drafts.count)).font(.footnote)
            BoardButton("backup.save", id: "backup.save", kind: .primary) {
                Task {
                    if await store.save({ board in
                        var spareFreeSlot = board.rosters.allSatisfy(\.staged)
                        for roster in backup.rosters {
                            var copy = roster
                            copy.id = UUID()
                            copy.staged = inBattle || (!access.hasPro && !spareFreeSlot)
                            if !copy.staged { spareFreeSlot = false }
                            board.rosters.append(copy)
                        }
                        for encounter in backup.drafts + [backup.encounter].compactMap({ $0 }) {
                            var copy = encounter
                            copy.id = UUID()
                            copy.proInBattle = access.hasPro
                            board.savedDrafts.append(copy)
                        }
                    }) { clear(); note = "backup.saved" }
                }
            }.disabled(store.busy)
        }.modifier(Panel())
    }

    private func restoreDraft(_ draft: Encounter) {
        guard !inBattle else { note = "roster.staged"; return }
        Task {
            if await store.save({ board in
                board.savedDrafts.removeAll { $0.id == draft.id }
                if !board.play.active.members.isEmpty { board.savedDrafts.append(board.play.active) }
                board.play.active = draft
                if board.play.active.turn != nil { board.play.active.proInBattle = access.hasPro }
                board.play.summary = nil
                board.history.removeAll()
            }) { dismiss() }
        }
    }

    private func exportBackup() {
        Task {
            do {
                let data = try await store.backup()
                if Launch.testing { note = "backup.saved" }
                else { exportingData = BackupDocument(data: data); exporting = true }
            } catch {
                issue = error as? BoardError ?? .storage
            }
        }
    }

    private func copyCode(_ roster: Roster) {
        do {
            let code = try BoardFiles.code(roster)
            if !Launch.testing { UIPasteboard.general.string = code }
            note = "code.copied"
            issue = nil
        } catch { issue = error as? BoardError ?? .format }
    }

    private func clear() {
        input = nil
        codeRoster = nil
        fileBackup = nil
        editing = nil
        issue = nil
        note = nil
    }
}
