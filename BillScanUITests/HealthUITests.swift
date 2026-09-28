import XCTest

final class HealthUITests: XCTestCase {
    @MainActor func testArchivePrescriptionAndEditorFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--health-demo"]
        app.launch()
        XCTAssertTrue(app.staticTexts["病症档案"].waitForExistence(timeout: 15))
        capture("01-病症档案")
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "这次感冒")).firstMatch.tap()
        XCTAssertTrue(app.buttons["添加资料"].waitForExistence(timeout: 5))
        capture("02-档案详情")
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "门诊药方", "当前药方")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["药品与用法"].waitForExistence(timeout: 5))
        capture("03-药方详情")
        app.buttons["编辑"].tap()
        XCTAssertTrue(app.navigationBars["编辑资料"].waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
        app.buttons["放弃修改"].tap()
        app.swipeUp()
        app.buttons["归入历史药方"].tap()
        XCTAssertTrue(app.staticTexts["历史药方 · 提醒已关闭"].waitForExistence(timeout: 5))
        app.buttons["恢复为当前药方"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "用药提醒")).firstMatch.exists)
    }
    @MainActor func testCreateManualRecordAndSave() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--health-demo"]
        app.launch()
        app.buttons["添加病历 / 药方"].tap()
        XCTAssertTrue(app.textFields["episodeName"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["保存"].isEnabled)
        app.textFields["episodeName"].tap()
        app.textFields["episodeName"].typeText("Follow up")
        app.swipeUp()
        let text = app.textViews["documentText"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.tap(); text.typeText("Manual medical record. Follow up in one week.")
        app.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts["病症档案"].waitForExistence(timeout: 5))
        let folder = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Follow up")).firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 5))
        folder.tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "门诊病历")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Manual medical record. Follow up in one week."].waitForExistence(timeout: 5))
        app.buttons["资料操作"].tap()
        app.buttons["删除资料"].tap()
        app.buttons["删除资料"].tap()
        XCTAssertTrue(app.staticTexts["还没有资料"].waitForExistence(timeout: 5))
    }

    @MainActor func testReminderRequiresConfirmedMedicineAndCanBeSaved() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--health-demo"]
        app.launch()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "这次感冒")).firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "门诊药方", "当前药方")).firstMatch.tap()
        app.swipeUp()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "用药提醒")).firstMatch.tap()
        XCTAssertTrue(app.switches["示例药品 A"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["示例药品 B"].isEnabled)
        app.switches["示例药品 A"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        capture("04-提醒设置")
        XCTAssertTrue(app.staticTexts["第 1 次"].waitForExistence(timeout: 3))
        app.buttons["保存"].tap()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = system.buttons["Allow"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        else if system.buttons["允许"].exists { system.buttons["允许"].tap() }
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "已设置")).firstMatch.waitForExistence(timeout: 8))
        app.buttons["归入历史药方"].tap()
        XCTAssertTrue(app.staticTexts["历史药方 · 提醒已关闭"].waitForExistence(timeout: 5))
    }

    @MainActor func testPrescriptionFilterSeparatesCurrentAndHistory() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--health-demo"]
        app.launch()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "这次感冒")).firstMatch.tap()
        app.segmentedControls.buttons["药方"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "门诊药方", "当前药方")).firstMatch.exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "门诊药方", "历史药方")).firstMatch.exists)
        app.segmentedControls.buttons["历史药方"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "门诊药方", "历史药方")).firstMatch.exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "门诊药方", "当前药方")).firstMatch.exists)
    }

    @MainActor func testEditingMedicationSavesAndRequiresReconfirmation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--health-demo"]
        app.launch()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "这次感冒")).firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "门诊药方", "当前药方")).firstMatch.tap()
        app.buttons["编辑"].tap()
        let medicine = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "示例药品 A")).firstMatch
        for _ in 0..<3 { if medicine.isHittable { break }; app.swipeUp() }
        medicine.tap()
        let dose = app.textFields["每次用量，例如：1片"]
        XCTAssertTrue(dose.waitForExistence(timeout: 5))
        dose.tap()
        let length = (dose.value as? String ?? "").count
        dose.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: length) + "2 tablets")
        XCTAssertEqual(app.switches["我已按原药方核对以上信息"].value as? String, "0")
        app.navigationBars["药品用法"].buttons.element(boundBy: 0).tap()
        app.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "2 tablets")).firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
