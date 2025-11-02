import Foundation

public struct MobileNumberValidator: @unchecked Sendable, FieldValidator {
    private let localization: LocalizationService
    private let allowInternational: Bool

    public init(
        localization: LocalizationService,
        allowInternational: Bool = true
    ) {
        self.localization = localization
        self.allowInternational = allowInternational
    }

    public func validate(_ value: String) -> ValidationResult {

        let cleanedValue = value.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "+", with: "")

        if cleanedValue.isEmpty {
            return .invalid(localization[LocalizationKeys.Validation.mobileNumberRequired])
        }

        let numericSet = CharacterSet.decimalDigits
        let valueSet = CharacterSet(charactersIn: cleanedValue)

        guard numericSet.isSuperset(of: valueSet) else {
            return .invalid(localization[LocalizationKeys.Validation.mobileNumberInvalid])
        }

        let minLength = 10
        let maxLength = allowInternational ? 15 : 10

        if cleanedValue.count < minLength {
            return .invalid(localization[LocalizationKeys.Validation.mobileNumberTooShort])
        }

        if cleanedValue.count > maxLength {
            return .invalid(localization[LocalizationKeys.Validation.mobileNumberTooLong])
        }

        if allowInternational && value.hasPrefix("+") {

            if cleanedValue.count < 11 {
                return .invalid(localization[LocalizationKeys.Validation.mobileNumberInvalid])
            }
        }

        return .valid
    }
}

public struct SecureKeyValidator: @unchecked Sendable, FieldValidator {
    private let localization: LocalizationService
    private let minLength: Int
    private let maxLength: Int
    private let requireUppercase: Bool
    private let requireLowercase: Bool
    private let requireDigits: Bool
    private let requireSpecialChars: Bool

    public init(
        localization: LocalizationService,
        minLength: Int = 16,
        maxLength: Int = 64,
        requireUppercase: Bool = true,
        requireLowercase: Bool = true,
        requireDigits: Bool = true,
        requireSpecialChars: Bool = false
    ) {
        self.localization = localization
        self.minLength = minLength
        self.maxLength = maxLength
        self.requireUppercase = requireUppercase
        self.requireLowercase = requireLowercase
        self.requireDigits = requireDigits
        self.requireSpecialChars = requireSpecialChars
    }

    public func validate(_ value: String) -> ValidationResult {
        if value.isEmpty {
            return .invalid(localization[LocalizationKeys.Validation.secureKeyRequired])
        }

        if value.count < minLength {
            return .invalid(localization.getString(
                LocalizationKeys.Validation.secureKeyTooShort,
                minLength
            ))
        }

        if value.count > maxLength {
            return .invalid(localization.getString(
                LocalizationKeys.Validation.secureKeyTooLong,
                maxLength
            ))
        }

        if requireUppercase && !value.contains(where: { $0.isUppercase }) {
            return .invalid(localization[LocalizationKeys.Validation.secureKeyNeedsUppercase])
        }

        if requireLowercase && !value.contains(where: { $0.isLowercase }) {
            return .invalid(localization[LocalizationKeys.Validation.secureKeyNeedsLowercase])
        }

        if requireDigits && !value.contains(where: { $0.isNumber }) {
            return .invalid(localization[LocalizationKeys.Validation.secureKeyNeedsDigit])
        }

        if requireSpecialChars {
            let specialChars = CharacterSet(charactersIn: "!@#$%^&*()_+-=[]{}|;:,.<>?")
            let valueSet = CharacterSet(charactersIn: value)

            if valueSet.intersection(specialChars).isEmpty {
                return .invalid(localization[LocalizationKeys.Validation.secureKeyNeedsSpecial])
            }
        }

        return .valid
    }
}

public struct PasswordValidator: @unchecked Sendable, FieldValidator {
    private let localization: LocalizationService
    private let minLength: Int
    private let maxLength: Int
    private let requireUppercase: Bool
    private let requireLowercase: Bool
    private let requireDigits: Bool
    private let requireSpecialChars: Bool

    public init(
        localization: LocalizationService,
        minLength: Int = 8,
        maxLength: Int = 128,
        requireUppercase: Bool = true,
        requireLowercase: Bool = true,
        requireDigits: Bool = true,
        requireSpecialChars: Bool = true
    ) {
        self.localization = localization
        self.minLength = minLength
        self.maxLength = maxLength
        self.requireUppercase = requireUppercase
        self.requireLowercase = requireLowercase
        self.requireDigits = requireDigits
        self.requireSpecialChars = requireSpecialChars
    }

    public func validate(_ value: String) -> ValidationResult {
        if value.isEmpty {
            return .invalid(localization[LocalizationKeys.Validation.passwordRequired])
        }

        if value.count < minLength {
            return .invalid(localization.getString(
                LocalizationKeys.Validation.passwordTooShort,
                minLength
            ))
        }

        if value.count > maxLength {
            return .invalid(localization.getString(
                LocalizationKeys.Validation.passwordTooLong,
                maxLength
            ))
        }

        if requireUppercase && !value.contains(where: { $0.isUppercase }) {
            return .invalid(localization[LocalizationKeys.Validation.passwordNeedsUppercase])
        }

        if requireLowercase && !value.contains(where: { $0.isLowercase }) {
            return .invalid(localization[LocalizationKeys.Validation.passwordNeedsLowercase])
        }

        if requireDigits && !value.contains(where: { $0.isNumber }) {
            return .invalid(localization[LocalizationKeys.Validation.passwordNeedsDigit])
        }

        if requireSpecialChars {
            let specialChars = CharacterSet(charactersIn: "!@#$%^&*()_+-=[]{}|;:,.<>?")
            let valueSet = CharacterSet(charactersIn: value)

            if valueSet.intersection(specialChars).isEmpty {
                return .invalid(localization[LocalizationKeys.Validation.passwordNeedsSpecial])
            }
        }

        return .valid
    }
}

public struct PasswordConfirmationValidator: @unchecked Sendable, FieldValidator {
    private let localization: LocalizationService
    private let originalPassword: () -> String

    public init(
        localization: LocalizationService,
        originalPassword: @escaping () -> String
    ) {
        self.localization = localization
        self.originalPassword = originalPassword
    }

    public func validate(_ value: String) -> ValidationResult {
        if value.isEmpty {
            return .invalid(localization[LocalizationKeys.Validation.passwordConfirmRequired])
        }

        if value != originalPassword() {
            return .invalid(localization[LocalizationKeys.Validation.passwordsDoNotMatch])
        }

        return .valid
    }
}

public struct OTPValidator: @unchecked Sendable, FieldValidator {
    private let localization: LocalizationService
    private let length: Int

    public init(
        localization: LocalizationService,
        length: Int = 6
    ) {
        self.localization = localization
        self.length = length
    }

    public func validate(_ value: String) -> ValidationResult {
        if value.isEmpty {
            return .invalid(localization[LocalizationKeys.Validation.otpRequired])
        }

        let numericSet = CharacterSet.decimalDigits
        let valueSet = CharacterSet(charactersIn: value)

        guard numericSet.isSuperset(of: valueSet) else {
            return .invalid(localization[LocalizationKeys.Validation.otpInvalid])
        }

        if value.count != length {
            return .invalid(localization.getString(
                LocalizationKeys.Validation.otpInvalidLength,
                length
            ))
        }

        return .valid
    }
}

public struct UsernameValidator: @unchecked Sendable, FieldValidator {
    private let localization: LocalizationService
    private let minLength: Int
    private let maxLength: Int

    public init(
        localization: LocalizationService,
        minLength: Int = 3,
        maxLength: Int = 32
    ) {
        self.localization = localization
        self.minLength = minLength
        self.maxLength = maxLength
    }

    public func validate(_ value: String) -> ValidationResult {
        if value.isEmpty {
            return .invalid(localization[LocalizationKeys.Validation.usernameRequired])
        }

        if value.count < minLength {
            return .invalid(localization.getString(
                LocalizationKeys.Validation.usernameTooShort,
                minLength
            ))
        }

        if value.count > maxLength {
            return .invalid(localization.getString(
                LocalizationKeys.Validation.usernameTooLong,
                maxLength
            ))
        }

        let allowedSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let valueSet = CharacterSet(charactersIn: value)

        guard allowedSet.isSuperset(of: valueSet) else {
            return .invalid(localization[LocalizationKeys.Validation.usernameInvalidChars])
        }

        guard let firstChar = value.first, firstChar.isLetter || firstChar.isNumber else {
            return .invalid(localization[LocalizationKeys.Validation.usernameInvalidStart])
        }

        return .valid
    }
}

public struct DeviceNameValidator: @unchecked Sendable, FieldValidator {
    private let localization: LocalizationService
    private let minLength: Int
    private let maxLength: Int

    public init(
        localization: LocalizationService,
        minLength: Int = 2,
        maxLength: Int = 64
    ) {
        self.localization = localization
        self.minLength = minLength
        self.maxLength = maxLength
    }

    public func validate(_ value: String) -> ValidationResult {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return .invalid(localization[LocalizationKeys.Validation.deviceNameRequired])
        }

        if trimmed.count < minLength {
            return .invalid(localization.getString(
                LocalizationKeys.Validation.deviceNameTooShort,
                minLength
            ))
        }

        if trimmed.count > maxLength {
            return .invalid(localization.getString(
                LocalizationKeys.Validation.deviceNameTooLong,
                maxLength
            ))
        }

        return .valid
    }
}
