import XCTest

/// Вкладка «Контакты»: список, добавление (вставка и сканер), проверки ключа и имени, карточка, переименование,
/// удаление, ошибка чтения (фича 03-contacts).
final class ContactsUITests: XCTestCase {
    private let notAKey = "Это не ключ CipherKeyboard. Вставьте строку целиком — она начинается с ckpub1:"
    private let newerVersion = "Этот ключ создан более новой версией CipherKeyboard. Обновите приложение."
    private let ownKeyMessage = "Это ваш собственный ключ. Добавьте ключ собеседника."
    private let hint = "Сверьте отпечаток с собеседником при встрече или по телефону — он должен совпасть."

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: - E8

    @MainActor
    func testAddContactByPasteAndRelaunch() {
        // Настоящий файл контактов симулятора тестов: без `-contacts memory`.
        let arguments = ["-keystore", "memory"]
        let app = launch(arguments)
        openContacts(app)
        removeContacts(named: "Тест Анна", in: app)

        // 2) Пустое состояние.
        let empty = app.staticTexts["contacts.empty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        XCTAssertTrue(empty.label.contains("Пока нет контактов"), empty.label)
        XCTAssertTrue(app.buttons["contacts.addFirst"].exists)
        XCTAssertFalse(app.buttons["contacts.add"].exists)

        // 3) Лист добавления.
        app.buttons["contacts.addFirst"].tap()
        let title = app.staticTexts["addcontact.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Новый контакт")
        XCTAssertFalse(app.buttons["addcontact.save"].isEnabled)

        // 4–5) Ключ K1 → отпечаток K1; имя.
        enterKey(TestKeys.k1.publicKey, in: app)
        let fingerprint = app.staticTexts["addcontact.fingerprint"]
        XCTAssertTrue(fingerprint.waitForExistence(timeout: 5))
        XCTAssertEqual(fingerprint.label, TestKeys.k1.fingerprint)
        XCTAssertEqual(fingerprint.label.count, 39)
        enterName("Тест Анна", in: app)
        XCTAssertTrue(app.buttons["addcontact.save"].isEnabled)

        // 6) Сохранить → лист закрыт, одна строка, «+» вместо «Добавить контакт».
        app.buttons["addcontact.save"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        let expectedLabel = "Тест Анна, \(TestKeys.k1.shortFingerprint)"
        let rows = contactRows(app)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.firstMatch.label, expectedLabel)
        XCTAssertTrue(app.buttons["contacts.add"].exists)
        XCTAssertFalse(app.buttons["contacts.addFirst"].exists)

        // 7) Перезапуск с теми же аргументами — строка на месте.
        app.terminate()
        app.launch()
        openContacts(app)
        let relaunchedRows = contactRows(app)
        XCTAssertTrue(relaunchedRows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(relaunchedRows.count, 1)
        XCTAssertEqual(relaunchedRows.firstMatch.label, expectedLabel)

        // 8) Убрать за собой.
        removeContacts(named: "Тест Анна", in: app)
        XCTAssertTrue(app.staticTexts["contacts.empty"].waitForExistence(timeout: 5))
    }

    // MARK: - E9

    @MainActor
    func testRejectsNonKeyAndNewerVersion() {
        let app = launch(["-keystore", "memory", "-contacts", "memory"])
        openContacts(app)
        openAddSheet(app)
        let save = app.buttons["addcontact.save"]
        let keyError = app.staticTexts["addcontact.keyError"]
        let fingerprint = app.staticTexts["addcontact.fingerprint"]

        let notKeys = [
            "привет",
            "Мой ключ: " + TestKeys.k1.publicKey,
            String(TestKeys.k1.publicKey.dropLast()),
        ]
        for text in notKeys {
            enterKey(text, in: app)
            XCTAssertTrue(keyError.waitForExistence(timeout: 5), text)
            XCTAssertEqual(keyError.label, notAKey, text)
            XCTAssertFalse(fingerprint.exists, text)
            XCTAssertFalse(save.isEnabled, text)
        }

        enterKey("ckpub2:" + TestKeys.k1.body, in: app)
        XCTAssertTrue(keyError.waitForExistence(timeout: 5))
        XCTAssertEqual(keyError.label, newerVersion)
        XCTAssertFalse(fingerprint.exists)
        XCTAssertFalse(save.isEnabled)

        enterKey("", in: app)
        XCTAssertTrue(keyError.waitForNonExistence(timeout: 5))
        XCTAssertFalse(fingerprint.exists)
        XCTAssertFalse(save.isEnabled)
    }

    // MARK: - E10

    @MainActor
    func testRejectsOwnKeyAndDuplicates() {
        let app = launch(["-keystore", "memory", "-contacts", "memory"])
        // 1) Свой ключ с экрана «Мой ключ».
        let ownKey = readOwnKey(app)

        // 2) «Анна» с K1.
        openContacts(app)
        addContact(name: "Анна", key: TestKeys.k1.publicKey, in: app)

        let save = app.buttons["addcontact.save"]
        let keyError = app.staticTexts["addcontact.keyError"]
        let fingerprint = app.staticTexts["addcontact.fingerprint"]
        let nameError = app.staticTexts["addcontact.nameError"]

        // 3) Свой ключ.
        openAddSheet(app)
        enterKey(ownKey, in: app)
        XCTAssertTrue(keyError.waitForExistence(timeout: 5))
        XCTAssertEqual(keyError.label, ownKeyMessage)
        XCTAssertFalse(fingerprint.exists)
        XCTAssertFalse(save.isEnabled)

        // 4) K1 уже сохранён как «Анна».
        enterKey(TestKeys.k1.publicKey, in: app)
        XCTAssertTrue(keyError.waitForExistence(timeout: 5))
        XCTAssertEqual(keyError.label, "Этот ключ уже сохранён как «Анна»")
        XCTAssertFalse(fingerprint.exists)
        XCTAssertFalse(save.isEnabled)

        // 5) K2 с именем «анна» — дубль имени.
        enterKey(TestKeys.k2.publicKey, in: app)
        XCTAssertTrue(fingerprint.waitForExistence(timeout: 5))
        enterName("анна", in: app)
        XCTAssertTrue(nameError.waitForExistence(timeout: 5))
        XCTAssertEqual(nameError.label, "Контакт с таким именем уже есть")
        XCTAssertFalse(save.isEnabled)

        // 6) «Аня» — можно.
        enterName("Аня", in: app)
        XCTAssertTrue(nameError.waitForNonExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)

        // 7) Две строки: «Анна», «Аня».
        save.tap()
        XCTAssertTrue(app.staticTexts["addcontact.title"].waitForNonExistence(timeout: 5))
        let rows = contactRows(app)
        XCTAssertTrue(waitForCount(rows, 2))
        XCTAssertEqual(rowNames(app), ["Анна", "Аня"])
    }

    // MARK: - E11

    @MainActor
    func testNameValidationInSheet() {
        let app = launch(["-keystore", "memory", "-contacts", "memory"])
        openContacts(app)
        openAddSheet(app)
        let save = app.buttons["addcontact.save"]
        let nameError = app.staticTexts["addcontact.nameError"]
        let count = app.staticTexts["addcontact.nameCount"]

        // 1) Сразу после появления предпросмотра.
        enterKey(TestKeys.k1.publicKey, in: app)
        XCTAssertTrue(app.staticTexts["addcontact.fingerprint"].waitForExistence(timeout: 5))
        XCTAssertFalse(nameError.exists)
        XCTAssertEqual(count.label, "0/40")
        XCTAssertFalse(save.isEnabled)

        // 2) Только пробелы.
        enterName("   ", in: app)
        XCTAssertTrue(nameError.waitForExistence(timeout: 5))
        XCTAssertEqual(nameError.label, "Введите имя")
        XCTAssertFalse(save.isEnabled)

        // 3) 41 символ.
        enterName(String(repeating: "А", count: 41), in: app)
        XCTAssertTrue(nameError.waitForExistence(timeout: 5))
        XCTAssertEqual(nameError.label, "Не больше 40 символов")
        XCTAssertEqual(count.label, "41/40")
        XCTAssertFalse(save.isEnabled)

        // 4) Стереть один символ — 40.
        nameField(app).typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertTrue(nameError.waitForNonExistence(timeout: 5))
        XCTAssertEqual(count.label, "40/40")
        XCTAssertTrue(save.isEnabled)

        // 5) «  Анна  » сохраняется без пробелов по краям.
        enterName("  Анна  ", in: app)
        XCTAssertTrue(save.isEnabled)
        save.tap()
        let rows = contactRows(app)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(rows.firstMatch.label.hasPrefix("Анна,"), rows.firstMatch.label)
    }

    // MARK: - E12

    @MainActor
    func testDoubleSaveCreatesOneContact() {
        let app = launch(["-keystore", "memory", "-contacts", "memory"])
        openContacts(app)
        openAddSheet(app)
        enterKey(TestKeys.k1.publicKey, in: app)
        XCTAssertTrue(app.staticTexts["addcontact.fingerprint"].waitForExistence(timeout: 5))
        enterName("Анна", in: app)

        let save = app.buttons["addcontact.save"]
        XCTAssertTrue(save.isEnabled)
        // Точка в координатах окна, вычисленная заранее: второе нажатие идёт туда же, даже если кнопка исчезает.
        let frame = save.frame
        let point = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY))
        save.tap()
        point.tap()
        // Если лист уже закрылся, второе нажатие попадает в таб-бар под кнопкой — вернуться к списку.
        let contactsTab = app.tabBars.buttons["tab.contacts"]
        if !contactsTab.isSelected { contactsTab.tap() }
        XCTAssertTrue(app.staticTexts["contacts.title"].waitForExistence(timeout: 5))

        let rows = contactRows(app)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(rows.count, 1)
    }

    // MARK: - E13

    @MainActor
    func testCardAndRename() {
        let app = launch(["-keystore", "memory", "-contacts", "memory"])
        openContacts(app)
        addContact(name: "Яна", key: TestKeys.k1.publicKey, in: app)
        addContact(name: "Борис", key: TestKeys.k2.publicKey, in: app)
        XCTAssertEqual(rowNames(app), ["Борис", "Яна"])

        // 1–2) Карточка «Яна».
        row(named: "Яна", in: app).tap()
        let title = app.staticTexts["contact.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Яна")
        let fingerprint = app.staticTexts["contact.fingerprint"].label
        XCTAssertEqual(fingerprint, TestKeys.k1.fingerprint)
        XCTAssertEqual(fingerprint.count, 39)
        XCTAssertEqual(fingerprint.split(separator: " ").count, 8)
        XCTAssertEqual(app.staticTexts["contact.hint"].label, hint)
        let publicKey = app.staticTexts["contact.publicKey"].label
        XCTAssertEqual(publicKey, TestKeys.k1.publicKey)
        XCTAssertEqual(publicKey.count, 93)

        // 3) Переименовать: поле заполнено текущим именем.
        app.buttons["contact.rename"].tap()
        let renameField = app.textFields["rename.name"]
        XCTAssertTrue(renameField.waitForExistence(timeout: 5))
        XCTAssertEqual(renameField.value as? String, "Яна")
        replaceText(in: renameField, with: "Анна", app: app)
        app.buttons["rename.save"].tap()
        XCTAssertTrue(renameField.waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitForLabel(title, "Анна"))
        XCTAssertEqual(title.label, "Анна")

        // 4) Список пересортирован.
        goBackToList(app)
        XCTAssertEqual(rowNames(app), ["Анна", "Борис"])
    }

    // MARK: - E14

    @MainActor
    func testKeyCannotBeEdited() {
        let app = launch(["-keystore", "memory", "-contacts", "memory"])
        openContacts(app)
        addContact(name: "Анна", key: TestKeys.k1.publicKey, in: app)

        // 1) На карточке нет полей ввода; нажатие на ключ и ввод его не меняют.
        row(named: "Анна", in: app).tap()
        let publicKey = app.staticTexts["contact.publicKey"]
        XCTAssertTrue(publicKey.waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields.count + app.textViews.count, 0)
        publicKey.tap()
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasKeyboardFocus == true"))
        if focused.count > 0 { app.typeText("x") }
        XCTAssertEqual(focused.count, 0, "после нажатия на ключ появился фокус ввода")
        XCTAssertEqual(publicKey.label, TestKeys.k1.publicKey)
        for forbidden in ["Изменить ключ", "Заменить ключ", "Обновить ключ"] {
            XCTAssertFalse(app.buttons[forbidden].exists, forbidden)
        }

        // 2) В листе переименования — ровно одно поле, ключа нет.
        app.buttons["contact.rename"].tap()
        XCTAssertTrue(app.textFields["rename.name"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields.count + app.textViews.count, 1)
        let keyLike = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'ckpub1:'"))
        let sheetElements = keyLike.allElementsBoundByIndex.filter { $0.isHittable }
        XCTAssertEqual(sheetElements.count, 0, "в листе переименования виден ключ")

        // 3) Закрыть и снова открыть карточку — ключ прежний.
        app.buttons["rename.cancel"].tap()
        XCTAssertTrue(app.textFields["rename.name"].waitForNonExistence(timeout: 5))
        goBackToList(app)
        row(named: "Анна", in: app).tap()
        XCTAssertTrue(publicKey.waitForExistence(timeout: 5))
        XCTAssertEqual(publicKey.label, TestKeys.k1.publicKey)
    }

    // MARK: - E15

    @MainActor
    func testDeleteAsksConfirmation() {
        let app = launch(["-keystore", "memory", "-contacts", "memory"])
        openContacts(app)
        addContact(name: "Анна", key: TestKeys.k1.publicKey, in: app)
        row(named: "Анна", in: app).tap()
        XCTAssertTrue(app.staticTexts["contact.title"].waitForExistence(timeout: 5))

        // 1) Диалог с именем.
        app.buttons["contact.delete"].tap()
        let dialogTitle = app.staticTexts["Удалить контакт «Анна»?"]
        XCTAssertTrue(dialogTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Вы не сможете отправлять ему сообщения."].exists)
        let confirm = app.buttons["contact.deleteConfirm"].firstMatch
        XCTAssertTrue(confirm.exists)
        XCTAssertEqual(confirm.label, "Удалить")
        let cancel = dialogCancelButton(app)
        XCTAssertTrue(cancel.exists)

        // 2) «Отмена» — карточка на месте.
        cancel.tap()
        XCTAssertTrue(dialogTitle.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["contact.title"].label, "Анна")

        // 3) «Удалить» → пустой список.
        app.buttons["contact.delete"].tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        let empty = app.staticTexts["contacts.empty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        XCTAssertTrue(empty.label.contains("Пока нет контактов"), empty.label)
        XCTAssertEqual(contactRows(app).count, 0)
    }

    // MARK: - E16

    @MainActor
    func testScannedPayloadIsHandledLikePaste() {
        // a) Ключ собеседника: сканер закрывается, текст в поле, предпросмотр; сохраняется только с именем.
        var app = launch(["-keystore", "memory", "-contacts", "memory", "-contacts-scan", TestKeys.k1.publicKey])
        openContacts(app)
        openAddSheet(app)
        scan(in: app)
        XCTAssertEqual(keyField(app).value as? String, TestKeys.k1.publicKey)
        let fingerprint = app.staticTexts["addcontact.fingerprint"]
        XCTAssertTrue(fingerprint.waitForExistence(timeout: 5))
        XCTAssertEqual(fingerprint.label, TestKeys.k1.fingerprint)
        XCTAssertFalse(app.buttons["addcontact.save"].isEnabled)
        enterName("Анна", in: app)
        app.buttons["addcontact.save"].tap()
        XCTAssertTrue(app.staticTexts["addcontact.title"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(contactRows(app).firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rowNames(app), ["Анна"])
        app.terminate()

        // b) Мусор: сканер закрывается, сообщение «не ключ», лист открыт.
        app = launch(["-keystore", "memory", "-contacts", "memory", "-contacts-scan", "привет"])
        openContacts(app)
        openAddSheet(app)
        scan(in: app)
        let keyError = app.staticTexts["addcontact.keyError"]
        XCTAssertTrue(keyError.waitForExistence(timeout: 5))
        XCTAssertEqual(keyError.label, notAKey)
        XCTAssertTrue(app.staticTexts["addcontact.title"].exists)
        app.terminate()

        // c) Свой ключ (настоящий Keychain симулятора тестов — ключ не меняется между запусками).
        app = launch(["-contacts", "memory"])
        let ownKey = readOwnKey(app)
        app.terminate()
        app = launch(["-contacts", "memory", "-contacts-scan", ownKey])
        openContacts(app)
        openAddSheet(app)
        scan(in: app)
        XCTAssertTrue(keyError.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["addcontact.keyError"].label, ownKeyMessage)
    }

    // MARK: - E20

    @MainActor
    func testLongListScrollsAndIsSorted() {
        let app = launch(["-keystore", "memory", "-contacts", "memory", "-contacts-seed", "120"])
        openContacts(app)
        let rows = contactRows(app)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))

        // 1) Первая видимая строка.
        XCTAssertEqual(visibleRowNames(app).first, "Контакт 001")

        // 2) Прокрутка до «Контакт 120».
        let list =
            app.collectionViews["contacts.list"].exists
            ? app.collectionViews["contacts.list"] : app.descendants(matching: .any)["contacts.list"]
        let last = row(named: "Контакт 120", in: app)
        var swipes = 0
        while !(last.exists && last.isHittable) && swipes < 30 {
            list.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(last.exists)
        XCTAssertTrue(last.isHittable)

        // 3) «Аарон» встаёт первым.
        addContact(name: "Аарон", key: TestKeys.k1.publicKey, in: app)

        // 4) К началу списка.
        let first = row(named: "Аарон", in: app)
        swipes = 0
        while !(first.exists && first.isHittable) && swipes < 30 {
            list.swipeDown()
            swipes += 1
        }
        let names = visibleRowNames(app)
        XCTAssertEqual(names.first, "Аарон")
        XCTAssertEqual(names.dropFirst().first, "Контакт 001")
        let sorted = names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        XCTAssertEqual(names, sorted)
    }

    // MARK: - E22

    @MainActor
    func testUnreadableStoreShowsErrorAndRetry() {
        let app = launch(["-keystore", "memory", "-contacts", "memory", "-contacts-fault", "read"])
        openContacts(app)

        // 1) Экран ошибки, добавить нельзя.
        let error = app.staticTexts["contacts.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(error.label.contains("Не удалось прочитать контакты"), error.label)
        XCTAssertTrue(
            error.label.contains("Файл контактов повреждён или недоступен. Контакты не удалены."), error.label)
        XCTAssertFalse(app.buttons["contacts.add"].exists)
        XCTAssertFalse(app.buttons["contacts.addFirst"].exists)

        // 2) «Повторить» → пустой список.
        app.buttons["contacts.retry"].tap()
        let empty = app.staticTexts["contacts.empty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        XCTAssertTrue(empty.label.contains("Пока нет контактов"), empty.label)

        // 3) Добавление работает.
        addContact(name: "Анна", key: TestKeys.k1.publicKey, in: app)
        XCTAssertEqual(contactRows(app).count, 1)
    }

    // MARK: - Помощники

    @MainActor
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    @MainActor
    private func readOwnKey(_ app: XCUIApplication) -> String {
        XCTAssertTrue(app.staticTexts["mykey.title"].waitForExistence(timeout: 10))
        return app.staticTexts["mykey.publicKey"].label
    }

    @MainActor
    private func openContacts(_ app: XCUIApplication) {
        let tab = app.tabBars.buttons["tab.contacts"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()
        XCTAssertTrue(app.staticTexts["contacts.title"].waitForExistence(timeout: 5))
        // Дождаться конца загрузки: пусто, список или ошибка.
        let loaded = NSPredicate { _, _ in
            app.buttons["contacts.addFirst"].exists || app.buttons["contacts.add"].exists
                || app.staticTexts["contacts.error"].exists
        }
        let expectation = XCTNSPredicateExpectation(predicate: loaded, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 10), .completed, "список не загрузился")
    }

    @MainActor
    private func openAddSheet(_ app: XCUIApplication) {
        let first = app.buttons["contacts.addFirst"]
        if first.exists { first.tap() } else { app.buttons["contacts.add"].tap() }
        XCTAssertTrue(app.staticTexts["addcontact.title"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func addContact(name: String, key: String, in app: XCUIApplication) {
        openAddSheet(app)
        enterKey(key, in: app)
        XCTAssertTrue(app.staticTexts["addcontact.fingerprint"].waitForExistence(timeout: 5))
        enterName(name, in: app)
        let save = app.buttons["addcontact.save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.staticTexts["addcontact.title"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(contactRows(app).firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    private func scan(in app: XCUIApplication) {
        app.buttons["addcontact.scan"].tap()
        let scanner = app.descendants(matching: .any)["scanner.view"]
        XCTAssertTrue(scanner.waitForExistence(timeout: 5), "сканер не открылся")
        XCTAssertTrue(scanner.waitForNonExistence(timeout: 5), "сканер не закрылся сам")
        XCTAssertTrue(app.staticTexts["addcontact.title"].waitForExistence(timeout: 5))
    }

    /// Поле ключа: многострочный `TextField` — в дереве доступности это поле или текстовое представление.
    @MainActor
    private func keyField(_ app: XCUIApplication) -> XCUIElement {
        let view = app.textViews["addcontact.key"]
        return view.exists ? view : app.textFields["addcontact.key"]
    }

    @MainActor
    private func nameField(_ app: XCUIApplication) -> XCUIElement {
        app.textFields["addcontact.name"]
    }

    @MainActor
    private func enterKey(_ text: String, in app: XCUIApplication) {
        let field = keyField(app)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        replaceText(in: field, with: text, app: app)
    }

    @MainActor
    private func enterName(_ text: String, in app: XCUIApplication) {
        let field = nameField(app)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        replaceText(in: field, with: text, app: app)
    }

    /// Стирает текст поля целиком и вводит новый. Курсор ставится в конец нажатием у правого нижнего края текста.
    @MainActor
    private func replaceText(in field: XCUIElement, with text: String, app: XCUIApplication) {
        func currentText() -> String {
            let value = (field.value as? String) ?? ""
            return value == (field.placeholderValue ?? "") ? "" : value
        }
        // Нажатие в правый нижний угол текста (внутри отступа 12 pt) ставит курсор в конец последней строки.
        let frame = field.frame
        let end = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.maxX - 14, dy: frame.maxY - 14))
        end.tap()
        var attempts = 0
        while !currentText().isEmpty && attempts < 3 {
            attempts += 1
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentText().count + 2))
            if !currentText().isEmpty { end.tap() }
        }
        XCTAssertEqual(currentText(), "", "поле не очистилось")
        if !text.isEmpty { field.typeText(text) }
    }

    @MainActor
    private func contactRows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(identifier: "contacts.row")
    }

    @MainActor
    private func row(named name: String, in app: XCUIApplication) -> XCUIElement {
        contactRows(app).matching(NSPredicate(format: "label BEGINSWITH %@", name + ", ")).firstMatch
    }

    private func name(fromRowLabel label: String) -> String {
        guard let range = label.range(of: ", ", options: .backwards) else { return label }
        return String(label[..<range.lowerBound])
    }

    @MainActor
    private func rowNames(_ app: XCUIApplication) -> [String] {
        contactRows(app).allElementsBoundByIndex.map { name(fromRowLabel: $0.label) }
    }

    /// Имена строк, которые сейчас видны на экране, сверху вниз.
    @MainActor
    private func visibleRowNames(_ app: XCUIApplication) -> [String] {
        contactRows(app).allElementsBoundByIndex
            .filter { $0.isHittable }
            .sorted { $0.frame.minY < $1.frame.minY }
            .map { name(fromRowLabel: $0.label) }
    }

    /// Удаляет через карточку все контакты с этим именем (уборка перед тестом на настоящем файле).
    @MainActor
    private func removeContacts(named name: String, in app: XCUIApplication) {
        var attempts = 0
        while row(named: name, in: app).exists && attempts < 10 {
            attempts += 1
            row(named: name, in: app).tap()
            let delete = app.buttons["contact.delete"]
            XCTAssertTrue(delete.waitForExistence(timeout: 5))
            delete.tap()
            let confirm = app.buttons["contact.deleteConfirm"].firstMatch
            XCTAssertTrue(confirm.waitForExistence(timeout: 5))
            confirm.tap()
            XCTAssertTrue(app.staticTexts["contacts.title"].waitForExistence(timeout: 5))
        }
    }

    @MainActor
    private func goBackToList(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["contacts.title"].waitForExistence(timeout: 5))
    }

    /// «Отмена» системного диалога подтверждения (у карточки своей «Отмены» нет).
    @MainActor
    private func dialogCancelButton(_ app: XCUIApplication) -> XCUIElement {
        let inSheet = app.sheets.buttons["Отмена"]
        return inSheet.exists ? inSheet : app.buttons["Отмена"]
    }

    @MainActor
    private func waitForCount(_ query: XCUIElementQuery, _ count: Int, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate { _, _ in query.count == count }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func waitForLabel(_ element: XCUIElement, _ label: String, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
