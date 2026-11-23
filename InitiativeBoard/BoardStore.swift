import Foundation
import SwiftUI
import WidgetKit

private actor BoardRepository {
    func open() throws -> (BoardDisk, Board) {
        let files = FileManager.default
        let base = try files.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                 appropriateFor: nil, create: true)
        let name = Launch.testing ? "InitiativeBoardTests" : "InitiativeBoard"
        let disk = BoardDisk(url: base.appendingPathComponent(name).appendingPathComponent("board.json"))
        if Launch.has("-reset"), files.fileExists(atPath: disk.url.path) { try files.removeItem(at: disk.url) }
        return (disk, try disk.load())
    }

    func write(_ board: Board, to disk: BoardDisk) throws {
        try disk.save(board)
        guard !Launch.testing else { return }
        let encounter = board.play.active
        let snapshot: WidgetSnapshot? = board.play.summary == nil ? encounter.turn.map {
            WidgetSnapshot(id: encounter.id, round: $0.round,
                           current: board.widgetNames ? encounter.current?.publicName : nil,
                           next: board.widgetNames ? encounter.next?.publicName : nil)
        } : nil
        if WidgetSnapshot.load() != snapshot {
            WidgetSnapshot.save(snapshot)
            WidgetCenter.shared.reloadTimelines(ofKind: "InitiativeResume")
        }
    }

    func importFile(_ url: URL) throws -> BoardFiles.Backup {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: BoardFiles.maxBackupBytes + 1) ?? Data()
        return try BoardFiles.readBackup(data)
    }

    func export(_ board: Board) throws -> Data { try BoardFiles.backup(board) }
}

@MainActor final class BoardStore: ObservableObject {
    @Published private(set) var board = Board()
    @Published private(set) var ready = false
    @Published private(set) var busy = false
    @Published var error: BoardError?
    private let repository = BoardRepository()
    private var disk: BoardDisk?
    private var advanceTap = AdvanceThrottle()

    func open() async {
        guard !ready, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let (disk, original) = try await repository.open()
            var loaded = original
            if Launch.has("-demo"), loaded.play.active.members.isEmpty { try Self.seed(&loaded) }
            loaded.play.review.recordUse(on: Launch.usageDate)
            try await repository.write(loaded, to: disk)
            self.disk = disk
            board = loaded
            ready = true
        } catch { self.error = error as? BoardError ?? .storage }
    }

    func save(_ change: (inout Board) throws -> Void) async -> Bool {
        guard let disk, !busy else { return false }
        busy = true
        defer { busy = false }
        self.error = nil
        do {
            var updated = board
            updated.play.review.recordUse(on: Launch.usageDate)
            try change(&updated)
            if board != updated {
                try await repository.write(updated, to: disk)
                board = updated
            }
            return true
        } catch {
            self.error = error as? BoardError ?? .storage
            return false
        }
    }

    func advance() async {
        guard board.play.active.current != nil, !busy, advanceTap.accept(ProcessInfo.processInfo.systemUptime) else { return }
        _ = await save { board in board.change { $0.active.advance() } }
    }

    func importFile(_ url: URL) async throws -> BoardFiles.Backup { try await repository.importFile(url) }

    func backup() async throws -> Data { try await repository.export(board) }

    private static func seed(_ board: inout Board) throws {
        let roster = Roster(name: L.t("demo.group"), members: [
            Combatant(name: L.t("demo.name1"), hp: 24, maxHP: 24),
            Combatant(name: L.t("demo.name2"), hp: 18, maxHP: 18),
            Combatant(name: L.t("demo.name3")),
            Combatant(name: L.t("demo.secret"), visible: false)
        ])
        board.rosters = [roster]
        board.load(roster)
        let scores = [19, 16, 12, 8]
        for index in scores.indices { board.play.active.members[index].score = scores[index] }
        let mode = Launch.value("-scene")
        if ["live", "table", "summary"].contains(mode ?? "") {
            try board.play.active.start(pro: true)
            for _ in 0..<5 { board.play.active.advance() }
            if mode == "summary" { board.play.finish() }
        }
    }
}
