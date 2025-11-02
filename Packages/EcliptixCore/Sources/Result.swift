import Foundation

public extension Result {

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }

    func unwrap() throws -> Success {
        switch self {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }

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
