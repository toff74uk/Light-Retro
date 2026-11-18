import XCTest

final class LibraryUITests: XCTestCase {
    func testLibraryFolderEntryAndSettingsInBothOrientations() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-preview"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.buttons["add-folder"].waitForExistence(timeout: 20))
        app.buttons["game-sf2"].tap()
        XCTAssertTrue(app.staticTexts["selected-title"].label.contains("Street Fighter II"))
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
