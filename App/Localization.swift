import Foundation
import LibraryCore
import BookCatalog

typealias LocalizedMessage = LibraryCore.LocalizedMessage

@MainActor
func L(_ message: LocalizedMessage) -> String {
    message.rendered(template: L10n.string(message.key))
}

@MainActor
func catalogSourceDisplayName(_ source: String) -> String {
    source == "MEGOGO BOOKS" ? L("Книжный каталог") : source
}

@MainActor
enum L10n {
    // Reading an observable preference inside a View's body registers that view
    // for language changes, including calls through L and other display helpers.
    static var locale: Locale { AppPreferences.shared.locale }
    static func string(_ key: String) -> String {
        let language = AppPreferences.shared.language.rawValue
        return translations[key]?[language] ?? translations[key]?["ru"] ?? key
    }
    static func date(_ value: Date) -> String {
        value.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
    }

    private static let translations: [String: [String: String]] = {
        var result: [String: [String: String]] = [:]
        for name in ["Library", "Catalog", "Settings", "Errors", "Topics", "Covers", "ScanFlow", "Privacy"] {
            let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "Localization")
                ?? Bundle.main.url(forResource: name, withExtension: "json")
            guard let url, let data = try? Data(contentsOf: url),
                  let entries = try? JSONDecoder().decode([String: [String: String]].self, from: data) else {
                assertionFailure("Missing localization resource: \(name)")
                continue
            }
            result.merge(entries) { _, new in new }
        }
        return result
    }()

    static func error(_ error: Error) -> String {
        if let error = error as? CatalogError {
            switch error {
            case .invalidISBN: return L("Некорректный ISBN. Проверьте цифры и контрольную сумму.")
            case .invalidResponse: return L("Не удалось прочитать ответ каталога книг.")
            case .httpStatus(429): return L("Каталог временно ограничил количество запросов. Попробуйте позже.")
            case .httpStatus(let code): return L("Каталог вернул ошибку HTTP \(code).")
            }
        }
        if let error = error as? LibraryDataError {
            switch error {
            case .invalid(let reason): return string(reason)
            case .unsupportedVersion(let version): return L("Неподдерживаемая версия данных: \(version)")
            }
        }
        if error is LibraryDatabaseError { return L("Не удалось прочитать или сохранить базу данных. Перезапустите приложение.") }
        if error is DecodingError { return L("Не удалось прочитать данные. Проверьте формат файла.") }
        if error is EncodingError { return L("Не удалось подготовить данные для сохранения.") }
        if error is CancellationError { return L("Действие отменено.") }
        let underlying = error as NSError
        if underlying.domain == NSURLErrorDomain {
            switch URLError.Code(rawValue: underlying.code) {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return L("Нет подключения к интернету. Проверьте сеть и повторите попытку.")
            case .timedOut: return L("Сервер не ответил вовремя. Попробуйте ещё раз.")
            case .cancelled: return L("Действие отменено.")
            default: return L("Не удалось подключиться к сервису. Код ошибки: \(underlying.code).")
            }
        }
        if underlying.domain == NSCocoaErrorDomain {
            switch CocoaError.Code(rawValue: underlying.code) {
            case .fileReadNoPermission, .fileWriteNoPermission: return L("Нет доступа к файлу. Проверьте разрешение и повторите попытку.")
            case .fileNoSuchFile, .fileReadNoSuchFile: return L("Файл не найден.")
            case .fileWriteOutOfSpace: return L("На устройстве недостаточно свободного места.")
            default: return L("Не удалось обработать файл. Код ошибки: \(underlying.code).")
            }
        }
        return L("Не удалось выполнить действие. Код ошибки: \(underlying.code).")
    }
}
