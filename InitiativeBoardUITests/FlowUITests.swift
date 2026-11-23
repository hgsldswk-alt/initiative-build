import CoreGraphics
import Foundation
import XCTest

final class FlowUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        executionTimeAllowance = 900
    }

    private func launch(_ arguments: [String] = [], language: String = "en", reset: Bool = true,
                        environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(\(language))",
                               "-AppleLocale", language == "en" ? "en_US" : language]
        if reset { app.launchArguments.append("-reset") }
        app.launchArguments += arguments
        app.launchEnvironment = environment
        app.launch()
        return app
    }

    @discardableResult private func visible(_ element: XCUIElement, in app: XCUIApplication,
                                            file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        if element.waitForExistence(timeout: 5), element.isHittable { return element }
        for _ in 0..<4 {
            app.swipeUp()
            if element.exists && element.isHittable { return element }
        }
        XCTAssertTrue(element.exists && element.isHittable, "\(element)", file: file, line: line)
        return element
    }

    private func replace(_ field: XCUIElement, with value: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        if let old = field.value as? String, old != field.placeholderValue, !old.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count + 2))
        }
        field.typeText(value)
    }

    private func waitForText(_ text: String, identifier: String, in app: XCUIApplication) {
        let query = app.staticTexts.matching(identifier: identifier)
            .matching(NSPredicate(format: "label == %@", text))
        XCTAssertTrue(query.firstMatch.waitForExistence(timeout: 6), "Expected \(text) at \(identifier)")
    }

    func testFreshInstallManualOrderAdvanceUndoAndResume() {
        var app = launch(environment: ["INITIATIVE_TEST_DATE": "2026-11-24T23:58:00Z"])
        for (name, score) in [("Haze", "-7"), ("Reed", "0")] {
            replace(app.textFields["home.name"], with: name)
            replace(app.textFields["home.score"], with: score)
            visible(app.buttons["home.add"], in: app).tap()
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name))
                .firstMatch.waitForExistence(timeout: 5))
        }
        visible(app.buttons["home.start"], in: app).tap()
        waitForText("Reed", identifier: "turn.now", in: app)
        waitForText("Haze", identifier: "turn.next", in: app)
        app.buttons["live.advance"].tap()
        waitForText("Haze", identifier: "turn.now", in: app)
        app.buttons["live.undo"].tap()
        waitForText("Reed", identifier: "turn.now", in: app)
        app.buttons["live.advance"].tap()
        waitForText("Haze", identifier: "turn.now", in: app)
        app.terminate()
        app = launch(reset: false, environment: ["INITIATIVE_TEST_DATE": "2026-11-25T00:02:00Z"])
        waitForText("Haze", identifier: "turn.now", in: app)
    }

    func testCombatantEditingAndTablePrivacy() {
        let app = launch(["-demo", "-scene", "live"])
        waitForText("Rowan", identifier: "turn.now", in: app)
        visible(app.buttons["live.add"], in: app).tap()
        replace(app.textFields["edit.name"], with: "New ally")
        replace(app.textFields["edit.score"], with: "30")
        visible(app.buttons["edit.save"], in: app).tap()
        visible(app.buttons["member.edit.0"], in: app).tap()
        replace(app.textFields["edit.name"], with: "New scout")
        visible(app.buttons["edit.save"], in: app).tap()
        visible(app.buttons["live.table"], in: app).tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Hidden turn"))
            .firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Sentinel"].exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "member.hp.")).firstMatch.exists)
        visible(app.buttons["table.exit"], in: app).tap()
        visible(app.buttons["live.advance"], in: app).tap()
        waitForText("Ash", identifier: "turn.now", in: app)
    }

    func testRosterReloadAndManualCodeImport() throws {
        let app = launch(["-demo", "-scene", "setup"])
        visible(app.buttons["home.rosters"], in: app).tap()
        visible(app.buttons["roster.load.0"], in: app).tap()
        visible(app.buttons["member.edit.0"], in: app).tap()
        let initiative = app.textFields["edit.score"]
        XCTAssertTrue(initiative.exists)
        XCTAssertTrue((initiative.value as? String ?? "") == (initiative.placeholderValue ?? "0")
                      || (initiative.value as? String ?? "").isEmpty)
        visible(app.buttons["sheet.close"], in: app).tap()
        visible(app.buttons["home.rosters"], in: app).tap()
        visible(app.buttons["roster.paste"], in: app).tap()
        let json = Data(#"{"version":1,"name":"New table","members":["Moss","Ivy"]}"#.utf8)
        let code = "IT1:" + json.base64EncodedString().replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        let editor = app.textViews["code.input"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText(code)
        visible(app.buttons["code.previewButton"], in: app).tap()
        waitForText("New table", identifier: "code.preview", in: app)
        visible(app.buttons["code.add"], in: app).tap()
        visible(app.buttons["roster.load.1"], in: app).tap()
        XCTAssertTrue(app.buttons["member.edit.0"].waitForExistence(timeout: 5))
    }

    func testRecapShareAndUndoFinish() {
        let app = launch(["-demo", "-scene", "live"])
        visible(app.buttons["live.finish"], in: app).tap()
        visible(app.buttons["summary.share"], in: app).tap()
        XCTAssertTrue(app.descendants(matching: .any)["share.preview"].firstMatch.waitForExistence(timeout: 5))
        visible(app.buttons["share.image"], in: app).tap()
        XCTAssertTrue(app.staticTexts["share.requested"].waitForExistence(timeout: 8))
        visible(app.buttons["sheet.close"], in: app).tap()
        visible(app.buttons["summary.undo"], in: app).tap()
        waitForText("Rowan", identifier: "turn.now", in: app)
    }

    func testExpiredTrialLeavesFreeFlowAndKeepsExistingHP() {
        let app = launch(["-demo", "-scene", "setup", "-expired"])
        visible(app.buttons["home.start"], in: app).tap()
        waitForText("Vale", identifier: "turn.now", in: app)
        visible(app.buttons["member.hp.0"], in: app).tap()
        XCTAssertTrue(app.buttons["paywall.buy"].waitForExistence(timeout: 5))
        app.buttons["paywall.buy"].tap()
        XCTAssertTrue(app.staticTexts["Lifetime Pro unlocked"].waitForExistence(timeout: 5))
        visible(app.buttons["sheet.close"], in: app).tap()
        visible(app.buttons["member.hp.0"], in: app).tap()
        replace(app.textFields["hp.amount"], with: "4")
        visible(app.buttons["hp.damage"], in: app).tap()
        visible(app.buttons["live.advance"], in: app).tap()
        waitForText("Rowan", identifier: "turn.now", in: app)
    }

    func testReachableControlsWithAccessibilityTextSize() {
        let app = launch(["-demo", "-scene", "live", "-UIPreferredContentSizeCategoryName",
                          "UICTContentSizeCategoryAccessibilityXXXL"])
        let next = visible(app.buttons["live.advance"], in: app)
        XCTAssertGreaterThanOrEqual(next.frame.height, 44)
        next.tap()
        waitForText("Ash", identifier: "turn.now", in: app)
        let table = visible(app.buttons["live.table"], in: app)
        XCTAssertGreaterThanOrEqual(table.frame.height, 44)
        table.tap()
        let advance = visible(app.buttons["table.advance"], in: app)
        XCTAssertGreaterThanOrEqual(advance.frame.height, 44)
    }

    func testStoreScreenshots() {
        for language in ["en", "zh-Hans", "zh-Hant"] {
            let screens: [(String, String)] = [
                ("01-setup", "setup"), ("02-live", "live"), ("03-table", "table"),
                ("04-resume", "live"), ("05-rosters", "setup")
            ]
            for (filename, scene) in screens {
                var app = launch(["-demo", "-scene", scene], language: language)
                switch filename {
                case "01-setup":
                    _ = visible(app.buttons["home.start"], in: app)
                case "02-live":
                    _ = visible(app.buttons["live.advance"], in: app)
                case "03-table":
                    _ = visible(app.buttons["table.advance"], in: app)
                case "04-resume":
                    _ = visible(app.buttons["live.advance"], in: app)
                    let next = ["en": "Ash", "zh-Hans": "阿什", "zh-Hant": "阿什"][language]!
                    app.buttons["live.advance"].tap()
                    waitForText(next, identifier: "turn.now", in: app)
                    app.terminate()
                    app = launch(language: language, reset: false)
                    waitForText(next, identifier: "turn.now", in: app)
                default:
                    visible(app.buttons["home.rosters"], in: app).tap()
                    _ = visible(app.buttons["roster.load.0"], in: app)
                }
                capture("store-\(language)-\(filename)")
                app.terminate()
            }
        }
    }

    func testPaidScreenshot() {
        let app = launch(["-paywall"], language: "zh-Hans")
        XCTAssertTrue(app.buttons["paywall.buy"].waitForExistence(timeout: 5))
        capture("paid-01-paywall")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
