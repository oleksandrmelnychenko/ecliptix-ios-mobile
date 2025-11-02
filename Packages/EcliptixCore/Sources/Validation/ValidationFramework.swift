import Combine
import Foundation

public enum ValidationResult: Sendable {
    case valid
    case invalid(String)

    public var isValid: Bool {
        if case .valid = self {
            return true
        }
        return false
    }

    public var errorMessage: String? {
        if case .invalid(let message) = self {
            return message
        }
        return nil
    }
}

public protocol FieldValidator: Sendable {

    func validate(_ value: String) -> ValidationResult
}

@MainActor
public final class ValidationState: ObservableObject {

    @Published public private(set) var value: String = ""
    @Published public private(set) var validationResult: ValidationResult = .valid
    @Published public private(set) var isTouched: Bool = false

    private let validators: [FieldValidator]
    private var cancellables = Set<AnyCancellable>()

    public var isValid: Bool {
        validationResult.isValid
    }

    public var errorMessage: String? {

        guard isTouched else { return nil }
        return validationResult.errorMessage
    }

    public var shouldShowError: Bool {
        isTouched && !isValid
    }

    public init(validators: [FieldValidator] = []) {
        self.validators = validators
    }

    public init(validator: FieldValidator) {
        self.validators = [validator]
    }

    public func updateValue(_ newValue: String) {
        value = newValue
        validate()
    }

    public func markAsTouched() {
        isTouched = true
    }

    public func reset() {
        value = ""
        validationResult = .valid
        isTouched = false
    }

    @discardableResult
    public func validate() -> ValidationResult {

        for validator in validators {
            let result = validator.validate(value)
            if !result.isValid {
                validationResult = result
                return result
            }
        }

        validationResult = .valid
        return .valid
    }

    @discardableResult
    public func validateAndTouch() -> ValidationResult {
        markAsTouched()
        return validate()
    }
}

public extension ValidationState {

    var validationPublisher: AnyPublisher<ValidationResult, Never> {
        $validationResult.eraseToAnyPublisher()
    }

    var isValidPublisher: AnyPublisher<Bool, Never> {
        $validationResult
            .map { $0.isValid }
            .eraseToAnyPublisher()
    }

    var errorMessagePublisher: AnyPublisher<String?, Never> {
        Publishers.CombineLatest($isTouched, $validationResult)
            .map { isTouched, result in
                guard isTouched else { return nil }
                return result.errorMessage
            }
            .eraseToAnyPublisher()
    }

    var shouldShowErrorPublisher: AnyPublisher<Bool, Never> {
        Publishers.CombineLatest($isTouched, $validationResult)
            .map { isTouched, result in
                isTouched && !result.isValid
            }
            .eraseToAnyPublisher()
    }
}

@MainActor
public final class FormValidationState: ObservableObject {

    private let fields: [ValidationState]
    @Published public private(set) var isValid: Bool = true

    private var cancellables = Set<AnyCancellable>()

    public init(fields: [ValidationState]) {
        self.fields = fields
        setupBindings()
    }

    @discardableResult
    public func validateAll() -> Bool {
        var allValid = true

        for field in fields {
            let result = field.validate()
            if !result.isValid {
                allValid = false
            }
        }

        isValid = allValid
        return allValid
    }

    @discardableResult
    public func validateAllAndTouch() -> Bool {
        var allValid = true

        for field in fields {
            let result = field.validateAndTouch()
            if !result.isValid {
                allValid = false
            }
        }

        isValid = allValid
        return allValid
    }

    public func resetAll() {
        fields.forEach { $0.reset() }
        isValid = true
    }

    private func setupBindings() {

        let publishers = fields.map { $0.isValidPublisher }

        guard !publishers.isEmpty else { return }

        if publishers.count == 1 {
            publishers[0]
                .assign(to: &$isValid)
        } else {
            Publishers.MergeMany(publishers)
                .map { [weak self] _ in
                    self?.fields.allSatisfy { $0.isValid } ?? true
                }
                .removeDuplicates()
                .assign(to: &$isValid)
        }
    }
}

public extension FormValidationState {

    var isValidPublisher: AnyPublisher<Bool, Never> {
        $isValid.eraseToAnyPublisher()
    }

    var hasErrors: Bool {
        fields.contains { !$0.isValid }
    }

    var errorMessages: [String] {
        fields.compactMap { $0.errorMessage }
    }
}

public struct RequiredFieldValidator: FieldValidator {
    private let errorMessage: String

    public init(errorMessage: String = "This field is required") {
        self.errorMessage = errorMessage
    }

    public func validate(_ value: String) -> ValidationResult {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? .invalid(errorMessage) : .valid
    }
}

public struct MinLengthValidator: FieldValidator {
    private let minLength: Int
    private let errorMessage: String?

    public init(minLength: Int, errorMessage: String? = nil) {
        self.minLength = minLength
        self.errorMessage = errorMessage
    }

    public func validate(_ value: String) -> ValidationResult {
        if value.count < minLength {
            let message = errorMessage ?? "Must be at least \(minLength) characters"
            return .invalid(message)
        }
        return .valid
    }
}

public struct MaxLengthValidator: FieldValidator {
    private let maxLength: Int
    private let errorMessage: String?

    public init(maxLength: Int, errorMessage: String? = nil) {
        self.maxLength = maxLength
        self.errorMessage = errorMessage
    }

    public func validate(_ value: String) -> ValidationResult {
        if value.count > maxLength {
            let message = errorMessage ?? "Must be at most \(maxLength) characters"
            return .invalid(message)
        }
        return .valid
    }
}

public struct RegexValidator: FieldValidator {
    private let pattern: String
    private let errorMessage: String

    public init(pattern: String, errorMessage: String) {
        self.pattern = pattern
        self.errorMessage = errorMessage
    }

    public func validate(_ value: String) -> ValidationResult {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return .invalid("Invalid validation pattern")
        }

        let range = NSRange(value.startIndex..., in: value)
        let matches = regex.matches(in: value, range: range)

        return matches.isEmpty ? .invalid(errorMessage) : .valid
    }
}

public struct EmailValidator: FieldValidator {
    private let errorMessage: String

    public init(errorMessage: String = "Invalid email address") {
        self.errorMessage = errorMessage
    }

    public func validate(_ value: String) -> ValidationResult {
        let emailPattern = "^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$"
        let regex = try? NSRegularExpression(pattern: emailPattern, options: .caseInsensitive)

        guard let regex = regex else {
            return .invalid("Invalid email pattern")
        }

        let range = NSRange(value.startIndex..., in: value)
        let matches = regex.matches(in: value, range: range)

        return matches.isEmpty ? .invalid(errorMessage) : .valid
    }
}

public struct NumericValidator: FieldValidator {
    private let errorMessage: String

    public init(errorMessage: String = "Must contain only numbers") {
        self.errorMessage = errorMessage
    }

    public func validate(_ value: String) -> ValidationResult {
        let numericSet = CharacterSet.decimalDigits
        let valueSet = CharacterSet(charactersIn: value)

        return numericSet.isSuperset(of: valueSet) ? .valid : .invalid(errorMessage)
    }
}

public struct CompositeValidator: FieldValidator {
    private let validators: [FieldValidator]

    public init(validators: [FieldValidator]) {
        self.validators = validators
    }

    public func validate(_ value: String) -> ValidationResult {
        for validator in validators {
            let result = validator.validate(value)
            if !result.isValid {
                return result
            }
        }
        return .valid
    }
}
