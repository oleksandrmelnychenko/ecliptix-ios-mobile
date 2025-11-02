import EcliptixCore
import EcliptixNetworking
import EcliptixOPAQUE
import EcliptixProto
import EcliptixSecurity
import Foundation
import SwiftProtobuf

@MainActor
public final class OpaqueAuthenticationService {

    private let membershipClient: MembershipServiceClient
    private let deviceClient: DeviceServiceClient
    private var opaqueClient: OpaqueClient?
    private var serverPublicKey: Data?

    public init(
        membershipClient: MembershipServiceClient,
        deviceClient: DeviceServiceClient
    ) {
        self.membershipClient = membershipClient
        self.deviceClient = deviceClient

        Log.info("[OpaqueAuthService] Initialized (server key will be obtained from RegisterDevice)")
    }

    public func registerDevice(
        appInstanceId: Data,
        deviceId: Data,
        deviceType: Device_AppDevice.DeviceType
    ) async -> Result<Device_DeviceRegistrationResponse, ServiceFailure> {

        Log.info("[OpaqueAuthService] Registering device")

        do {

            var device = Device_AppDevice()
            device.appInstanceID = appInstanceId
            device.deviceID = deviceId
            device.deviceType = deviceType

            var envelope = Common_SecureEnvelope()
            envelope.encryptedPayload = try device.serializedData()
            envelope.timestamp = Google_Protobuf_Timestamp(date: Date())

            let responseEnvelope = try await deviceClient.registerDevice(envelope: envelope)

            let response = try Device_DeviceRegistrationResponse(
                serializedBytes: responseEnvelope.encryptedPayload
            )

            if response.status == .newRegistration || response.status == .alreadyExists {

                self.serverPublicKey = response.serverPublicKey

                self.opaqueClient = try OpaqueClient(serverPublicKey: response.serverPublicKey)

                Log.info("[OpaqueAuthService] [OK] Device registered, server public key obtained (\(response.serverPublicKey.count) bytes)")
            } else {
                Log.error("[OpaqueAuthService] Device registration failed: \(response.message)")
            }

            return .success(response)

        } catch let error as OpaqueError {
            Log.error("[OpaqueAuthService] OPAQUE error: \(error)")
            return .failure(.invalidData(error.description))

        } catch {
            Log.error("[OpaqueAuthService] Device registration failed: \(error)")
            return .failure(.networkError(error.localizedDescription))
        }
    }

    public func registrationInit(
        mobileNumber: String,
        password: String,
        membershipIdentifier: Data
    ) async -> Result<Membership_OpaqueRegistrationInitResponse, ServiceFailure> {

        Log.info("[OpaqueAuthService] Starting registration for \(mobileNumber)")

        do {

            guard let serverPubKey = serverPublicKey else {
                return .failure(.invalidData("Server public key not available. Call registerDevice() first."))
            }

            if opaqueClient == nil {
                opaqueClient = try OpaqueClient(serverPublicKey: serverPubKey)
            }

            guard let client = opaqueClient else {
                return .failure(.invalidData("OPAQUE client not initialized"))
            }

            let passwordData = password.data(using: .utf8) ?? Data()
            let registrationRequest = try client.createRegistrationRequest(password: passwordData)

            var request = Membership_OpaqueRegistrationInitRequest()
            request.peerOprf = registrationRequest
            request.membershipIdentifier = membershipIdentifier

            var envelope = Common_SecureEnvelope()
            envelope.encryptedPayload = try request.serializedData()
            envelope.timestamp = Google_Protobuf_Timestamp(date: Date())

            let responseEnvelope = try await membershipClient.opaqueRegistrationInit(envelope: envelope)

            let response = try Membership_OpaqueRegistrationInitResponse(
                serializedBytes: responseEnvelope.encryptedPayload
            )

            if response.result == .succeeded {
                Log.info("[OpaqueAuthService] [OK] Registration init succeeded")
            } else {
                Log.warning("[OpaqueAuthService] Registration init failed: \(response.message)")
            }

            return .success(response)

        } catch let error as OpaqueError {
            Log.error("[OpaqueAuthService] OPAQUE error: \(error)")
            return .failure(.invalidData(error.description))

        } catch {
            Log.error("[OpaqueAuthService] Registration init failed: \(error)")
            return .failure(.networkError(error.localizedDescription))
        }
    }

    public func registrationComplete(
        serverOprfResponse: Data,
        membershipIdentifier: Data
    ) async -> Result<Membership_OpaqueRegistrationCompleteResponse, ServiceFailure> {

        Log.info("[OpaqueAuthService] Completing registration")

        do {
            guard let client = opaqueClient else {
                return .failure(.invalidData("OPAQUE client not initialized"))
            }

            let registrationRecord = try client.finalizeRegistration(serverResponse: serverOprfResponse)

            var request = Membership_OpaqueRegistrationCompleteRequest()
            request.peerRegistrationRecord = registrationRecord
            request.membershipIdentifier = membershipIdentifier

            var envelope = Common_SecureEnvelope()
            envelope.encryptedPayload = try request.serializedData()
            envelope.timestamp = Google_Protobuf_Timestamp(date: Date())

            let responseEnvelope = try await membershipClient.opaqueRegistrationComplete(envelope: envelope)

            let response = try Membership_OpaqueRegistrationCompleteResponse(
                serializedBytes: responseEnvelope.encryptedPayload
            )

            if response.result == .succeeded {
                Log.info("[OpaqueAuthService] [OK] Registration completed successfully")
            } else {
                Log.warning("[OpaqueAuthService] Registration complete failed: \(response.message)")
            }

            return .success(response)

        } catch let error as OpaqueError {
            Log.error("[OpaqueAuthService] OPAQUE error: \(error)")
            return .failure(.invalidData(error.description))

        } catch {
            Log.error("[OpaqueAuthService] Registration complete failed: \(error)")
            return .failure(.networkError(error.localizedDescription))
        }
    }

    public func signInInit(
        mobileNumber: String,
        password: String
    ) async -> Result<Membership_OpaqueSignInInitResponse, ServiceFailure> {

        Log.info("[OpaqueAuthService] Starting sign-in for \(mobileNumber)")

        do {

            guard let serverPubKey = serverPublicKey else {
                return .failure(.invalidData("Server public key not available. Call registerDevice() first."))
            }

            if opaqueClient == nil {
                opaqueClient = try OpaqueClient(serverPublicKey: serverPubKey)
            }

            guard let client = opaqueClient else {
                return .failure(.invalidData("OPAQUE client not initialized"))
            }

            let passwordData = password.data(using: .utf8) ?? Data()
            let ke1 = try client.generateKE1(password: passwordData)

            var request = Membership_OpaqueSignInInitRequest()
            request.mobileNumber = mobileNumber
            request.peerOprf = ke1

            var envelope = Common_SecureEnvelope()
            envelope.encryptedPayload = try request.serializedData()
            envelope.timestamp = Google_Protobuf_Timestamp(date: Date())

            let responseEnvelope = try await membershipClient.opaqueSignInInit(envelope: envelope)

            let response = try Membership_OpaqueSignInInitResponse(
                serializedBytes: responseEnvelope.encryptedPayload
            )

            if response.result == .succeeded {
                Log.info("[OpaqueAuthService] [OK] Sign-in init succeeded")
            } else {
                Log.warning("[OpaqueAuthService] Sign-in init failed: \(response.message)")
            }

            return .success(response)

        } catch let error as OpaqueError {
            Log.error("[OpaqueAuthService] OPAQUE error: \(error)")
            return .failure(.invalidData(error.description))

        } catch {
            Log.error("[OpaqueAuthService] Sign-in init failed: \(error)")
            return .failure(.networkError(error.localizedDescription))
        }
    }

    public func signInFinalize(
        mobileNumber: String,
        ke2Response: Membership_OpaqueSignInInitResponse
    ) async -> Result<Membership_OpaqueSignInFinalizeResponse, ServiceFailure> {

        Log.info("[OpaqueAuthService] Finalizing sign-in for \(mobileNumber)")

        do {
            guard let client = opaqueClient else {
                return .failure(.invalidData("OPAQUE client not initialized"))
            }

            var ke2Data = Data()
            ke2Data.append(ke2Response.serverOprfResponse)
            ke2Data.append(ke2Response.serverEphemeralPublicKey)
            ke2Data.append(ke2Response.registrationRecord)
            ke2Data.append(ke2Response.serverMac)

            let ke3 = try client.generateKE3(ke2: ke2Data)

            let sessionKey = try client.finishAuthentication()

            Log.info("[OpaqueAuthService] Session key derived: \(sessionKey.count) bytes")

            var request = Membership_OpaqueSignInFinalizeRequest()
            request.mobileNumber = mobileNumber
            request.clientEphemeralPublicKey = Data()
            request.clientMac = ke3
            request.serverStateToken = ke2Response.serverStateToken

            var envelope = Common_SecureEnvelope()
            envelope.encryptedPayload = try request.serializedData()
            envelope.timestamp = Google_Protobuf_Timestamp(date: Date())

            let responseEnvelope = try await membershipClient.opaqueSignInComplete(envelope: envelope)

            let response = try Membership_OpaqueSignInFinalizeResponse(
                serializedBytes: responseEnvelope.encryptedPayload
            )

            if response.result == .succeeded {
                Log.info("[OpaqueAuthService] [OK] Sign-in completed successfully")
            } else {
                Log.warning("[OpaqueAuthService] Sign-in finalize failed: \(response.message)")
            }

            return .success(response)

        } catch let error as OpaqueError {
            Log.error("[OpaqueAuthService] OPAQUE error: \(error)")
            return .failure(.invalidData(error.description))

        } catch {
            Log.error("[OpaqueAuthService] Sign-in finalize failed: \(error)")
            return .failure(.networkError(error.localizedDescription))
        }
    }

    public func resetState() {
        guard let serverPubKey = serverPublicKey else {
            Log.warning("[OpaqueAuthService] Cannot reset state - no server public key")
            return
        }

        do {
            opaqueClient = try OpaqueClient(serverPublicKey: serverPubKey)
            Log.debug("[OpaqueAuthService] State reset")
        } catch {
            Log.error("[OpaqueAuthService] Failed to reset state: \(error)")
        }
    }
}
