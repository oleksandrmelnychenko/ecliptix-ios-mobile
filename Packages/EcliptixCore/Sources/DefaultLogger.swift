import Foundation
import os.log

public final class DefaultLogger: Logger {
    private let osLogger: os.Logger
    private let subsystem: String

    public init(subsystem: String = "com.ecliptix.ios", category: String = "default") {
        self.subsystem = subsystem
        self.osLogger = os.Logger(subsystem: subsystem, category: category)
    }

    public func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        osLogger.debug("[\(fileName):\(line)] \(function) - \(message)")
    }

    public func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        osLogger.info("[\(fileName):\(line)] \(function) - \(message)")
    }

    public func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        osLogger.warning("[\(fileName):\(line)] \(function) - \(message)")
    }

    public func error(_ message: String, error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        if let error = error {
            osLogger.error("[\(fileName):\(line)] \(function) - \(message): \(error.localizedDescription)")
        } else {
            osLogger.error("[\(fileName):\(line)] \(function) - \(message)")
        }
    }
}

public nonisolated(unsafe) var Log: Logger = DefaultLogger()

public func configureLogger(_ logger: Logger) {
    Log = logger
}
