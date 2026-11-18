import XCTest

final class LibraryUITests: XCTestCase {
    func testPauseExitStaysVisibleAndCanBeCancelled() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-preview", "--paused-game"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        let play = app.buttons["play-selected"]
        XCTAssertTrue(play.waitForExistence(timeout: 20))
        play.tap()
        let discard = app.buttons["pause-exit-without-saving"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        XCTAssertTrue(discard.isHittable)
        XCTAssertTrue(app.buttons["pause-save-exit"].isHittable)
        discard.tap()
        app.buttons["Cancel"].tap()
        XCTAssertTrue(discard.isHittable)
        XCUIDevice.shared.orientation = .portrait
        discard.tap()
        app.buttons["Exit"].tap()
        XCTAssertTrue(play.waitForExistence(timeout: 5))
    }

    func testLibraryFolderEntryAndSettingsInBothOrientations() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-preview"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.buttons["add-folder"].waitForExistence(timeout: 20))
        app.buttons["game-sf2"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "selected-title", "Street Fighter II")).firstMatch.waitForExistence(timeout: 5))
        attach("Library-landscape")
        app.buttons["add-folder"].tap()
        XCTAssertTrue(app.buttons["choose-folder"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Includes subfolders and keeps the ROMs in their original location. Select the folder in Files, then tap Open."].exists)
        attach("Add-folder")
        app.buttons["Done"].tap()
        app.buttons["open-settings"].tap()
        XCTAssertTrue(app.buttons["settings-Folder setup"].waitForExistence(timeout: 5))
        attach("Settings-landscape")
        app.buttons["save-exit"].tap()
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["add-folder"].waitForExistence(timeout: 5))
        attach("Library-portrait")
        app.buttons["add-folder"].tap()
        XCTAssertTrue(app.buttons["choose-folder"].waitForExistence(timeout: 5))
    }
    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
