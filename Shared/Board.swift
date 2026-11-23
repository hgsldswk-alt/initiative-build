import Foundation

enum BoardError: String, Error {
    case name, score, hp, limit, format, version, storage, noPublic
}

struct Combatant: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var score: Int?
    var hp: Int?
    var maxHP: Int?
    var visible = true

    var publicName: String { visible ? name : L.t("hidden") }

    static func parseScore(_ text: String) throws -> Int? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "−", with: "-")
        guard !text.isEmpty else { return nil }
        guard let value = Int(text), (-999...999).contains(value) else { throw BoardError.score }
        return value
    }

    func validated() throws -> Self {
        var result = self
        result.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.validName(result.name) else { throw BoardError.name }
        if let score, !(-999...999).contains(score) { throw BoardError.score }
        switch (hp, maxHP) {
        case (nil, nil): break
        case let (hp?, maxHP?) where (1...9999).contains(maxHP) && (0...maxHP).contains(hp): break
        default: throw BoardError.hp
        }
        return result
    }

    static func validName(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 60
            && name.utf8.count <= 240 && name.unicodeScalars.allSatisfy {
                $0.properties.generalCategory != .control && !CharacterSet.newlines.contains($0)
            }
    }
}

struct Roster: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var members: [Combatant]
    var staged = false

    static func template(_ members: [Combatant]) -> [Combatant] {
        members.map { Combatant(name: $0.name, hp: $0.maxHP, maxHP: $0.maxHP, visible: $0.visible) }
    }
}

struct TurnState: Codable, Equatable {
    var round = 1
    var current: UUID?
    var acted: Set<UUID> = []
    var deferred: Set<UUID> = []
    var advances = 0
}

struct Encounter: Codable, Equatable, Identifiable {
    static let maxMembers = 64
    var id = UUID()
    var name: String?
    var members: [Combatant] = []
    var manualOrder: [UUID]?
    var ascending = false
    var turn: TurnState?
    var proInBattle = false
    var participants: [Combatant] = []

    var ordered: [Combatant] {
        let ranks = Dictionary(uniqueKeysWithValues: (manualOrder ?? []).enumerated().map { ($1, $0) })
        return members.enumerated().sorted {
            if let first = ranks[$0.element.id], let second = ranks[$1.element.id] { return first < second }
            switch ($0.element.score, $1.element.score) {
            case let (a?, b?) where a != b: return ascending ? a < b : a > b
            case (nil, _?): return false
            case (_?, nil): return true
            default: return $0.offset < $1.offset
            }
        }.map(\.element)
    }
    var current: Combatant? { members.first { $0.id == turn?.current } }
    var remaining: [Combatant] {
        guard let turn else { return [] }
        return ordered.filter { $0.id != turn.current && !turn.acted.contains($0.id) && !turn.deferred.contains($0.id) }
    }
    var next: Combatant? { turn == nil ? nil : remaining.first ?? ordered.first }

    mutating func put(_ member: Combatant) throws {
        let edited = try member.validated()
        if let index = members.firstIndex(where: { $0.id == edited.id }) {
            let scoreChanged = members[index].score != edited.score
            members[index] = edited
            if scoreChanged { insertIntoManualOrder(edited) }
        } else {
            guard members.count < Self.maxMembers else { throw BoardError.limit }
            members.append(edited)
            insertIntoManualOrder(edited)
            if let anchor = turn?.current,
               let currentIndex = ordered.firstIndex(where: { $0.id == anchor }),
               let addedIndex = ordered.firstIndex(where: { $0.id == edited.id }), addedIndex < currentIndex {
                turn?.deferred.insert(edited.id)
            }
            let firstID = ordered.first?.id
            if turn != nil && turn?.current == nil { turn?.current = firstID }
        }
        if turn != nil {
            if let index = participants.firstIndex(where: { $0.id == edited.id }) {
                participants[index] = edited
            } else { participants.append(edited) }
        }
    }

    private mutating func insertIntoManualOrder(_ member: Combatant) {
        guard var order = manualOrder else { return }
        order.removeAll { $0 == member.id }
        let before = order.firstIndex { id in
            guard let score = member.score, let other = members.first(where: { $0.id == id }) else { return false }
            guard let old = other.score else { return true }
            return ascending ? score < old : score > old
        } ?? order.endIndex
        order.insert(member.id, at: before)
        manualOrder = order
    }

    mutating func reorder(_ ids: [UUID]) {
        guard ids.count == members.count, Set(ids) == Set(members.map(\.id)) else { return }
        manualOrder = ids
    }

    mutating func sort(_ ascending: Bool) {
        self.ascending = ascending
        manualOrder = nil
    }

    mutating func start(pro: Bool) throws {
        guard !members.isEmpty, members.allSatisfy({ $0.score != nil }) else { throw BoardError.score }
        turn = TurnState(current: ordered.first?.id)
        proInBattle = pro
        participants = ordered
    }

    mutating func advance() {
        guard var state = turn, let id = state.current else { return }
        let following = remaining.first
        state.advances += 1
        state.acted.insert(id)
        if let following { state.current = following.id }
        else { beginNextRound(&state) }
        turn = state
    }

    mutating func remove(_ id: UUID) {
        guard members.contains(where: { $0.id == id }) else { return }
        let successor = remaining.first?.id
        members.removeAll { $0.id == id }
        manualOrder?.removeAll { $0 == id }
        guard var state = turn else { return }
        state.acted.remove(id)
        state.deferred.remove(id)
        if state.current == id {
            if members.isEmpty { state.current = nil }
            else if let successor { state.current = successor }
            else { beginNextRound(&state) }
        }
        turn = state
    }

    private func beginNextRound(_ state: inout TurnState) {
        state.round += 1
        state.acted = []
        state.deferred = []
        state.current = ordered.first?.id
    }
}

struct Summary: Codable, Equatable {
    var encounter: Encounter
    var milestone: Bool
}

struct PlayState: Codable, Equatable {
    var active = Encounter()
    var summary: Summary?
    var validEncounters: Set<UUID> = []
    var review = ReviewProgress()

    mutating func finish() {
        guard let turn = active.turn, summary == nil else { return }
        let count = validEncounters.count
        if turn.advances >= 2 {
            validEncounters.insert(active.id)
            review.completedEncounter()
        }
        summary = Summary(encounter: active, milestone: count < 3 && validEncounters.count == 3)
    }

    mutating func nextEncounter() {
        active = Encounter(ascending: active.ascending)
        summary = nil
    }
}

struct Board: Codable, Equatable {
    var play = PlayState()
    var history: [PlayState] = []
    var rosters: [Roster] = []
    var savedDrafts: [Encounter] = []
    var widgetNames = false
    var appearance = "paper"

    mutating func change(_ apply: (inout PlayState) throws -> Void) rethrows {
        let previous = play
        try apply(&play)
        if play != previous {
            history.append(previous)
            if history.count > 40 { history.removeFirst() }
        }
    }

    mutating func undo() {
        guard let previous = history.popLast() else { return }
        let review = play.review
        play = previous
        play.review.keepUsage(from: review)
    }

    mutating func load(_ roster: Roster) {
        if play.active.turn != nil && play.summary == nil {
            var copy = roster
            copy.id = UUID()
            copy.staged = true
            rosters.append(copy)
            return
        }
        if play.summary == nil && !play.active.members.isEmpty { savedDrafts.append(play.active) }
        play.nextEncounter()
        play.active.name = roster.name
        play.active.members = Roster.template(roster.members)
        history.removeAll()
    }
}
