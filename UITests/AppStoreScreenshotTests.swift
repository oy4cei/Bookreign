import XCTest

/// Run this class explicitly when refreshing the App Store screenshot set.
/// All content lives in the app's isolated UI-test database.
final class AppStoreScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureEnglish() throws { capture(language: "en", nativeName: "English") }
    func testCaptureUkrainian() throws { capture(language: "uk", nativeName: "Українська") }
    func testCaptureRussian() throws { capture(language: "ru", nativeName: "Русский") }

    private func capture(language: String, nativeName: String) {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-library", "--reset-preferences", "--demo"]
        app.launch()
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 10))
        app.buttons["settingsButton"].tap()
        app.buttons["appearancePicker"].tap()
        app.buttons["Светлая"].tap()
        app.buttons["interfaceLanguagePicker"].tap()
        app.buttons[nativeName].tap()
        app.buttons["settingsDone"].tap()

        let grid = app.buttons["libraryLayoutGrid"]
        let list = app.buttons["libraryLayoutList"]
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        grid.tap()
        XCTAssertTrue(grid.isSelected)
        save(app, language: language, name: "01-library-grid")
        list.tap()
        XCTAssertTrue(list.isSelected)
        save(app, language: language, name: "02-library-list")

        let tabs: [String: (places: String, topics: String)] = [
            "en": ("Places", "Topics"),
            "uk": ("Місця", "Теми"),
            "ru": ("Места", "Темы")
        ]
        let labels = tabs[language]!
        selectTab(labels.places, in: app)
        XCTAssertTrue(app.buttons["loansLocation"].waitForExistence(timeout: 5))
        save(app, language: language, name: "03-places")
        selectTab(labels.topics, in: app)
        XCTAssertTrue(app.buttons["topicsAuthorPicker"].waitForExistence(timeout: 5))
        save(app, language: language, name: "04-topics")
    }

    private func selectTab(_ title: String, in app: XCUIApplication) {
        // iPad's floating tab bar exposes cells instead of a TabBar container.
        let tab = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title)).firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.tap()
    }

    private func save(_ app: XCUIApplication, language: String, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "app-store-\(language)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
