import Foundation

// MARK: - Result Extensions
/// Swift's Result type is already built-in, but we add convenient extensions

public extension Result {
    /// Returns true if the result is a success
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    /// Returns true if the result is a failure
    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }

    /// Unwraps the success value, throwing if failure
    func unwrap() throws -> Success {
        switch self {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }

    /// Unwraps the error, throwing if success
    func unwrapError() throws -> Failure {
        switch self {
        case .success:
            throw ResultError.notAnError
        case .failure(let error):
            return error
        }
    }
}

public enum ResultError: Error {
    case notAnError
}

// MARK: - Unit Type
/// Represents a void/empty result (equivalent to C#'s Unit)
public struct Unit: Equatable, Sendable {
    public static let value = Unit()
    private init() {}
}
