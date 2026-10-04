import XCTest

final class PolkaUITests: XCTestCase {
    func testLibraryListLayoutSupportsFilteringAndPersistsAfterRelaunch() throws {
        let app = launchFreshLibrary()
        let grid = app.buttons["libraryLayoutGrid"]
        let list = app.buttons["libraryLayoutList"]
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        XCTAssertTrue(grid.isHittable)
        XCTAssertTrue(list.isHittable, "List layout must be available directly on the library page")
        XCTAssertTrue(grid.isSelected)

        addManualUkrainianBook(in: app)
        list.tap()
        XCTAssertTrue(list.isSelected)
        let row = bookCard(in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(row.frame.width, row.frame.height * 2, "List layout must display a wide, compact book row")

        app.buttons["Дача"].tap()
        XCTAssertTrue(app.staticTexts["Книг не найдено"].waitForExistence(timeout: 5))
        XCTAssertFalse(row.exists)
        app.buttons["Все книги"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let search = app.textFields["librarySearch"]
        search.tap()
        search.typeText("MissingTitle\n")
        XCTAssertTrue(app.staticTexts["Книг не найдено"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.keyboards.count, 0, "Submitting library search should dismiss the keyboard")
        app.buttons["Очистить поиск"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Library list layout"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        openBook(in: app)
        XCTAssertTrue(app.staticTexts["Валер’ян Підмогильний"].exists)

        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        XCTAssertTrue(list.isSelected, "Layout selection must survive relaunch")
        XCTAssertGreaterThan(row.frame.width, row.frame.height * 2)
        grid.tap()
        XCTAssertTrue(grid.isSelected)
        XCTAssertLessThan(row.frame.width, row.frame.height)
        XCTAssertTrue(app.staticTexts["Изданий: 1"].exists)
    }

    func testAddBookOpensScannerAndDoesNotSaveBeforeConfirmation() throws {
        let app = launchFreshLibrary()
        app.buttons["Добавить первую книгу"].tap()
        XCTAssertTrue(app.navigationBars["Сканирование"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["scannerISBN"].exists)
        XCTAssertTrue(app.buttons["otherAddMethods"].exists)
        XCTAssertTrue(app.buttons["batchScan"].exists)
        app.buttons["Отмена"].tap()
        XCTAssertTrue(app.buttons["Добавить первую книгу"].waitForExistence(timeout: 5))
    }

    func testLoansAreInsidePlaces() throws {
        let app = launchFreshLibrary()
        XCTAssertFalse(app.buttons["tab-loans"].exists)
        XCTAssertTrue(app.buttons["tab-topics"].exists)
        app.buttons["tab-places"].tap()
        let loans = app.buttons["loansLocation"]
        XCTAssertTrue(loans.waitForExistence(timeout: 5))
        loans.tap()
        XCTAssertTrue(app.navigationBars["Выдано"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Все книги на месте"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(loans.waitForExistence(timeout: 5))
    }

    func testTopicsCombinesAuthorAndGenreFiltersAndSortsTitlesAfterRelaunch() throws {
        let app = launchFreshLibrary()
        addManualBook(in: app, title: "Яблуко", author: "Автор А", genres: "Роман")
        addManualBook(in: app, title: "Абетка", author: "Автор Б")
        addManualBook(in: app, title: "Місто", author: "Автор А", genres: "Роман; Класика")
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.buttons["tab-topics"].tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "topicsBook-"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.firstMatch.identifier, "topicsBook-Абетка")
        XCTAssertEqual(app.staticTexts["topicsResultCount"].label, "Найдено изданий: 3")

        app.buttons["topicsSortPicker"].tap()
        app.buttons["Название: Я–А"].tap()
        XCTAssertEqual(rows.firstMatch.identifier, "topicsBook-Яблуко")
        app.buttons["topicsAuthorPicker"].tap()
        app.buttons["Автор А"].tap()
        XCTAssertEqual(app.staticTexts["topicsResultCount"].label, "Найдено изданий: 2")
        XCTAssertFalse(app.buttons["topicsBook-Абетка"].exists)
        app.buttons["topicsGenrePicker"].tap()
        app.buttons["Класика"].tap()
        XCTAssertEqual(app.staticTexts["topicsResultCount"].label, "Найдено изданий: 1")
        XCTAssertEqual(rows.firstMatch.identifier, "topicsBook-Місто")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Topics author and genre filters"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        rows.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Автор А"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["topicsResetFilters"].tap()
        XCTAssertEqual(app.staticTexts["topicsResultCount"].label, "Найдено изданий: 3")
        XCTAssertEqual(rows.firstMatch.identifier, "topicsBook-Абетка")
        app.buttons["topicsGenrePicker"].tap()
        app.buttons["Без жанра"].tap()
        XCTAssertEqual(app.staticTexts["topicsResultCount"].label, "Найдено изданий: 1")
        XCTAssertEqual(rows.firstMatch.identifier, "topicsBook-Абетка")
        app.buttons["topicsAuthorPicker"].tap()
        app.buttons["Автор А"].tap()
        XCTAssertTrue(app.staticTexts["Книг не найдено"].waitForExistence(timeout: 5))
        app.buttons["topicsResetFilters"].tap()
        let search = app.textFields["topicsSearch"]
        search.tap()
        search.typeText("Місто\n")
        XCTAssertEqual(app.staticTexts["topicsResultCount"].label, "Найдено изданий: 1")
        XCTAssertEqual(rows.firstMatch.identifier, "topicsBook-Місто")
    }

    func testSettingsLanguagesThemeAndVersionPersistWithoutChangingBooks() throws {
        let app = launchFreshLibrary()
        addManualUkrainianBook(in: app)
        app.buttons["settingsButton"].tap()
        let version = app.staticTexts["appVersion"]
        XCTAssertTrue(version.waitForExistence(timeout: 5))
        XCTAssertTrue(version.label.contains("1.0.0 (12)"))
        let systemIsDark = try settingsBackgroundBrightness(in: app, navigationTitle: "Настройки") < 0.5

        app.buttons["appearancePicker"].tap()
        app.buttons["Тёмная"].tap()
        app.buttons["interfaceLanguagePicker"].tap()
        app.buttons["English"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Done"].exists)
        try assertSettingsBackground(in: app, navigationTitle: "Settings", isDark: true)
        let dark = XCTAttachment(screenshot: app.screenshot())
        dark.name = "Settings English dark"
        dark.lifetime = .keepAlways
        add(dark)
        app.buttons["settingsDone"].tap()
        XCTAssertTrue(app.staticTexts["My library"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Books"].exists)
        XCTAssertTrue(bookCard(in: app).exists)

        app.buttons["settingsButton"].tap()
        app.buttons["interfaceLanguagePicker"].tap()
        app.buttons["Українська"].tap()
        XCTAssertTrue(app.navigationBars["Налаштування"].waitForExistence(timeout: 5))
        app.buttons["appearancePicker"].tap()
        app.buttons["Світла"].tap()
        try assertSettingsBackground(in: app, navigationTitle: "Налаштування", isDark: false)
        let light = XCTAttachment(screenshot: app.screenshot())
        light.name = "Settings Ukrainian light"
        light.lifetime = .keepAlways
        add(light)
        app.buttons["settingsDone"].tap()
        XCTAssertTrue(app.staticTexts["Моя бібліотека"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Моя бібліотека"].waitForExistence(timeout: 10))
        XCTAssertTrue(bookCard(in: app).exists)
        app.buttons["settingsButton"].tap()
        let appearance = app.buttons["appearancePicker"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 5))
        XCTAssertTrue((appearance.label + " " + String(describing: appearance.value ?? "")).contains("Світла"))
        app.buttons["interfaceLanguagePicker"].tap()
        app.buttons["Русский"].tap()
        XCTAssertTrue(app.navigationBars["Настройки"].waitForExistence(timeout: 5))
        // Resetting the preference must follow the device's original theme
        // even while the settings sheet is already open.
        app.buttons["appearancePicker"].tap()
        app.buttons["Тёмная"].tap()
        try assertSettingsBackground(in: app, navigationTitle: "Настройки", isDark: true)
        app.buttons["appearancePicker"].tap()
        app.buttons["Как на устройстве"].tap()
        try assertSettingsBackground(in: app, navigationTitle: "Настройки", isDark: systemIsDark)
        app.buttons["settingsDone"].tap()
        openBook(in: app)
        XCTAssertTrue(app.staticTexts["Валер’ян Підмогильний"].exists)
        XCTAssertTrue(app.staticTexts["Украинский"].exists)
    }

    private func settingsBackgroundBrightness(in app: XCUIApplication, navigationTitle: String) throws -> Double {
        // Both archive themes have green navigation chrome. Sample the empty
        // form gutter alongside the theme picker to check the actual sheet body.
        let frame = app.navigationBars[navigationTitle].frame
        let picker = app.buttons["appearancePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        let screenshot = app.screenshot().image
        let cgImage = try XCTUnwrap(screenshot.cgImage)
        let pixel = try XCTUnwrap(cgImage.cropping(to: CGRect(x: (frame.minX + 8) * screenshot.scale,
                                                            y: picker.frame.midY * screenshot.scale,
                                                            width: 1, height: 1)))
        var rgba = [UInt8](repeating: 0, count: 4)
        rgba.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                    bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return rgba.prefix(3).map(Double.init).reduce(0, +) / (3 * 255)
    }

    private func assertSettingsBackground(in app: XCUIApplication, navigationTitle: String, isDark: Bool, file: StaticString = #filePath, line: UInt = #line) throws {
        let brightness = try settingsBackgroundBrightness(in: app, navigationTitle: navigationTitle)
        if isDark { XCTAssertLessThan(brightness, 0.35, file: file, line: line) }
        else { XCTAssertGreaterThan(brightness, 0.65, file: file, line: line) }
    }

    func testScannerEnterFindsBookWithoutTappingPlusOrReview() throws {
        let app = launchCatalogFixture()
        app.buttons["Добавить первую книгу"].tap()
        let isbn = app.textFields["scannerISBN"]
        XCTAssertTrue(isbn.waitForExistence(timeout: 5))
        isbn.tap()
        isbn.typeText("9789664481974")
        XCTAssertEqual(isbn.value as? String, "978-966-4481-97-4")
        XCTAssertTrue(app.staticTexts["ISBN"].exists)
        isbn.typeText("\n")

        XCTAssertTrue(app.navigationBars["Проверить книгу"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "confirmationCover").firstMatch.exists)
        let title = app.staticTexts["confirmationBookTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Малюк чує звук")
        XCTAssertTrue(app.staticTexts["Саша Кольцова"].exists)
        XCTAssertTrue(app.buttons["confirmBook"].isEnabled)
        XCTAssertTrue(app.buttons["editBookDetails"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "ISBN confirmation before saving"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["confirmBook"].tap()
        let card = app.descendants(matching: .any).matching(identifier: "bookCard-Малюк чує звук").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Изданий: 1"].exists)
        XCTAssertTrue(app.staticTexts["Экземпляров: 1"].exists)
    }

    func testCancellingScannedBookConfirmationLeavesLibraryEmptyAfterRelaunch() throws {
        let app = launchCatalogFixture()
        app.buttons["Добавить первую книгу"].tap()
        let isbn = app.textFields["scannerISBN"]
        XCTAssertTrue(isbn.waitForExistence(timeout: 5))
        isbn.tap()
        isbn.typeText("9789664481974\n")
        XCTAssertTrue(app.staticTexts["confirmationBookTitle"].waitForExistence(timeout: 10))
        app.buttons["Назад"].tap()
        XCTAssertTrue(app.navigationBars["Сканирование"].waitForExistence(timeout: 5))
        app.buttons["Отмена"].tap()
        XCTAssertTrue(app.buttons["Добавить первую книгу"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["Добавить первую книгу"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "bookCard-Малюк чує звук").firstMatch.exists)
    }

    func testInvalidISBNCanBeRetriedAndMissingCatalogBookAddedManually() throws {
        let app = launchCatalogFixture()
        app.buttons["Добавить первую книгу"].tap()
        let scannerISBN = app.textFields["scannerISBN"]
        XCTAssertTrue(scannerISBN.waitForExistence(timeout: 5))
        scannerISBN.tap()
        scannerISBN.typeText("9780140328722\n")
        let invalidMessage = app.staticTexts["Это не ISBN книги. Нужен код ISBN-10 или ISBN-13 с верной контрольной цифрой."]
        XCTAssertTrue(invalidMessage.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Сканирование"].exists)
        XCTAssertFalse(app.buttons["confirmBook"].exists)

        // The failed submit keeps focus at the end. Correct only the check digit;
        // tapping the middle of the masked field would move the insertion point.
        scannerISBN.typeText(XCUIKeyboardKey.delete.rawValue + "1")
        XCTAssertEqual(scannerISBN.value as? String, "978-014-0328-72-1")
        scannerISBN.typeText("\n")
        XCTAssertTrue(app.navigationBars["Добавить книгу"].waitForExistence(timeout: 10))
        let manualFallback = app.buttons["Заполнить самостоятельно"]
        // Form creates lower rows lazily. Reveal the fallback below the catalog
        // section before asking XCTest to locate it in the accessibility tree.
        scrollToElement(manualFallback, in: app)
        XCTAssertTrue(manualFallback.waitForExistence(timeout: 10))
        XCTAssertTrue(manualFallback.isHittable)
        XCTAssertFalse(app.buttons["confirmBook"].exists)

        // Retrying another valid ISBN must keep the editable fallback and carry
        // the latest ISBN into the new card, rather than saving a placeholder.
        let catalogQuery = app.textFields["catalogQuery"]
        XCTAssertTrue(catalogQuery.exists)
        for _ in 0..<4 where !catalogQuery.isHittable { app.swipeDown() }
        replaceText(in: catalogQuery, with: "9780131103627")
        XCTAssertEqual(catalogQuery.value as? String, "9780131103627")
        catalogQuery.typeText("\n")
        scrollToElement(manualFallback, in: app)
        XCTAssertTrue(manualFallback.waitForExistence(timeout: 10))
        XCTAssertTrue(manualFallback.isHittable)
        manualFallback.tap()

        let title = app.descendants(matching: .any).matching(identifier: "bookTitle").firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(title.isHittable, "Manual entry must open at the required title field")
        let initialTitle = title.value as? String ?? ""
        XCTAssertTrue(initialTitle.isEmpty || initialTitle == "Название *")
        title.tap()
        title.typeText("Книга без каталога")
        let confirm = app.buttons["confirmBook"]
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()

        let card = app.descendants(matching: .any).matching(identifier: "bookCard-Книга без каталога").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Изданий: 1"].exists)
        XCTAssertTrue(app.staticTexts["Экземпляров: 1"].exists)
        card.tap()
        // LabeledContent exposes the ISBN label and its value as one element.
        let savedISBN = app.staticTexts["ISBN, 9780131103627"]
        scrollToElement(savedISBN, in: app)
        XCTAssertTrue(savedISBN.waitForExistence(timeout: 5))
        XCTAssertEqual(savedISBN.label, "ISBN, 9780131103627")
    }

    func testAlternativeCoverPersistsAndFailedSourceDoesNotReplaceIt() throws {
        let app = launchCatalogFixture(extraArguments: ["--cover-test-fixture"])
        app.buttons["Добавить первую книгу"].tap()
        let isbn = app.textFields["scannerISBN"]
        XCTAssertTrue(isbn.waitForExistence(timeout: 5))
        isbn.tap()
        isbn.typeText("9789664481974\n")
        XCTAssertTrue(app.staticTexts["confirmationBookTitle"].waitForExistence(timeout: 10))

        let coverEditor = app.buttons["coverEditorButton"]
        XCTAssertTrue(coverEditor.waitForExistence(timeout: 5))
        coverEditor.tap()
        let candidate = app.buttons["coverCandidate-fixture-cover"]
        XCTAssertTrue(candidate.waitForExistence(timeout: 10))
        candidate.tap()
        XCTAssertTrue(app.staticTexts["coverPreviewStatus"].waitForExistence(timeout: 5))
        let applyCover = app.buttons["coverConfirmButton"]
        XCTAssertTrue(applyCover.isEnabled)
        applyCover.tap()
        XCTAssertTrue(app.staticTexts["confirmationBookTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["confirmationBookTitle"].label, "Малюк чує звук")
        XCTAssertTrue(app.staticTexts["Саша Кольцова"].exists)

        // A failed replacement must leave the already accepted cover intact.
        coverEditor.tap()
        let brokenCandidate = app.buttons["coverCandidate-fixture-broken"]
        XCTAssertTrue(brokenCandidate.waitForExistence(timeout: 10))
        brokenCandidate.tap()
        XCTAssertTrue(app.staticTexts["coverSourceError"].waitForExistence(timeout: 5))
        app.buttons["coverCancelButton"].tap()
        XCTAssertTrue(app.buttons["confirmBook"].waitForExistence(timeout: 5))
        app.buttons["confirmBook"].tap()
        let card = app.descendants(matching: .any).matching(identifier: "bookCard-Малюк чує звук").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))

        app.terminate()
        // No fixtures on relaunch: the selected image must come from the library.
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Изданий: 1"].exists)
        XCTAssertTrue(app.staticTexts["Экземпляров: 1"].exists)
        card.tap()
        XCTAssertTrue(app.staticTexts["Саша Кольцова"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Украинский"].exists)
        let savedCover = app.descendants(matching: .any).matching(identifier: "bookCover").firstMatch
        XCTAssertTrue(savedCover.exists)
        XCTAssertEqual(savedCover.value as? String, "Своя обложка")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Saved alternate cover after relaunch"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testScannerEnterPrefersUkrainianEditionAndAllowsChangingVariant() throws {
        let app = launchCatalogFixture()
        app.buttons["Добавить первую книгу"].tap()
        app.buttons["batchScan"].tap()
        let isbn = app.textFields["Ввести ISBN"]
        XCTAssertTrue(isbn.waitForExistence(timeout: 5))
        isbn.tap()
        isbn.typeText("9789664481974")
        app.buttons["Добавить ISBN в очередь"].tap()
        // Enter must search the number just entered, even when an older ISBN is queued.
        isbn.tap()
        isbn.typeText("9780306406157\n")

        let title = app.staticTexts["confirmationBookTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Українське видання")
        let variant = app.buttons["catalogEditionVariant"]
        XCTAssertTrue(variant.exists)
        variant.tap()
        app.buttons["Русский · Русское издание"].tap()
        XCTAssertEqual(title.label, "Русское издание")
        variant.tap()
        app.buttons["Украинский · Українське видання"].tap()
        app.buttons["confirmBook"].tap()

        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let card = app.descendants(matching: .any).matching(identifier: "bookCard-Українське видання").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        XCTAssertTrue(app.staticTexts["Украинский"].waitForExistence(timeout: 5))
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSavedISBNPlaceholderCanBeFilledWithoutAddingAnotherCopy() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-library", "--reset-preferences", "--seed-missing-isbn", "--catalog-test-fixture"]
        app.launch()
        let card = app.descendants(matching: .any).matching(identifier: "bookCard-Книга · 9789664481974").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        let find = app.buttons["findBookMetadata"]
        XCTAssertTrue(find.waitForExistence(timeout: 5))
        find.tap()
        XCTAssertTrue(app.staticTexts["Малюк чує звук"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Саша Кольцова"].exists)
        let apply = app.buttons["applyBookMetadata"]
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        apply.tap()
        XCTAssertTrue(app.staticTexts["Малюк чує звук"].waitForExistence(timeout: 10))
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let filled = app.descendants(matching: .any).matching(identifier: "bookCard-Малюк чує звук").firstMatch
        XCTAssertTrue(filled.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Изданий: 1"].exists)
        XCTAssertTrue(app.staticTexts["Экземпляров: 1"].exists)
        filled.tap()
        XCTAssertTrue(app.staticTexts["Детская"].waitForExistence(timeout: 5))
    }

    func testManualUkrainianBookLoanReturnAndRelaunch() throws {
        let app = launchFreshLibrary()
        addManualUkrainianBook(in: app)

        XCTAssertTrue(app.staticTexts["Изданий: 1"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Экземпляров: 1"].exists)
        attachLibraryScreenshot(from: app)

        openBook(in: app)
        XCTAssertTrue(app.staticTexts["Украинский"].waitForExistence(timeout: 5))
        let lend = app.buttons["Дать почитать"]
        XCTAssertTrue(lend.waitForExistence(timeout: 5))
        lend.tap()

        let borrower = app.descendants(matching: .any).matching(identifier: "borrowerName").firstMatch
        XCTAssertTrue(borrower.waitForExistence(timeout: 5))
        borrower.tap()
        borrower.typeText("Олена")
        app.buttons["Сохранить"].tap()
        XCTAssertTrue(app.staticTexts["У Олена"].waitForExistence(timeout: 10))

        app.buttons["tab-places"].tap()
        app.buttons["loansLocation"].tap()
        XCTAssertTrue(app.staticTexts["Олена"].waitForExistence(timeout: 5))
        app.buttons["Отметить возврат"].tap()
        let returnButton = app.buttons["Вернуть"]
        XCTAssertTrue(returnButton.waitForExistence(timeout: 5))
        returnButton.tap()
        XCTAssertTrue(app.staticTexts["Все книги на месте"].waitForExistence(timeout: 5))
        app.buttons["tab-books"].tap()
        revealLoanHistory(in: app)
        XCTAssertTrue(app.staticTexts["Олена"].exists)
        XCTAssertFalse(app.staticTexts["У Олена"].exists)

        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Изданий: 1"].waitForExistence(timeout: 10))
        openBook(in: app)
        XCTAssertTrue(app.staticTexts["Місто"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Валер’ян Підмогильний"].exists)
        revealLoanHistory(in: app)
        XCTAssertTrue(app.staticTexts["Олена"].exists)
    }

    private func revealLoanHistory(in app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["Книга"].waitForExistence(timeout: 5))
        let history = app.staticTexts["История выдачи"]
        // List virtualizes the history section below the cover and copy controls.
        // Scroll within visible content, above the persistent tab strip.
        for _ in 0..<4 where !history.isHittable || !app.staticTexts["Олена"].isHittable {
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let top = app.navigationBars["Книга"].frame.maxY + 30
            let bottom = app.buttons["tab-books"].frame.minY - 30
            let lower = origin.withOffset(CGVector(dx: app.frame.width * 0.75, dy: bottom))
            let upper = origin.withOffset(CGVector(dx: app.frame.width * 0.75, dy: top))
            lower.press(forDuration: 0.05, thenDragTo: upper)
        }
        XCTAssertTrue(history.isHittable)
        XCTAssertTrue(app.staticTexts["Олена"].isHittable)
    }

    func testSecondCopyAppearsUnderItsLocationAfterRelaunch() throws {
        let app = launchFreshLibrary()
        addManualUkrainianBook(in: app)
        openBook(in: app)

        let addCopy = app.buttons["Добавить ещё экземпляр"]
        XCTAssertTrue(addCopy.waitForExistence(timeout: 5))
        addCopy.tap()
        choose("Дача", inPicker: "Место", app: app)
        app.buttons["Добавить"].tap()
        XCTAssertTrue(app.staticTexts["Дача"].waitForExistence(timeout: 10))

        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Экземпляров: 2"].waitForExistence(timeout: 10))
        app.buttons["Дача"].tap()
        XCTAssertTrue(bookCard(in: app).waitForExistence(timeout: 5))
        app.buttons["Дом"].tap()
        XCTAssertTrue(bookCard(in: app).waitForExistence(timeout: 5))
    }

    private func launchFreshLibrary() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-library", "--reset-preferences"]
        app.launch()
        XCTAssertTrue(app.buttons["Добавить первую книгу"].waitForExistence(timeout: 10))
        return app
    }

    private func launchCatalogFixture(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-library", "--reset-preferences", "--catalog-test-fixture"] + extraArguments
        app.launch()
        XCTAssertTrue(app.buttons["Добавить первую книгу"].waitForExistence(timeout: 10))
        return app
    }

    private func addManualUkrainianBook(in app: XCUIApplication) {
        addManualBook(in: app, title: "Місто", author: "Валер’ян Підмогильний")
    }

    private func addManualBook(in app: XCUIApplication, title bookTitle: String, author bookAuthor: String, genres: String? = nil) {
        let addEntry = app.buttons["Добавить первую книгу"].exists ? app.buttons["Добавить первую книгу"] : app.buttons["addBookButton"]
        addEntry.tap()
        let otherMethods = app.buttons["otherAddMethods"]
        XCTAssertTrue(otherMethods.waitForExistence(timeout: 5))
        otherMethods.tap()
        let manualEntry = app.buttons["Ввести вручную"]
        XCTAssertTrue(manualEntry.waitForExistence(timeout: 5))
        manualEntry.tap()

        let title = app.descendants(matching: .any).matching(identifier: "bookTitle").firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText(bookTitle)

        let author = app.descendants(matching: .any).matching(identifier: "bookAuthor").firstMatch
        XCTAssertTrue(author.waitForExistence(timeout: 5))
        author.tap()
        author.typeText(bookAuthor)
        choose("Украинский", inPicker: "Язык издания", app: app)

        if let genres {
            let field = app.descendants(matching: .any).matching(identifier: "bookGenres").firstMatch
            // A full-screen swipe jumps past this row while the keyboard is open.
            // Scroll in small steps within the visible form instead.
            for _ in 0..<6 where !field.isHittable {
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.50))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.38))
                start.press(forDuration: 0.05, thenDragTo: end)
            }
            XCTAssertTrue(field.isHittable)
            field.tap()
            field.typeText(genres)
        }

        let add = app.buttons["confirmBook"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertTrue(add.isEnabled)
        add.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "bookCard-\(bookTitle)").firstMatch.waitForExistence(timeout: 10))
    }

    private func choose(_ optionName: String, inPicker pickerName: String, app: XCUIApplication) {
        let picker = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", pickerName)).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "Missing picker: \(pickerName)")
        picker.tap()
        let option = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", optionName)).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5), "Missing option: \(optionName)")
        option.tap()
    }

    private func replaceText(in field: XCUIElement, with replacement: String) {
        field.tap()
        let count = (field.value as? String)?.count ?? 0
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count) + replacement)
    }

    private func scrollToElement(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !element.isHittable { app.swipeUp() }
    }

    private func bookCard(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "bookCard-Місто").firstMatch
    }

    private func openBook(in app: XCUIApplication) {
        let card = bookCard(in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        XCTAssertTrue(app.staticTexts["Місто"].waitForExistence(timeout: 5))
    }

    private func attachLibraryScreenshot(from app: XCUIApplication) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Library with Ukrainian edition"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
