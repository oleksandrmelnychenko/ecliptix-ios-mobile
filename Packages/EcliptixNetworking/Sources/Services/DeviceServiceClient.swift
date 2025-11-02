import EcliptixCore
import Foundation
import GRPCCore
import GRPCProtobuf

@_exported import EcliptixProto

@MainActor
public final class DeviceServiceClient {
    private let channelManager: GRPCChannelManager
    private var grpcClient: Device_DeviceService.Client<HTTP2Transport>?

    nonisolated public init(channelManager: GRPCChannelManager) {
        self.channelManager = channelManager
        Log.info("[DeviceServiceClient] Initialized")
    }
    private func getClient() throws -> Device_DeviceService.Client<HTTP2Transport> {
        if let client = grpcClient {
            return client
        }

        let grpcBaseClient = try channelManager.getClient()
        let client = Device_DeviceService.Client(wrapping: grpcBaseClient)
        grpcClient = client
        return client
    }

    public func establishSecureChannel(
        envelope: Common_SecureEnvelope,
        exchangeType: PubKeyExchangeType? = nil
    ) async throws -> Common_SecureEnvelope {

        Log.info("[DeviceServiceClient] Establishing secure channel")

        let client = try getClient()

        let request = ClientRequest(message: envelope)

        var options = CallOptions.defaults
        options.timeout = .seconds(30)

        let serializer = GRPCProtobuf.ProtobufSerializer<Common_SecureEnvelope>()
        let deserializer = GRPCProtobuf.ProtobufDeserializer<Common_SecureEnvelope>()

        let response = try await client.establishSecureChannel(
            request: request,
            serializer: serializer,
            deserializer: deserializer,
            options: options
        )

        Log.info("[DeviceServiceClient] [OK] Secure channel established")
        return response
    }

    public func registerDevice(
        envelope: Common_SecureEnvelope
    ) async throws -> Common_SecureEnvelope {

        Log.info("[DeviceServiceClient] Registering device")

        let client = try getClient()
        let request = ClientRequest(message: envelope)

        var options = CallOptions.defaults
        options.timeout = .seconds(30)

        let serializer = GRPCProtobuf.ProtobufSerializer<Common_SecureEnvelope>()
        let deserializer = GRPCProtobuf.ProtobufDeserializer<Common_SecureEnvelope>()

        let response = try await client.registerDevice(
            request: request,
            serializer: serializer,
            deserializer: deserializer,
            options: options
        )

        Log.info("[DeviceServiceClient] [OK] Device registered")
        return response
    }

    public func restoreSecureChannel(
        request: Device_RestoreChannelRequest
    ) async throws -> Device_RestoreChannelResponse {

        Log.info("[DeviceServiceClient] Restoring secure channel")

        let client = try getClient()
        let grpcRequest = ClientRequest(message: request)

        var options = CallOptions.defaults
        options.timeout = .seconds(30)

        let serializer = GRPCProtobuf.ProtobufSerializer<Device_RestoreChannelRequest>()
        let deserializer = GRPCProtobuf.ProtobufDeserializer<Device_RestoreChannelResponse>()

        let response = try await client.restoreSecureChannel(
            request: grpcRequest,
            serializer: serializer,
            deserializer: deserializer,
            options: options
        )

        Log.info("[DeviceServiceClient] [OK] Secure channel restored")
        return response
    }

    public func authenticatedEstablishSecureChannel(
        request: Device_AuthenticatedEstablishRequest
    ) async throws -> Common_SecureEnvelope {

        Log.info("[DeviceServiceClient] Establishing authenticated secure channel")

        let client = try getClient()
        let grpcRequest = ClientRequest(message: request)

        var options = CallOptions.defaults
        options.timeout = .seconds(30)

        let serializer = GRPCProtobuf.ProtobufSerializer<Device_AuthenticatedEstablishRequest>()
        let deserializer = GRPCProtobuf.ProtobufDeserializer<Common_SecureEnvelope>()

        let response = try await client.authenticatedEstablishSecureChannel(
            request: grpcRequest,
            serializer: serializer,
            deserializer: deserializer,
            options: options
        )

        Log.info("[DeviceServiceClient] [OK] Authenticated secure channel established")
        return response
    }
}
