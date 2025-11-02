import EcliptixCore
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import NIOCore
import NIOHTTP2
import NIOPosix
import NIOSSL

public typealias HTTP2Transport = HTTP2ClientTransport.Posix

public struct GRPCChannelConfiguration: Sendable {
    public let host: String
    public let port: Int
    public let useTLS: Bool
    public let keepaliveInterval: TimeInterval
    public let keepaliveTimeout: TimeInterval
    public let connectionTimeout: TimeInterval

    public static let `default` = GRPCChannelConfiguration(
        host: "api.ecliptix.com",
        port: 443,
        useTLS: true,
        keepaliveInterval: 30.0,
        keepaliveTimeout: 10.0,
        connectionTimeout: 30.0
    )

    public init(
        host: String,
        port: Int,
        useTLS: Bool = true,
        keepaliveInterval: TimeInterval = 30.0,
        keepaliveTimeout: TimeInterval = 10.0,
        connectionTimeout: TimeInterval = 30.0
    ) {
        self.host = host
        self.port = port
        self.useTLS = useTLS
        self.keepaliveInterval = keepaliveInterval
        self.keepaliveTimeout = keepaliveTimeout
        self.connectionTimeout = connectionTimeout
    }
}

@MainActor
public final class GRPCChannelManager {
    private let configuration: GRPCChannelConfiguration
    private var clientPool: [GRPCClient<HTTP2Transport>] = []
    private var currentPoolIndex: Int = 0
    private let poolSize: Int
    private var isShutdown = false

    public init(configuration: GRPCChannelConfiguration = .default, poolSize: Int = 3) {
        self.configuration = configuration
        self.poolSize = min(max(poolSize, 1), 10)
        Log.info("[GRPCChannelManager] Initialized with pool size \(self.poolSize) for \(configuration.host):\(configuration.port)")
    }

    deinit {
        if !isShutdown {
            Log.warning("[GRPCChannelManager] Deallocated without explicit shutdown")
        }
    }

    public func getClient() throws -> GRPCClient<HTTP2Transport> {
        guard !isShutdown else {
            throw GRPCChannelError.connectionFailed("Channel manager shut down")
        }

        if clientPool.isEmpty {
            try initializePool()
        }

        let client = clientPool[currentPoolIndex]
        currentPoolIndex = (currentPoolIndex + 1) % clientPool.count

        return client
    }

    private func initializePool() throws {
        Log.info("[GRPCChannelManager] Initializing connection pool with \(poolSize) clients")

        for i in 0..<poolSize {
            let client = try createClient()
            clientPool.append(client)
            Log.debug("[GRPCChannelManager] Created pool client \(i + 1)/\(poolSize)")
        }

        Log.info("[GRPCChannelManager] [OK] Connection pool initialized with \(clientPool.count) clients")
    }
    private func createClient() throws -> GRPCClient<HTTP2Transport> {
        let transportSecurity: HTTP2Transport.TransportSecurity
        if configuration.useTLS {
            transportSecurity = .tls
        } else {
            transportSecurity = .plaintext
        }

        let transport = try HTTP2Transport(
            target: .dns(host: configuration.host, port: configuration.port),
            transportSecurity: transportSecurity,
            config: .defaults(
                configure: { transportConfig in
                    transportConfig.http2.targetWindowSize = 65535
                    transportConfig.http2.maxFrameSize = 16384

                    transportConfig.connection.keepalive = .init(
                        time: .seconds(Int64(configuration.keepaliveInterval)),
                        timeout: .seconds(Int64(configuration.keepaliveTimeout)),
                        allowWithoutCalls: false
                    )

                    transportConfig.backoff = .defaults
                }
            )
        )

        let grpcClient = GRPCClient(transport: transport)

        Log.info("[GRPCChannelManager] Created gRPC client to \(configuration.host):\(configuration.port)")
        return grpcClient
    }

    public func shutdown() async {
        let clientsToShutdown = clientPool
        clientPool.removeAll()
        isShutdown = true

        if !clientsToShutdown.isEmpty {
            Log.info("[GRPCChannelManager] Shutting down \(clientsToShutdown.count) gRPC clients")

            Log.info("[GRPCChannelManager] [OK] All gRPC clients shut down")
        }
    }
}
public enum GRPCChannelError: Error, LocalizedError {
    case connectionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let message):
            return "gRPC connection failed: \(message)"
        }
    }
}
