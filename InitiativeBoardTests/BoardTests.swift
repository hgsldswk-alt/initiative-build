import CoreImage
import Foundation
import XCTest

final class BoardTests: XCTestCase {
    private func encounter(_ scores: [Int], pro: Bool = false) throws -> Encounter {
        var fight = Encounter()
        for (index, score) in scores.enumerated() {
            try fight.put(Combatant(name: "Seat \(index)", score: score))
        }
        try fight.start(pro: pro)
        return fight
    }

    func testSignedIntegerAndStableTiesInBothDirections() throws {
        XCTAssertEqual(try Combatant.parseScore(" −12 "), -12)
        XCTAssertEqual(try Combatant.parseScore("+0"), 0)
        XCTAssertNil(try Combatant.parseScore(" "))
        for invalid in ["1000", "-1000", "4.0", "word"] { XCTAssertThrowsError(try Combatant.parseScore(invalid)) }
        let a = Combatant(name: "Same", score: 0)
        let b = Combatant(name: "same", score: 0)
        let c = Combatant(name: "Other", score: -1)
        var fight = Encounter(members: [a, b, c])
        XCTAssertEqual(fight.ordered.map(\.id), [a.id, b.id, c.id])
        fight.sort(true)
        XCTAssertEqual(fight.ordered.map(\.id), [c.id, a.id, b.id])
    }

    func testMissingRollCannotStartAndOneMemberWraps() throws {
        var empty = Encounter(members: [Combatant(name: "Zero")])
        XCTAssertThrowsError(try empty.start(pro: false))
        var fight = try encounter([0])
        let id = fight.current?.id
        fight.advance()
        XCTAssertEqual(fight.turn?.round, 2)
        XCTAssertEqual(fight.current?.id, id)
        XCTAssertEqual(fight.next?.id, id)
        if let id { fight.remove(id) }
        XCTAssertNil(fight.next)
        let late = Combatant(name: "Late", score: -1)
        try fight.put(late)
        XCTAssertEqual(fight.current?.id, late.id)
        XCTAssertEqual(fight.turn?.round, 2)
    }

    func testManualOrderAndEditsKeepCurrentAndActedRoles() throws {
        var fight = try encounter([19, 14, 10, 4])
        let original = fight.ordered
        fight.advance()
        fight.reorder([original[3].id, original[0].id, original[1].id, original[2].id])
        XCTAssertEqual(fight.current?.id, original[1].id)
        XCTAssertEqual(fight.next?.id, original[3].id)
        fight.advance()
        var updated = original[0]
        updated.score = -4
        try fight.put(updated)
        XCTAssertEqual(fight.current?.id, original[3].id)
        XCTAssertEqual(fight.next?.id, original[2].id)
        XCTAssertTrue(fight.turn?.acted.contains(original[0].id) == true)
    }

    func testReinforcementsAndCurrentRemoval() throws {
        var fight = try encounter([15, 10, 5])
        let original = fight.ordered
        fight.advance()
        let early = Combatant(name: "Early next round", score: 20)
        let late = Combatant(name: "Late this round", score: 8)
        try fight.put(early)
        try fight.put(late)
        XCTAssertEqual(fight.next?.id, late.id)
        XCTAssertTrue(fight.turn?.deferred.contains(early.id) == true)
        fight.remove(original[1].id)
        XCTAssertEqual(fight.current?.id, late.id)
        XCTAssertEqual(fight.turn?.round, 1)
        fight.remove(late.id)
        fight.remove(original[2].id)
        XCTAssertEqual(fight.current?.id, early.id)
        XCTAssertEqual(fight.turn?.round, 2)
    }

    func testManualOrderAcceptsReinforcementWithoutMovingExistingRows() throws {
        var fight = try encounter([15, 10, 5])
        let original = fight.ordered
        fight.reorder([original[0].id, original[2].id, original[1].id])
        let added = Combatant(name: "New", score: 7)
        try fight.put(added)
        XCTAssertEqual(fight.ordered.filter { $0.id != added.id }.map(\.id),
                       [original[0].id, original[2].id, original[1].id])
        XCTAssertEqual(fight.current?.id, original[0].id)
    }

    func testUndoRestoresHealthOrderRosterAndRound() throws {
        var board = Board()
        board.play.active = try encounter([12], pro: true)
        let initial = board.play
        let first = try XCTUnwrap(initial.active.current)
        var edited = first
        edited.hp = 0
        edited.maxHP = 10
        try board.change { try $0.active.put(edited) }
        XCTAssertEqual(board.play.active.current?.hp, 0)
        board.change { $0.active.advance() }
        XCTAssertEqual(board.play.active.turn?.round, 2)
        board.change { $0.active.remove(first.id) }
        board.undo()
        XCTAssertEqual(board.play.active.current?.hp, 0)
        board.undo()
        XCTAssertEqual(board.play.active.turn?.round, 1)
        board.undo()
        XCTAssertEqual(board.play, initial)
    }

    func testShortIntervalThrottle() {
        var throttle = AdvanceThrottle()
        XCTAssertTrue(throttle.accept(1))
        XCTAssertFalse(throttle.accept(1.1))
        XCTAssertFalse(throttle.accept(1.2))
        XCTAssertTrue(throttle.accept(1.4))
    }

    func testValidEncounterCountMilestoneAndUndoFinish() throws {
        var board = Board()
        for index in 1...3 {
            board.play.active = try encounter([4])
            for _ in 0..<2 { board.change { $0.active.advance() } }
            board.change { $0.finish() }
            XCTAssertEqual(board.play.validEncounters.count, index)
            XCTAssertEqual(board.play.summary?.milestone, index == 3)
            board.change { $0.finish() }
            XCTAssertEqual(board.play.validEncounters.count, index)
            if index == 3 {
                board.undo()
                XCTAssertNil(board.play.summary)
                board.change { $0.finish() }
                XCTAssertEqual(board.play.validEncounters.count, 3)
            }
            board.play.nextEncounter()
        }
    }

    func testRosterTemplateResetsScoresAndDamageAndPreservesDraft() {
        var board = Board()
        board.play.active.members = [Combatant(name: "Unsaved", score: 2)]
        board.load(Roster(name: "Group", members: [Combatant(name: "Test", score: 19, hp: 0, maxHP: 9)]))
        XCTAssertNil(board.play.active.members.first?.score)
        XCTAssertEqual(board.play.active.members.first?.hp, 9)
        XCTAssertEqual(board.savedDrafts.first?.members.first?.name, "Unsaved")
    }

    func testCodeRoundTripTransfersOnlySelectedPublicNamesAndOrder() throws {
        let roster = Roster(name: "Team", members: [
            Combatant(name: "風 隊長𠮷 👩‍👩‍👧", score: -2, hp: 4, maxHP: 7),
            Combatant(name: "Secret", visible: false), Combatant(name: "Player")
        ])
        let restored = try BoardFiles.readCode(BoardFiles.code(roster))
        XCTAssertEqual(restored.members.map(\.name), ["風 隊長𠮷 👩‍👩‍👧", "Player"])
        XCTAssertTrue(restored.members.allSatisfy { $0.score == nil && $0.hp == nil && $0.maxHP == nil })
        XCTAssertEqual(restored.name, roster.name)
    }

    func testCodeAndBackupRejectMalformedInputBeforeSaving() throws {
        for code in ["IT1:!!!", "IT1:_w", "IT2:AA", String(repeating: "a", count: 8193)] {
            XCTAssertThrowsError(try BoardFiles.readCode(code))
        }
        func encodedCode(_ json: String) -> String {
            "IT1:" + Data(json.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
                .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        }
        XCTAssertThrowsError(try BoardFiles.readCode(encodedCode(#"{"version":2,"name":"Test","members":["A"]}"#)))
        XCTAssertThrowsError(try BoardFiles.readCode(encodedCode(#"{"version":1,"name":"Test","members":["A"],"hp":10}"#)))
        XCTAssertThrowsError(try BoardFiles.readBackup(Data(#"{"version":2}"#.utf8)))
        XCTAssertThrowsError(try BoardFiles.readBackup(Data(#"{"version":1,"rosters":"#.utf8)))
        XCTAssertThrowsError(try BoardFiles.readBackup(Data(count: BoardFiles.maxBackupBytes + 1)))
        var fight = try encounter(Array(repeating: 0, count: 64))
        XCTAssertThrowsError(try fight.put(Combatant(name: "Too many", score: 1)))
    }

    func testOldBoardMigrationResumeAndIncompatibleDataIsPreserved() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("board.json")
        var board = Board()
        board.play.active = try encounter([17, 4])
        board.change { $0.active.advance() }
        try JSONEncoder().encode(board).write(to: file)
        let disk = BoardDisk(url: file)
        XCTAssertEqual(try disk.load(), board)
        try disk.save(board)
        XCTAssertEqual(try disk.load().play.active.current?.name, "Seat 1")
        XCTAssertEqual(try disk.load().history.count, 1)
        let broken = Data(#"{"version":17,"board":{}}"#.utf8)
        try broken.write(to: file)
        XCTAssertThrowsError(try disk.load())
        XCTAssertEqual(try Data(contentsOf: file), broken)
    }

    func testBackupRoundTripCarriesEncounterButNeverStoreRights() throws {
        var board = Board()
        board.play.active = try encounter([10, 5])
        board.play.active.advance()
        let data = try BoardFiles.backup(board)
        let restored = try BoardFiles.readBackup(data)
        XCTAssertEqual(restored.encounter, board.play.active)
        XCTAssertTrue(restored.rosters.isEmpty)
    }

    func testQRCodeResolvesAppStoreURLOnlyWithAnID() throws {
        XCTAssertNil(ShareQR.storeURL(""))
        XCTAssertNil(ShareQR.storeURL("abc"))
        let url = try XCTUnwrap(ShareQR.storeURL("1234567890"))
        let image = try XCTUnwrap(ShareQR.image(for: url))
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                                options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let features = detector.features(in: CIImage(cgImage: image)).compactMap { $0 as? CIQRCodeFeature }
        XCTAssertEqual(features.first?.messageString, "https://apps.apple.com/app/id1234567890")
    }
}
