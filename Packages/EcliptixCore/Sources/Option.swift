import Foundation

// MARK: - Option Type
/// Option type similar to Rust/C# for explicit optionality
/// Note: Swift has Optional built-in, but this provides a compatible API for migration
public enum Option<T> {
    case some(T)
    case none

    /// Returns true if the option contains a value
    public var hasValue: Bool {
        if case .some = self { return true }
        return false
    }

    /// Returns true if the option is empty
    public var isEmpty: Bool {
        if case .none = self { return true }
        return false
    }

    /// Returns the wrapped value, or nil if none
    public var value: T? {
        switch self {
        case .some(let val):
            return val
        case .none:
            return nil
        }
    }

    /// Unwraps the value, throwing if none
    public func unwrap() throws -> T {
        switch self {
        case .some(let val):
            return val
        case .none:
            throw OptionError.noValue
        }
    }

    /// Unwraps the value or returns a default
    public func unwrapOr(_ defaultValue: T) -> T {
        switch self {
        case .some(let val):
            return val
        case .none:
            return defaultValue
        }
    }

    /// Maps the value if present
    public func map<U>(_ transform: (T) -> U) -> Option<U> {
        switch self {
        case .some(let val):
            return .some(transform(val))
        case .none:
            return .none
        }
    }

    /// FlatMaps the value if present
    public func flatMap<U>(_ transform: (T) -> Option<U>) -> Option<U> {
        switch self {
        case .some(let val):
            return transform(val)
        case .none:
            return .none
        }
    }
}

// MARK: - Option Initializers
public extension Option {
    /// Creates Some option
    static func some(_ value: T) -> Option<T> {
        return .some(value)
    }

    /// Creates None option
    static var none: Option<T> {
        return .none
    }

    /// Creates option from Swift Optional
    init(_ optional: T?) {
        if let value = optional {
            self = .some(value)
        } else {
            self = .none
        }
    }
}

// MARK: - Option Equatable
extension Option: Equatable where T: Equatable {}

// MARK: - Option Errors
public enum OptionError: LocalizedError {
    case noValue

    public var errorDescription: String? {
        switch self {
        case .noValue:
            return "Option contains no value"
        }
    }
}
