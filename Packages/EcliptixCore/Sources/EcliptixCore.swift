import Foundation

public struct EcliptixCore {
    public static let version = "1.0.0"

    public init() {}
}

public enum ApplicationState: Equatable {
    case initializing
    case anonymous
    case authenticated(userId: String)

    public var isAuthenticated: Bool {
        if case .authenticated = self {
            return true
        }
        return false
    }
}

public protocol Logger {
    func debug(_ message: String, file: String, function: String, line: Int)
    func info(_ message: String, file: String, function: String, line: Int)
    func warning(_ message: String, file: String, function: String, line: Int)
    func error(_ message: String, error: Error?, file: String, function: String, line: Int)
}

public extension Logger {
    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        debug(message, file: file, function: function, line: line)
    }

    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        info(message, file: file, function: function, line: line)
    }

    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        warning(message, file: file, function: function, line: line)
    }

    func error(_ message: String, error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        self.error(message, error: error, file: file, function: function, line: line)
    }
}
