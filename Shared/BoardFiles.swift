import Foundation

enum BoardFiles {
    static let maxCodeBytes = 8192
    static let maxBackupBytes = 2_000_000
    static let version = 1

    private struct Code: Codable {
        var version: Int
        var name: String
        var members: [String]
    }

    struct Backup: Codable {
        var version = BoardFiles.version
        var rosters: [Roster]
        var drafts: [Encounter]
        var encounter: Encounter?
    }

    private struct Header: Codable { var version: Int }

    static func code(_ roster: Roster) throws -> String {
        let names = roster.members.filter(\.visible).map(\.name)
        guard !names.isEmpty else { throw BoardError.noPublic }
        let payload = Code(version: version, name: roster.name, members: names)
        _ = try rosterFromCode(payload)
        let encoded = try JSONEncoder().encode(payload).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let code = "IT1:" + encoded
        guard code.utf8.count <= maxCodeBytes else { throw BoardError.limit }
        return code
    }

    static func readCode(_ text: String) throws -> Roster {
        guard text.utf8.count <= maxCodeBytes else { throw BoardError.limit }
        let code = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.hasPrefix("IT1:") else {
            throw code.hasPrefix("IT") ? BoardError.version : BoardError.format
        }
        let payload = String(code.dropFirst(4))
        guard !payload.isEmpty, payload.utf8.allSatisfy({
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }) else { throw BoardError.format }
        var base64 = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64), String(data: data, encoding: .utf8) != nil else { throw BoardError.format }
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: data) else { throw BoardError.format }
        guard header.version == version else { throw BoardError.version }
        guard let decoded = try? decoder.decode(Code.self, from: data),
              let fields = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(fields.keys) == ["version", "name", "members"] else { throw BoardError.format }
        return try rosterFromCode(decoded)
    }

    private static func rosterFromCode(_ code: Code) throws -> Roster {
        guard Combatant.validName(code.name), !code.members.isEmpty else { throw BoardError.format }
        guard code.members.count <= Encounter.maxMembers else { throw BoardError.limit }
        return Roster(name: code.name, members: try code.members.map { try Combatant(name: $0).validated() })
    }

    static func backup(_ board: Board) throws -> Data {
        let data = try JSONEncoder().encode(Backup(rosters: board.rosters, drafts: board.savedDrafts,
                                                   encounter: board.play.active.members.isEmpty ? nil : board.play.active))
        guard data.count <= maxBackupBytes else { throw BoardError.limit }
        return data
    }

    static func readBackup(_ data: Data) throws -> Backup {
        guard data.count <= maxBackupBytes else { throw BoardError.limit }
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: data) else { throw BoardError.format }
        guard header.version == version else { throw BoardError.version }
        guard let backup = try? decoder.decode(Backup.self, from: data) else { throw BoardError.format }
        for roster in backup.rosters {
            guard Combatant.validName(roster.name) else { throw BoardError.name }
            try validate(roster.members)
        }
        for encounter in backup.drafts + [backup.encounter].compactMap({ $0 }) { try validate(encounter) }
        return backup
    }

    static func validate(_ encounter: Encounter) throws {
        try validate(encounter.members)
        if let name = encounter.name, !Combatant.validName(name) { throw BoardError.name }
        guard Set(encounter.participants.map(\.id)).count == encounter.participants.count else { throw BoardError.format }
        for participant in encounter.participants { _ = try participant.validated() }
        let members = Set(encounter.members.map(\.id))
        if let order = encounter.manualOrder {
            guard Set(order) == members, order.count == members.count else { throw BoardError.format }
        }
        if let turn = encounter.turn {
            guard (1...1_000_000).contains(turn.round), (0...1_000_000).contains(turn.advances),
                  encounter.members.allSatisfy({ $0.score != nil }),
                  turn.acted.isSubset(of: members), turn.deferred.isSubset(of: members),
                  turn.acted.isDisjoint(with: turn.deferred), (turn.current == nil) == members.isEmpty,
                  turn.current.map({ members.contains($0) && !turn.acted.contains($0) && !turn.deferred.contains($0) }) ?? true
            else { throw BoardError.format }
        }
    }

    private static func validate(_ members: [Combatant]) throws {
        guard members.count <= Encounter.maxMembers else { throw BoardError.limit }
        guard Set(members.map(\.id)).count == members.count else { throw BoardError.format }
        for member in members { _ = try member.validated() }
    }
}

struct BoardDisk {
    let url: URL

    private struct Document: Codable { var version = 1; var board: Board }

    func load() throws -> Board {
        guard FileManager.default.fileExists(atPath: url.path) else { return Board() }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let board: Board
        if let document = try? decoder.decode(Document.self, from: data) {
            guard document.version == 1 else { throw BoardError.version }
            board = document.board
        } else {
            board = try decoder.decode(Board.self, from: data)
        }
        try BoardFiles.validate(board.play.active)
        if let summary = board.play.summary { try BoardFiles.validate(summary.encounter) }
        for state in board.history {
            try BoardFiles.validate(state.active)
            if let summary = state.summary { try BoardFiles.validate(summary.encounter) }
        }
        return board
    }

    func save(_ board: Board) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(Document(board: board)).write(to: url, options: .atomic)
    }
}
