import XCTest

/// Theme regression and review captures. Run explicitly on an iPhone and iPad.
/// Fixture data and preferences are isolated from the user's own library.
final class ArchiveThemeScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLibraryControlsRemainReachableAtLargestAccessibilityTextSize() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-library", "--reset-preferences", "--demo",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let heading = app.staticTexts["Моя библиотека"]
        XCTAssertTrue(heading.waitForExistence(timeout: 10))
        // Check rendered geometry so an ignored launch override cannot yield a
        // false pass at the normal text size (whose heading is about 41 pt tall).
        XCTAssertGreaterThan(heading.frame.height, 60, "The accessibility text-size override must visibly enlarge the heading")
        XCTAssertLessThanOrEqual(heading.frame.maxX, app.frame.maxX, "The enlarged heading must wrap within the screen")
        let scan = app.buttons["addBookButton"]
        XCTAssertTrue(scan.isHittable, "Scanning must remain reachable without scrolling past the enlarged header")
        XCTAssertGreaterThanOrEqual(scan.frame.height, 44)
        save(app, theme: "accessibility-xxxl", name: "library-heading")

        func revealLayoutControl(_ control: XCUIElement) {
            // The scroll view extends behind the pinned footer. Keep the whole
            // gesture within visible content so it cannot start on Scan.
            for _ in 0..<8 {
                let top = app.navigationBars.firstMatch.frame.maxY + 20
                let bottom = scan.frame.minY - 20
                let frame = control.frame
                if control.isHittable && frame.minY >= top && frame.maxY <= bottom { break }
                let origin = app.coordinate(withNormalizedOffset: .zero)
                // Short, slow drags avoid momentum overshooting this 44 pt
                // control between the large header and pinned scan action.
                let distance = min(140, max(60, abs(frame.midY - (top + bottom) / 2)))
                let startY = frame.minY < top ? top + 10 : bottom - 10
                let endY = frame.minY < top ? startY + distance : startY - distance
                let start = origin.withOffset(CGVector(dx: app.frame.width * 0.75, dy: startY - app.frame.minY))
                let end = origin.withOffset(CGVector(dx: app.frame.width * 0.75, dy: endY - app.frame.minY))
                start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
            }
            let navigation = app.navigationBars.firstMatch.frame
            let diagnostic = "Control \(control.frame); navigation \(navigation); scan \(scan.frame)"
            XCTAssertTrue(control.isHittable, diagnostic)
            XCTAssertGreaterThanOrEqual(control.frame.minY, navigation.maxY + 20, diagnostic)
            XCTAssertLessThanOrEqual(control.frame.maxY, scan.frame.minY - 20, diagnostic)
        }

        let list = app.buttons["libraryLayoutList"]
        revealLayoutControl(list)
        XCTAssertTrue(list.isHittable, "The layout control must remain reachable below the enlarged heading and search")
        XCTAssertGreaterThanOrEqual(list.frame.width, 44)
        XCTAssertGreaterThanOrEqual(list.frame.height, 44)
        list.tap()
        XCTAssertTrue(list.isSelected)
        let grid = app.buttons["libraryLayoutGrid"]
        revealLayoutControl(grid)
        XCTAssertGreaterThanOrEqual(grid.frame.width, 44)
        XCTAssertGreaterThanOrEqual(grid.frame.height, 44)
        XCTAssertLessThanOrEqual(list.frame.maxX, app.frame.maxX)
        save(app, theme: "accessibility-xxxl", name: "library-list")
        grid.tap()
        XCTAssertTrue(grid.isSelected)
        XCTAssertTrue(scan.isHittable, "Switching layout must preserve the scan action")
    }

    func testArchiveThemesAcrossLibraryAndBookConfirmation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-library", "--reset-preferences", "--demo", "--catalog-test-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 10))

        for theme in [(name: "green-binding", choice: "Светлая", dark: false),
                      (name: "night-archive", choice: "Тёмная", dark: true)] {
            app.buttons["settingsButton"].tap()
            app.buttons["appearancePicker"].tap()
            app.buttons[theme.choice].tap()
            let picker = app.buttons["appearancePicker"]
            XCTAssertTrue(picker.waitForExistence(timeout: 5))
            let nav = app.navigationBars["Настройки"].frame
            let body = try pixel(in: app, at: CGPoint(x: nav.minX + 8, y: picker.frame.midY))
            if theme.dark {
                XCTAssertLessThan(body.brightness, 0.35, "Dark preference must update the open settings sheet")
                XCTAssertGreaterThan(body.green, body.red + 0.025, "Night Archive must retain its green character")
            } else {
                XCTAssertGreaterThan(body.brightness, 0.65, "Light preference must update the open settings sheet")
                XCTAssertGreaterThan(body.red, body.blue + 0.02, "Green Binding must use warm paper rather than neutral gray")
            }
            save(app, theme: theme.name, name: "settings")
            app.buttons["settingsDone"].tap()

            let grid = app.buttons["libraryLayoutGrid"]
            let list = app.buttons["libraryLayoutList"]
            XCTAssertTrue(grid.waitForExistence(timeout: 5))
            grid.tap()
            XCTAssertTrue(grid.isSelected)
            let libraryNav = app.navigationBars.firstMatch.frame
            let header = try pixel(in: app, at: CGPoint(x: libraryNav.minX + 8, y: libraryNav.midY))
            XCTAssertLessThan(header.brightness, 0.45, "Archive navigation must have a dark header in both themes")
            XCTAssertGreaterThan(header.green, header.red + 0.025, "Archive header must remain green")
            save(app, theme: theme.name, name: "library-grid")
            list.tap()
            XCTAssertTrue(list.isSelected)
            save(app, theme: theme.name, name: "library-list")

            selectTab("Места", in: app)
            XCTAssertTrue(app.buttons["loansLocation"].waitForExistence(timeout: 5))
            save(app, theme: theme.name, name: "places")
            selectTab("Темы", in: app)
            XCTAssertTrue(app.buttons["topicsAuthorPicker"].waitForExistence(timeout: 5))
            save(app, theme: theme.name, name: "topics")
            selectTab("Книги", in: app)

            let scan = app.buttons["addBookButton"].exists
                ? app.buttons["addBookButton"] : app.buttons["Добавить книгу"]
            XCTAssertTrue(scan.isHittable, "Main scan action must remain reachable in both themes")
            XCTAssertGreaterThanOrEqual(scan.frame.height, 44)
            scan.tap()
            let isbn = app.textFields["scannerISBN"]
            XCTAssertTrue(isbn.waitForExistence(timeout: 5))
            save(app, theme: theme.name, name: "scanner")
            isbn.tap()
            isbn.typeText("9789664481974\n")
            XCTAssertTrue(app.staticTexts["confirmationBookTitle"].waitForExistence(timeout: 10))
            let confirm = app.buttons["confirmBook"]
            XCTAssertTrue(confirm.isEnabled)
            XCTAssertTrue(confirm.isHittable)
            XCTAssertGreaterThanOrEqual(confirm.frame.height, 44)
            XCTAssertTrue(app.buttons["editBookDetails"].exists)
            save(app, theme: theme.name, name: "confirmation")
            app.buttons["Назад"].tap()
            XCTAssertTrue(app.navigationBars["Сканирование"].waitForExistence(timeout: 5))
            app.buttons["Отмена"].tap()
            XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 5))
        }
    }

    private func selectTab(_ title: String, in app: XCUIApplication) {
        // iPad's floating tab bar exposes cells instead of a TabBar container.
        let tab = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title)).firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.tap()
    }

    private func save(_ app: XCUIApplication, theme: String, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "archive-\(theme)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private struct Pixel {
        let red: Double
        let green: Double
        let blue: Double
        var brightness: Double { (red + green + blue) / 3 }
    }

    private func pixel(in app: XCUIApplication, at point: CGPoint) throws -> Pixel {
        let screenshot = app.screenshot().image
        let image = try XCTUnwrap(screenshot.cgImage)
        let pixel = try XCTUnwrap(image.cropping(to: CGRect(x: point.x * screenshot.scale,
                                                          y: point.y * screenshot.scale,
                                                          width: 1, height: 1)))
        var rgba = [UInt8](repeating: 0, count: 4)
        rgba.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                    bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return Pixel(red: Double(rgba[0]) / 255, green: Double(rgba[1]) / 255, blue: Double(rgba[2]) / 255)
    }
}
