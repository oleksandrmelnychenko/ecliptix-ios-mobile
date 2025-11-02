import EcliptixCore
import Foundation
import GRPCCore
import GRPCProtobuf

@_exported import EcliptixProto

@MainActor
public final class MembershipServiceClient {
    private let channelManager: GRPCChannelManager
    private var grpcClient: Membership_MembershipServices.Client<HTTP2Transport>?
    public init(channelManager: GRPCChannelManager) {
        self.channelManager = channelManager
        Log.info("[MembershipServiceClient] Initialized")
    }
    private func getClient() throws -> Membership_MembershipServices.Client<HTTP2Transport> {
        if let client = grpcClient {
            return client
        }

        let grpcBaseClient = try channelManager.getClient()
        let client = Membership_MembershipServices.Client(wrapping: grpcBaseClient)
        grpcClient = client
        return client
    }

    public func opaqueRegistrationInit(
        envelope: Common_SecureEnvelope
    ) async throws -> Common_SecureEnvelope {

        Log.info("[MembershipServiceClient] OPAQUE registration init")

        let client = try getClient()
        let request = ClientRequest(message: envelope)

        var options = CallOptions.defaults
        options.timeout = .seconds(40)

        let serializer = GRPCProtobuf.ProtobufSerializer<Common_SecureEnvelope>()
        let deserializer = GRPCProtobuf.ProtobufDeserializer<Common_SecureEnvelope>()

        let response = try await client.opaqueRegistrationInitRequest(
            request: request,
            serializer: serializer,
            deserializer: deserializer,
            options: options
        )

        Log.info("[MembershipServiceClient] [OK] OPAQUE registration init complete")
        return response
    }

    public func opaqueRegistrationComplete(
        envelope: Common_SecureEnvelope
    ) async throws -> Common_SecureEnvelope {

        Log.info("[MembershipServiceClient] OPAQUE registration complete")

        let client = try getClient()
        let request = ClientRequest(message: envelope)

        var options = CallOptions.defaults
        options.timeout = .seconds(40)

        let serializer = GRPCProtobuf.ProtobufSerializer<Common_SecureEnvelope>()
        let deserializer = GRPCProtobuf.ProtobufDeserializer<Common_SecureEnvelope>()

        let response = try await client.opaqueRegistrationCompleteRequest(
            request: request,
            serializer: serializer,
            deserializer: deserializer,
            options: options
        )

        Log.info("[MembershipServiceClient] [OK] OPAQUE registration completed")
        return response
    }

    public func opaqueRecoverySecretKeyInit(
        envelope: Common_SecureEnvelope
    ) async throws -> Common_SecureEnvelope {

        Log.info("[MembershipServiceClient] Recovery secret key init")

        let client = try getClient()
        let request = ClientRequest(message: envelope)

        var options = CallOptions.defaults
        options.timeout = .seconds(35)

        let serializer = GRPCProtobuf.ProtobufSerializer<Common_SecureEnvelope>()
        let deserializer = GRPCProtobuf.ProtobufDeserializer<Common_SecureEnvelope>()

        let response = try await client.opaqueRecoverySecretKeyInitRequest(
            request: request,
            serializer: serializer,
            deserializer: deserializer,
            options: options
        )

        Log.info("[MembershipServiceClient] [OK] Recovery secret key init complete")
        return response
    }

    public func opaqueRecoverySecretKeyComplete(
        envelope: Common_SecureEnvelope
    ) async throws -> Common_SecureEnvelope {

        Log.info("[MembershipServiceClient] Recovery secret key complete")

        let client = try getClient()
        let request = ClientRequest(message: envelope)

        var options = CallOptions.defaults
        options.timeout = .seconds(35)

        let serializer = GRPCProtobuf.ProtobufSerializer<Common_SecureEnvelope>()
        let deserializer = GRPCProtobuf.ProtobufDeserializer<Common_SecureEnvelope>()

        let response = try await client.opaqueRecoverySecretKeyCompleteRequest(
            request: request,
            serializer: serializer,
            deserializer: deserializer,
            options: options
        )

        Log.info("[MembershipServiceClient] [OK] Recovery secret key setup completed")
        return response
    }

    public func opaqueSignInInit(
        envelope: Common_SecureEnvelope
    ) async throws -> Common_SecureEnvelope {

        Log.info("[MembershipServiceClient] OPAQUE sign-in init")

        let client = try getClient()
        let request = ClientRequest(message: envelope)

        var options = CallOptions.defaults
        options.timeout = .seconds(35)

        let serializer = GRPCProtobuf.ProtobufSerializer<Common_SecureEnvelope>()
        let deserializer = GRPCProtobuf.ProtobufDeserializer<Common_SecureEnvelope>()

        let response = try await client.opaqueSignInInitRequest(
            request: request,
            serializer: serializer,
            deserializer: deserializer,
            options: options
        )

        Log.info("[MembershipServiceClient] [OK] OPAQUE sign-in init complete")
        return response
    }

    public func opaqueSignInComplete(
        envelope: Common_SecureEnvelope
    ) async throws -> Common_SecureEnvelope {

        Log.info("[MembershipServiceClient] OPAQUE sign-in complete")

        let client = try getClient()
        let request = ClientRequest(message: envelope)

        var options = CallOptions.defaults
        options.timeout = .seconds(35)

        let serializer = GRPCProtobuf.ProtobufSerializer<Common_SecureEnvelope>()
        let deserializer = GRPCProtobuf.ProtobufDeserializer<Common_SecureEnvelope>()

        let response = try await client.opaqueSignInCompleteRequest(
            request: request,
            serializer: serializer,
            deserializer: deserializer,
            options: options
        )

        Log.info("[MembershipServiceClient] [OK] OPAQUE sign-in completed")
        return response
    }

    public func logout(
        envelope: Common_SecureEnvelope
    ) async throws -> Common_SecureEnvelope {

        Log.info("[MembershipServiceClient] Logout")

        let client = try getClient()
        let request = ClientRequest(message: envelope)

        var options = CallOptions.defaults
        options.timeout = .seconds(30)

        let serializer = GRPCProtobuf.ProtobufSerializer<Common_SecureEnvelope>()
        let deserializer = GRPCProtobuf.ProtobufDeserializer<Common_SecureEnvelope>()

        let response = try await client.logout(
            request: request,
            serializer: serializer,
            deserializer: deserializer,
            options: options
        )

        Log.info("[MembershipServiceClient] [OK] Logged out")
        return response
    }

    public func anonymousLogout(
        envelope: Common_SecureEnvelope
    ) async throws -> Common_SecureEnvelope {

        Log.info("[MembershipServiceClient] Anonymous logout")

        let client = try getClient()
        let request = ClientRequest(message: envelope)

        var options = CallOptions.defaults
        options.timeout = .seconds(30)

        let serializer = GRPCProtobuf.ProtobufSerializer<Common_SecureEnvelope>()
        let deserializer = GRPCProtobuf.ProtobufDeserializer<Common_SecureEnvelope>()

        let response = try await client.anonymousLogout(
            request: request,
            serializer: serializer,
            deserializer: deserializer,
            options: options
        )

        Log.info("[MembershipServiceClient] [OK] Anonymous logged out")
        return response
    }

    public func getLogoutHistory(
        envelope: Common_SecureEnvelope
    ) async throws -> Common_SecureEnvelope {

        Log.info("[MembershipServiceClient] Get logout history")

        let client = try getClient()
        let request = ClientRequest(message: envelope)

        var options = CallOptions.defaults
        options.timeout = .seconds(30)

        let serializer = GRPCProtobuf.ProtobufSerializer<Common_SecureEnvelope>()
        let deserializer = GRPCProtobuf.ProtobufDeserializer<Common_SecureEnvelope>()

        let response = try await client.getLogoutHistory(
            request: request,
            serializer: serializer,
            deserializer: deserializer,
            options: options
        )

        Log.info("[MembershipServiceClient] [OK] Retrieved logout history")
        return response
    }
}
