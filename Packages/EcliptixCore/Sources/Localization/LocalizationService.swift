import Combine
import Foundation

public protocol LocalizationService: AnyObject {

    subscript(key: String) -> String { get }

    func getString(_ key: String, _ args: CVarArg...) -> String

    func setCulture(_ cultureName: String, onCultureChanged: (@Sendable () -> Void)?)

    var currentCulture: Locale { get }

    var currentCultureName: String { get }

    var languageChanged: AnyPublisher<Void, Never> { get }
}

public final class DefaultLocalizationService: @unchecked Sendable, LocalizationService {

    private let defaultLanguageStrings: [String: String]
    private var currentLanguageStrings: [String: String]
    private var _currentCulture: Locale
    nonisolated(unsafe) private let languageChangedSubject = PassthroughSubject<Void, Never>()
    private let lock = NSLock()

    public var currentCulture: Locale {
        lock.lock()
        defer { lock.unlock() }
        return _currentCulture
    }

    public var currentCultureName: String {
        lock.lock()
        defer { lock.unlock() }
        return _currentCulture.identifier
    }

    public var languageChanged: AnyPublisher<Void, Never> {
        languageChangedSubject.eraseToAnyPublisher()
    }

    public init(defaultCultureName: String = "en-US") {
        self.defaultLanguageStrings = LocalizationData.englishStrings
        self._currentCulture = Self.createLocale(from: defaultCultureName)

        if let languageStrings = LocalizationData.allLanguages[defaultCultureName] {
            self.currentLanguageStrings = languageStrings
        } else {
            self.currentLanguageStrings = self.defaultLanguageStrings
        }

        Log.info("[Localization] Service initialized with culture: \(defaultCultureName)")
    }

    public subscript(key: String) -> String {
        guard !key.isEmpty else {
            return "[INVALID_KEY]"
        }

        lock.lock()
        defer { lock.unlock() }

        if let value = currentLanguageStrings[key] {
            return value
        }

        if let defaultValue = defaultLanguageStrings[key] {
            return defaultValue
        }

        return "!\(key)!"
    }

    public func getString(_ key: String, _ args: CVarArg...) -> String {
        let formatString = self[key]

        guard !formatString.hasPrefix("!") || !formatString.hasSuffix("!")  else {
            return formatString
        }

        guard !args.isEmpty else {
            return formatString
        }

        return String(format: formatString, arguments: args)
    }

    public func setCulture(_ cultureName: String, onCultureChanged: (@Sendable () -> Void)? = nil) {
        guard !cultureName.isEmpty else {
            Log.warning("[Localization] Attempted to set empty culture name")
            return
        }

        let newLocale = Self.createLocale(from: cultureName)

        lock.lock()
        let cultureChanged = _currentCulture.identifier != newLocale.identifier

        if cultureChanged {
            _currentCulture = newLocale

            if let languageStrings = LocalizationData.allLanguages[cultureName] {
                currentLanguageStrings = languageStrings
            } else {
                currentLanguageStrings = defaultLanguageStrings
            }

            Log.info("[Localization] Culture changed to: \(cultureName)")
        }
        lock.unlock()

        if cultureChanged {

            DispatchQueue.main.async { [weak self, onCultureChanged] in
                guard let self = self else { return }
                self.languageChangedSubject.send(())
                onCultureChanged?()
            }
        }
    }

    private static func createLocale(from cultureName: String?) -> Locale {
        guard let cultureName = cultureName, !cultureName.isEmpty else {
            return Locale(identifier: "en-US")
        }

        let locale = Locale(identifier: cultureName)

        if locale.identifier.isEmpty {
            Log.warning("[Localization] Invalid culture name '\(cultureName)', using en-US")
            return Locale(identifier: "en-US")
        }

        return locale
    }
}

extension LocalizationService {

    public var languageChangeTrigger: AnyPublisher<Void, Never> {
        Just(())
            .merge(with: languageChanged)
            .eraseToAnyPublisher()
    }
}
