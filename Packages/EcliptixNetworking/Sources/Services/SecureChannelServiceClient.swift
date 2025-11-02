import EcliptixCore
import Foundation
import GRPCCore

@MainActor
public final class SecureChannelServiceClient {

    private let channelManager: GRPCChannelManager

    public init(channelManager: GRPCChannelManager) {
        self.channelManager = channelManager
        Log.info("[SecureChannelServiceClient] Initialized (stub)")
    }

    public func restoreSecureChannel(envelope: SecureEnvelope) async -> Result<SecureEnvelope, NetworkFailure> {
        Log.warning("[SecureChannelServiceClient] restoreSecureChannel() not yet implemented")
        return .failure(NetworkFailure(type: .unknown, message: "SecureChannelServiceClient not yet migrated"))
    }

    public func establishSecureChannel(envelope: SecureEnvelope) async -> Result<SecureEnvelope, NetworkFailure> {
        Log.warning("[SecureChannelServiceClient] establishSecureChannel() not yet implemented")
        return .failure(NetworkFailure(type: .unknown, message: "SecureChannelServiceClient not yet migrated"))
    }

    public func sendEncryptedMessage(envelope: SecureEnvelope) async -> Result<SecureEnvelope, NetworkFailure> {
        Log.warning("[SecureChannelServiceClient] sendEncryptedMessage() not yet implemented")
        return .failure(NetworkFailure(type: .unknown, message: "SecureChannelServiceClient not yet migrated"))
    }
}

@MainActor
public final class ServiceClientFactory {
    private let channelManager: GRPCChannelManager

    public init(channelManager: GRPCChannelManager) {
        self.channelManager = channelManager
    }

    public func createMembershipClient() -> MembershipServiceClient {
        return MembershipServiceClient(channelManager: channelManager)
    }

    public func createDeviceClient() -> DeviceServiceClient {
        return DeviceServiceClient(channelManager: channelManager)
    }

    public func createSecureChannelClient() -> SecureChannelServiceClient {
        return SecureChannelServiceClient(channelManager: channelManager)
    }
}
