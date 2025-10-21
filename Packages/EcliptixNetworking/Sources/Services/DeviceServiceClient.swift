import Foundation
import GRPC
import EcliptixCore

// MARK: - Device Service Client
/// Client for device-related RPC calls (registration, management)
/// Migrated from: Ecliptix.Core/Services/Network/Rpc/UnaryRpcServices.cs (device methods)
public final class DeviceServiceClient: BaseRPCService {

    // TODO: Replace with generated protobuf client when available
    // private let grpcClient: Ecliptix_Protobuf_Device_DeviceServiceClient

    // MARK: - Register Device
    /// Registers a new device with the backend
    /// Migrated from: RegisterDeviceAsync()
    public func registerDevice(
        envelope: SecureEnvelope
    ) async -> Result<SecureEnvelope, NetworkFailure> {

        return await executeSecureEnvelopeCall(
            serviceType: .registerDevice,
            envelope: envelope
        ) { request, callOptions in
            // TODO: Call generated protobuf client
            // return try await self.grpcClient.registerDevice(request, callOptions: callOptions)

            // Placeholder - will be replaced with actual gRPC call
            throw NetworkError.unknown("Protobuf client not yet generated")
        }
    }

    // MARK: - Update Device Info
    /// Updates device information
    public func updateDeviceInfo(
        envelope: SecureEnvelope
    ) async -> Result<SecureEnvelope, NetworkFailure> {

        return await executeSecureEnvelopeCall(
            serviceType: .registerDevice, // Reuses same service type
            envelope: envelope
        ) { request, callOptions in
            // TODO: Call generated protobuf client
            throw NetworkError.unknown("Protobuf client not yet generated")
        }
    }

    // MARK: - Get Device Status
    /// Retrieves device status from backend
    public func getDeviceStatus(
        envelope: SecureEnvelope
    ) async -> Result<SecureEnvelope, NetworkFailure> {

        return await executeSecureEnvelopeCall(
            serviceType: .registerDevice, // Reuses same service type
            envelope: envelope
        ) { request, callOptions in
            // TODO: Call generated protobuf client
            throw NetworkError.unknown("Protobuf client not yet generated")
        }
    }
}
