import SwiftUI

struct CombatantEditor: View {
    let member: Combatant?
    let live: Bool
    let canEditHP: Bool
    @ObservedObject var store: BoardStore
    var onPro: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var score: String
    @State private var maxHP: String
    @State private var visible: Bool
    @State private var issue: BoardError?
    @State private var removing = false
    @FocusState private var focus: Field?
    private enum Field: Hashable { case name, score, hp }

    init(member: Combatant?, live: Bool, canEditHP: Bool, store: BoardStore, onPro: @escaping () -> Void) {
        self.member = member
        self.live = live
        self.canEditHP = canEditHP
        self.store = store
        self.onPro = onPro
        _name = State(initialValue: member?.name ?? "")
        _score = State(initialValue: member?.score.map(String.init) ?? "")
        _maxHP = State(initialValue: member?.maxHP.map(String.init) ?? "")
        _visible = State(initialValue: member?.visible ?? true)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SheetHeader(key: member == nil ? "add.title" : "edit.title") { dismiss() }
                BoardField(key: "name", placeholder: "name.placeholder", id: "edit.name", value: $name)
                    .focused($focus, equals: .name).submitLabel(.next).onSubmit { focus = .score }
                BoardField(key: "initiative", placeholder: "score.placeholder", id: "edit.score", value: $score)
                    .focused($focus, equals: .score).keyboardType(.numbersAndPunctuation).submitLabel(.done).onSubmit(save)
                Toggle(L.t("table.visible"), isOn: $visible).frame(minHeight: 44)
                    .accessibilityIdentifier("edit.visible")
                if canEditHP {
                    BoardField(key: "hp.max", placeholder: "optional", id: "edit.hp", value: $maxHP)
                        .focused($focus, equals: .hp).keyboardType(.numberPad)
                } else if member?.maxHP == nil {
                    BoardButton("hp.pro", id: "edit.pro", action: onPro)
                }
                if let issue = issue ?? store.error {
                    Text(L.t("error." + issue.rawValue)).foregroundStyle(Palette.accent)
                        .accessibilityIdentifier("edit.error")
                }
                BoardButton(member == nil ? "add" : "save", id: "edit.save", kind: .primary, action: save)
                    .disabled(store.busy)
                if let member {
                    BoardButton("remove", id: "edit.remove") { removing = true }
                        .disabled(store.busy)
                        .confirmationDialog(L.t("remove.title"), isPresented: $removing, titleVisibility: .visible) {
                            Button(L.t("remove"), role: .destructive) {
                                Task {
                                    if await store.save({ board in board.change { $0.active.remove(member.id) } }) {
                                        dismiss()
                                    }
                                }
                            }
                        }
                }
            }.padding(20)
        }.background(Palette.paper)
    }

    private func save() {
        var updated = member ?? Combatant(name: name)
        do {
            updated.name = name
            updated.score = try Combatant.parseScore(score)
            if live && updated.score == nil { throw BoardError.score }
            updated.visible = visible
            if canEditHP {
                let text = maxHP.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty {
                    updated.hp = nil
                    updated.maxHP = nil
                } else if let maximum = Int(text), (1...9999).contains(maximum) {
                    updated.hp = min(updated.hp ?? maximum, maximum)
                    updated.maxHP = maximum
                } else { throw BoardError.hp }
            }
            updated = try updated.validated()
        } catch {
            issue = error as? BoardError ?? .format
            return
        }
        let value = updated
        issue = nil
        Task {
            if await store.save({ board in try board.change { try $0.active.put(value) } }) { dismiss() }
        }
    }
}

struct HealthView: View {
    let member: Combatant
    @ObservedObject var store: BoardStore
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var invalid = false
    @State private var bypass = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SheetHeader(key: "hp.title") { dismiss() }
                Text(member.name).font(.headline)
                if let hp = member.hp, let maxHP = member.maxHP {
                    Text(L.f("hp.value", hp, maxHP)).font(.largeTitle.bold())
                }
                BoardField(key: "hp.amount", placeholder: "score.placeholder", id: "hp.amount", value: $amount)
                    .keyboardType(.numberPad)
                if let issue = store.error ?? (invalid ? .hp : nil) {
                    Text(L.t("error." + issue.rawValue)).foregroundStyle(Palette.accent)
                }
                HStack {
                    BoardButton("hp.damage", id: "hp.damage", kind: .bordered) { change(heal: false) }
                    BoardButton("hp.heal", id: "hp.heal", kind: .primary) { change(heal: true) }
                }.disabled(store.busy || bypass)
            }.padding(20)
        }.background(Palette.paper)
    }

    private func change(heal: Bool) {
        guard !bypass, let value = Int(amount), (1...9999).contains(value),
              let current = member.hp, let maximum = member.maxHP else { invalid = true; return }
        bypass = true
        var updated = member
        updated.hp = min(maximum, max(0, current + (heal ? value : -value)))
        Task {
            if await store.save({ board in try board.change { try $0.active.put(updated) } }) { dismiss() }
            else { bypass = false }
        }
    }
}
