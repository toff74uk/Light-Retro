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
        verifyToolbar(in: app)
        XCUIDevice.shared.orientation = .portrait
        // A native tap synchronises with the rotation animation. Verify it
        // actually opens the menu and changes the visible gameplay buttons.
        layout.tap()
        let automatic = app.buttons["Automatic (6 buttons)"]
        XCTAssertTrue(automatic.waitForExistence(timeout: 5))
        automatic.tap()
        XCTAssertTrue(sixth.waitForExistence(timeout: 5))
        verifyToolbar(in: app)
        attach("Arcade-six-buttons-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        // The new landscape controls are laid out after the orientation setter returns.
        let landscapeControls = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.width > app.frame.height && sixth.isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscapeControls], timeout: 5), .completed)
        verifyToolbar(in: app)
        attach("Arcade-six-buttons-landscape")
    }

    private func verifyToolbar(in app: XCUIApplication) {
        let coin = app.buttons["COIN"]
        let start = app.buttons["START"]
        let setup = app.buttons["emulator-setup"]
        XCTAssertTrue(coin.isHittable && start.isHittable && setup.isHittable)
        XCTAssertLessThan(coin.frame.midX, start.frame.midX)
        XCTAssertLessThan(start.frame.midX, app.frame.midX)
        XCTAssertGreaterThan(setup.frame.midX, app.frame.midX)
        XCTAssertLessThan(coin.frame.midY, app.frame.height / 3)
        XCTAssertEqual(coin.frame.midY, setup.frame.midY, accuracy: 5)
    }

    func testConsoleSetupReturnsToTheGame() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-preview", "--paused-game"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        let game = app.buttons["game-Super Mario World (USA)"]
        XCTAssertTrue(game.waitForExistence(timeout: 20))
        game.tap()
        app.buttons["play-selected"].tap()
        app.buttons["Continue playing"].tap()
        let setup = app.buttons["emulator-setup"]
        XCTAssertTrue(setup.waitForExistence(timeout: 5))
        setup.tap()
        XCTAssertTrue(app.staticTexts["Super Nintendo setup"].waitForExistence(timeout: 5))
        app.buttons["setup-done"].tap()
        XCTAssertTrue(setup.waitForExistence(timeout: 5))
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
        let confirmation = app.alerts["Exit without saving a new state?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertTrue(confirmation.buttons["Exit"].isHittable)
        confirmation.buttons["Cancel"].tap()
        XCTAssertTrue(discard.isHittable)
        XCUIDevice.shared.orientation = .portrait
        discard.tap()
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertTrue(confirmation.buttons["Cancel"].isHittable)
        attach("Exit-confirmation-portrait")
        confirmation.buttons["Exit"].tap()
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
    func testOpenProfilesFromLibraryAndSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-preview"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        let player = app.buttons["Player 1"]
        XCTAssertTrue(player.waitForExistence(timeout: 20))
        player.tap()
        XCTAssertTrue(app.navigationBars["Profiles"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Add player"].exists)
        app.buttons["Done"].tap()

        app.buttons["open-settings"].tap()
        app.buttons["settings-Profiles"].tap()
        XCTAssertTrue(app.navigationBars["Profiles"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Player 1"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["save-exit"].waitForExistence(timeout: 5))
    }

    func testAppearanceAndScreensaverPreviews() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-preview"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        let settings = app.buttons["open-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        app.buttons["settings-Appearance"].tap()
        let swatch = app.buttons["Light blue"]
        let preview = app.descendants(matching: .any).matching(identifier: "appearance-preview").firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertLessThan(swatch.frame.maxX, preview.frame.minX)
        swatch.tap()
        XCTAssertTrue((preview.value as? String)?.contains("Light blue") == true)
        attach("Appearance-landscape")
        XCUIDevice.shared.orientation = .portrait
        let portrait = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.height > app.frame.width && swatch.isHittable && swatch.frame.maxX < preview.frame.minX
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [portrait], timeout: 5), .completed)
        attach("Appearance-portrait")
        XCTAssertFalse(app.buttons["Preview screensaver"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["settings-Screensaver"].tap()
        let show = app.buttons["Preview screensaver"]
        XCTAssertTrue(show.waitForExistence(timeout: 5))
        show.tap()
        let wake = app.buttons["dismiss-screensaver"]
        XCTAssertTrue(wake.waitForExistence(timeout: 5))
        XCTAssertEqual(wake.frame.midX, app.frame.midX, accuracy: 4)
        XCTAssertGreaterThan(wake.frame.midY, app.frame.maxY - 95)
        let logo = app.descendants(matching: .any).matching(identifier: "screensaver-logo").firstMatch
        XCTAssertTrue(logo.waitForExistence(timeout: 5))
        let start = logo.frame.origin
        let moving = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(logo.frame.minX - start.x) + abs(logo.frame.minY - start.y) > 8
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [moving], timeout: 6), .completed)
        attach("Screensaver-preview")
        wake.tap()
        XCTAssertTrue(show.waitForExistence(timeout: 5))
    }

    func testReorderSystemsInBrowsingSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-preview"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        let settings = app.buttons["open-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        app.buttons["settings-Customise browsing"].tap()
        let mame = app.cells.containing(.switch, identifier: "MAME / Arcade").firstMatch
        let fbneo = app.cells.containing(.switch, identifier: "FinalBurn Neo").firstMatch
        XCTAssertTrue(mame.waitForExistence(timeout: 5))
        XCTAssertTrue(fbneo.exists)
        // Some simulator versions expose the reorder control as its own button.
        // Otherwise its centre is 32 points inside the trailing edge of the inset cell.
        let reorder = fbneo.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Reorder'")).firstMatch
        let centre = CGVector(dx: 0.5, dy: 0.5)
        let handle = reorder.exists ? reorder.coordinate(withNormalizedOffset: centre) :
            fbneo.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -32, dy: 0))
        let target = mame.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.15)).withOffset(CGVector(dx: -32, dy: 0))
        handle.press(forDuration: 0.8, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.5)
        XCTAssertLessThan(fbneo.frame.midY, mame.frame.midY)
        attach("System-order")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["save-exit"].tap()
        let first = app.buttons["nav-FinalBurn Neo"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertLessThan(first.frame.midX, app.buttons["nav-MAME / Arcade"].frame.midX)
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
