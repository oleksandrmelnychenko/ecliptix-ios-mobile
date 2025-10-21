import Foundation
import GRPC
import NIOCore
import NIOPosix
import NIOSSL
import EcliptixCore

// MARK: - GRPC Channel Configuration
/// Configuration for gRPC channels
public struct GRPCChannelConfiguration {
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

// MARK: - GRPC Channel Manager
/// Manages gRPC channel lifecycle
/// Simplified migration from: C# gRPC channel management
public final class GRPCChannelManager {

    // MARK: - Properties
    private let configuration: GRPCChannelConfiguration
    private var channel: GRPCChannel?
    private let eventLoopGroup: MultiThreadedEventLoopGroup
    private var isDisposed = false
    private let lock = NSLock()

    // MARK: - Initialization
    public init(configuration: GRPCChannelConfiguration = .default) {
        self.configuration = configuration
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        Log.info("GRPCChannelManager initialized for \(configuration.host):\(configuration.port)")
    }

    deinit {
        dispose()
    }

    // MARK: - Get Channel
    /// Gets or creates a gRPC channel
    public func getChannel() throws -> GRPCChannel {
        lock.lock()
        defer { lock.unlock() }

        guard !isDisposed else {
            throw NetworkError.connectionFailed("Channel manager disposed")
        }

        if let existingChannel = channel, !isChannelShutdown(existingChannel) {
            return existingChannel
        }

        // Create new channel
        let newChannel = try createChannel()
        channel = newChannel
        return newChannel
    }

    // MARK: - Create Channel
    private func createChannel() throws -> GRPCChannel {
        let target = ConnectionTarget.host(configuration.host, port: configuration.port)

        var builder = ClientConnection.usingPlatformAppropriateTLS(for: eventLoopGroup)
            .withConnectionBackoff(initial: .seconds(1), multiplier: 2.0, maximum: .seconds(30))
            .withConnectionTimeout(minimum: .seconds(Int64(configuration.connectionTimeout)))
            .withKeepalive(
                ClientConnectionKeepalive(
                    interval: .seconds(Int64(configuration.keepaliveInterval)),
                    timeout: .seconds(Int64(configuration.keepaliveTimeout))
                )
            )

        // Configure TLS
        if configuration.useTLS {
            builder = builder.withTLS(certificateVerification: .fullVerification)
        } else {
            builder = builder.withTLS(certificateVerification: .none)
        }

        let connection = builder.connect(host: configuration.host, port: configuration.port)

        Log.info("Created gRPC channel to \(configuration.host):\(configuration.port)")
        return connection
    }

    // MARK: - Check Channel Status
    private func isChannelShutdown(_ channel: GRPCChannel) -> Bool {
        // In grpc-swift, we check the connectivity state
        // If it's shutdown or transitioning to shutdown, return true
        return false // Simplified - in practice, check channel.connectivity.state
    }

    // MARK: - Shutdown Channel
    /// Gracefully shuts down the channel
    public func shutdown() async {
        lock.lock()
        let channelToShutdown = channel
        channel = nil
        lock.unlock()

        if let channelToShutdown = channelToShutdown {
            do {
                try await channelToShutdown.close().get()
                Log.info("gRPC channel shut down gracefully")
            } catch {
                Log.warning("Error shutting down gRPC channel: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Dispose
    public func dispose() {
        lock.lock()
        defer { lock.unlock() }

        guard !isDisposed else { return }
        isDisposed = true

        Task {
            await shutdown()

            do {
                try await eventLoopGroup.shutdownGracefully()
                Log.info("Event loop group shut down")
            } catch {
                Log.error("Error shutting down event loop group: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Call Options Factory
/// Creates gRPC call options
public struct GRPCCallOptionsFactory {

    /// Creates call options with timeout
    public static func createCallOptions(timeout: TimeInterval) -> CallOptions {
        var callOptions = CallOptions()
        callOptions.timeLimit = .timeout(.seconds(Int64(timeout)))
        return callOptions
    }

    /// Creates call options with custom headers
    public static func createCallOptions(
        timeout: TimeInterval,
        customHeaders: [String: String]
    ) -> CallOptions {
        var callOptions = CallOptions()
        callOptions.timeLimit = .timeout(.seconds(Int64(timeout)))

        // Add custom headers
        for (key, value) in customHeaders {
            callOptions.customMetadata.add(name: key, value: value)
        }

        return callOptions
    }
}
