import Foundation
import GRPC
import NIOCore
import NIOPosix
import SwiftProtobuf
import EcliptixCore

// MARK: - Networking Module
/// Networking module providing gRPC clients and HTTP services

public struct EcliptixNetworking {
    public static let version = "1.0.0"

    public init() {}
}

// MARK: - Network Connectivity
/// Protocol for monitoring network connectivity
public protocol NetworkConnectivityMonitor {
    var isConnected: Bool { get }
    var connectionType: ConnectionType { get }

    func startMonitoring(statusUpdateHandler: @escaping (ConnectionStatus) -> Void)
    func stopMonitoring()
}

public enum ConnectionType {
    case wifi
    case cellular
    case ethernet
    case none
}

public enum ConnectionStatus {
    case connected(ConnectionType)
    case disconnected
}

// MARK: - gRPC Service Base
/// Base protocol for gRPC service clients
public protocol GRPCServiceClient {
    associatedtype Request: Message
    associatedtype Response: Message

    func call(_ request: Request) async throws -> Response
}

// MARK: - Request Interceptor
/// Protocol for intercepting and modifying gRPC requests
public protocol RequestInterceptor {
    func intercept<Request, Response>(
        request: Request,
        context: InterceptorContext,
        next: @escaping (Request, InterceptorContext) async throws -> Response
    ) async throws -> Response
}

public struct InterceptorContext {
    public var headers: [String: String]
    public var timeout: TimeInterval?

    public init(headers: [String: String] = [:], timeout: TimeInterval? = nil) {
        self.headers = headers
        self.timeout = timeout
    }
}

// MARK: - Retry Policy
/// Protocol for retry strategies
public protocol RetryPolicy {
    func shouldRetry(attempt: Int, error: Error) -> Bool
    func delay(for attempt: Int) -> TimeInterval
}

/// Exponential backoff retry policy
public struct ExponentialBackoffRetryPolicy: RetryPolicy {
    public let maxAttempts: Int
    public let baseDelay: TimeInterval
    public let maxDelay: TimeInterval

    public init(maxAttempts: Int = 3, baseDelay: TimeInterval = 1.0, maxDelay: TimeInterval = 30.0) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }

    public func shouldRetry(attempt: Int, error: Error) -> Bool {
        return attempt < maxAttempts
    }

    public func delay(for attempt: Int) -> TimeInterval {
        let exponentialDelay = baseDelay * pow(2.0, Double(attempt))
        return min(exponentialDelay, maxDelay)
    }
}

// MARK: - Network Service Configuration
public struct NetworkServiceConfiguration {
    public let host: String
    public let port: Int
    public let useTLS: Bool
    public let certificatePinning: Bool
    public let timeout: TimeInterval
    public let retryPolicy: RetryPolicy

    public init(
        host: String,
        port: Int,
        useTLS: Bool = true,
        certificatePinning: Bool = true,
        timeout: TimeInterval = 30.0,
        retryPolicy: RetryPolicy = ExponentialBackoffRetryPolicy()
    ) {
        self.host = host
        self.port = port
        self.useTLS = useTLS
        self.certificatePinning = certificatePinning
        self.timeout = timeout
        self.retryPolicy = retryPolicy
    }
}

// MARK: - Networking Errors
public enum NetworkError: LocalizedError {
    case notConnected
    case timeout
    case invalidResponse
    case serverError(Int)
    case grpcError(GRPCStatus)
    case connectionFailed(Error)
    case certificatePinningFailed

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "No network connection available"
        case .timeout:
            return "Request timed out"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let code):
            return "Server error: \(code)"
        case .grpcError(let status):
            return "gRPC error: \(status.code) - \(status.message ?? "Unknown")"
        case .connectionFailed(let error):
            return "Connection failed: \(error.localizedDescription)"
        case .certificatePinningFailed:
            return "Certificate pinning validation failed"
        }
    }
}
