import XCTest

final class LibraryUITests: XCTestCase {
    func testArcadeLayoutSwitchInBothOrientations() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-preview", "--paused-game"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        let fighter = app.buttons["game-sf2"]
        XCTAssertTrue(fighter.waitForExistence(timeout: 20))
        fighter.tap()
        app.buttons["play-selected"].tap()
        app.buttons["Continue playing"].tap()
        let layout = app.descendants(matching: .any).matching(identifier: "arcade-layout").firstMatch
        XCTAssertTrue(layout.waitForExistence(timeout: 8))
        layout.tap()
        XCTAssertTrue(app.buttons["Automatic (6 buttons)"].exists)
        app.buttons["3 buttons"].tap()
        let third = app.descendants(matching: .any).matching(identifier: "pad-3").firstMatch
        let sixth = app.descendants(matching: .any).matching(identifier: "pad-6").firstMatch
        XCTAssertTrue(third.waitForExistence(timeout: 5))
        // Choosing a layout reveals the touch controls even with a connected controller.
        let stick = app.descendants(matching: .any).matching(identifier: "pad-stick").firstMatch
        XCTAssertTrue(stick.waitForExistence(timeout: 5))
        XCTAssertEqual(stick.label, "Directional joystick")
        XCTAssertFalse(sixth.exists)
        XCUIDevice.shared.orientation = .portrait
        // A native tap synchronises with the rotation animation. Verify it
        // actually opens the menu and changes the visible gameplay buttons.
        layout.tap()
        let automatic = app.buttons["Automatic (6 buttons)"]
        XCTAssertTrue(automatic.waitForExistence(timeout: 5))
        automatic.tap()
        XCTAssertTrue(sixth.waitForExistence(timeout: 5))
        attach("Arcade-six-buttons-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(sixth.isHittable)
        attach("Arcade-six-buttons-landscape")
    }

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
