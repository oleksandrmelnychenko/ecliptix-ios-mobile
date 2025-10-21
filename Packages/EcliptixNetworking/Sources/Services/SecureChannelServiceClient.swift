import Foundation
import GRPC
import EcliptixCore

// MARK: - Secure Channel Service Client
/// Client for secure channel operations (encrypted communication)
/// Migrated from: Ecliptix.Core/Services/Network/Rpc/SecrecyChannelRpcServices.cs
public final class SecureChannelServiceClient: BaseRPCService {

    // TODO: Replace with generated protobuf client when available
    // private let grpcClient: Ecliptix_Protobuf_SecureChannel_SecureChannelServiceClient

    // MARK: - Restore Secure Channel
    /// Restores a previously established secure channel
    /// Migrated from: RestoreSecureChannelAsync()
    public func restoreSecureChannel(
        envelope: SecureEnvelope
    ) async -> Result<SecureEnvelope, NetworkFailure> {

        return await executeSecureEnvelopeCall(
            serviceType: .restoreSecureChannel,
            envelope: envelope
        ) { request, callOptions in
            // TODO: Call generated protobuf client
            // return try await self.grpcClient.restoreSecureChannel(request, callOptions: callOptions)

            // Placeholder - will be replaced with actual gRPC call
            throw NetworkError.unknown("Protobuf client not yet generated")
        }
    }

    // MARK: - Establish Secure Channel
    /// Establishes a new secure channel with the server
    public func establishSecureChannel(
        envelope: SecureEnvelope
    ) async -> Result<SecureEnvelope, NetworkFailure> {

        return await executeSecureEnvelopeCall(
            serviceType: .restoreSecureChannel, // Reuses same service type
            envelope: envelope
        ) { request, callOptions in
            // TODO: Call generated protobuf client
            throw NetworkError.unknown("Protobuf client not yet generated")
        }
    }

    // MARK: - Send Encrypted Message
    /// Sends an encrypted message through the secure channel
    public func sendEncryptedMessage(
        envelope: SecureEnvelope
    ) async -> Result<SecureEnvelope, NetworkFailure> {

        return await executeSecureEnvelopeCall(
            serviceType: .restoreSecureChannel, // Reuses same service type
            envelope: envelope
        ) { request, callOptions in
            // TODO: Call generated protobuf client
            throw NetworkError.unknown("Protobuf client not yet generated")
        }
    }
}

// MARK: - Service Client Factory
/// Factory for creating service clients
public final class ServiceClientFactory {
    private let channelManager: GRPCChannelManager
    private let retryPolicy: RetryPolicy

    public init(
        channelManager: GRPCChannelManager,
        retryPolicy: RetryPolicy = RetryPolicy()
    ) {
        self.channelManager = channelManager
        self.retryPolicy = retryPolicy
    }

    // MARK: - Create Clients

    public func createMembershipClient() -> MembershipServiceClient {
        return MembershipServiceClient(
            channelManager: channelManager,
            retryPolicy: retryPolicy
        )
    }

    public func createDeviceClient() -> DeviceServiceClient {
        return DeviceServiceClient(
            channelManager: channelManager,
            retryPolicy: retryPolicy
        )
    }

    public func createSecureChannelClient() -> SecureChannelServiceClient {
        return SecureChannelServiceClient(
            channelManager: channelManager,
            retryPolicy: retryPolicy
        )
    }
}
