import Foundation
import os

enum L10n {
    private static let tableName = "Localizable"
    nonisolated(unsafe) private static var languageOverride = OSAllocatedUnfairLock<String?>(initialState: nil)

    #if SWIFT_PACKAGE
    private static let resourceBundle = Bundle.module
    #else
    private static let resourceBundle = Bundle.main
    #endif

    static func tr(_ key: String, _ arguments: CVarArg...) -> String {
        localizedString(forKey: key, localeIdentifier: nil, arguments: arguments)
    }

    static func tr(_ key: String, localeIdentifier: String, _ arguments: CVarArg...) -> String {
        localizedString(forKey: key, localeIdentifier: localeIdentifier, arguments: arguments)
    }

    static func resourceURL(forLocalization localization: String) -> URL? {
        localizedBundle(localeIdentifier: localization)?.url(forResource: tableName, withExtension: "strings")
    }

    static func applyAppLanguage(_ language: AppLanguage) {
        languageOverride.withLock {
            $0 = language.localeIdentifier
        }
    }

    private static func localizedString(
        forKey key: String,
        localeIdentifier: String?,
        arguments: [CVarArg]
    ) -> String {
        let effectiveLocaleIdentifier = localeIdentifier ?? languageOverride.withLock { $0 }
        let bundle = effectiveLocaleIdentifier.flatMap(localizedBundle(localeIdentifier:)) ?? resourceBundle
        let format = bundle.localizedString(forKey: key, value: nil, table: tableName)
        let value = format == key ? englishFallback(forKey: key) : format
        guard !arguments.isEmpty else { return value }
        let locale = effectiveLocaleIdentifier.map(Locale.init(identifier:)) ?? Locale.current
        return String(format: value, locale: locale, arguments: arguments)
    }

    private static func englishFallback(forKey key: String) -> String {
        localizedBundle(localeIdentifier: "en")?
            .localizedString(forKey: key, value: key, table: tableName) ?? key
    }

    private static func localizedBundle(localeIdentifier: String) -> Bundle? {
        for identifier in localeCandidates(for: localeIdentifier) {
            if let path = resourceBundle.path(forResource: identifier, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }
        return nil
    }

    private static func localeCandidates(for localeIdentifier: String) -> [String] {
        let normalized = localeIdentifier.replacingOccurrences(of: "_", with: "-")
        let language = normalized.split(separator: "-").first.map(String.init)
        return [normalized, language].compactMap { $0 }.uniquedPreservingOrder()
    }
}

private extension Array where Element: Hashable {
    func uniquedPreservingOrder() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
