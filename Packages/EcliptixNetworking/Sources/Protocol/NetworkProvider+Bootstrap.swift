import EcliptixSecurity
import Foundation
import struct EcliptixCore.ApplicationInstanceSettings
import var EcliptixCore.Log

public typealias AppInstanceSettings = ApplicationInstanceSettings

@MainActor
extension NetworkProvider {

    public func computeUniqueConnectId(
        appInstanceId: UUID,
        deviceId: UUID,
        exchangeType: PubKeyExchangeType
    ) -> UInt32 {

        var hasher = Hasher()
        hasher.combine(appInstanceId)
        hasher.combine(deviceId)
        hasher.combine(exchangeType.rawValue)

        let hashValue = hasher.finalize()

        let connectId = UInt32(truncatingIfNeeded: hashValue)

        Log.info("[NetworkProvider] Computed ConnectId: \(connectId) for AppInstanceId: \(appInstanceId)")

        return connectId
    }

    public func initiateEcliptixProtocol(
        settings: AppInstanceSettings,
        connectId: UInt32
    ) {
        Log.info("[NetworkProvider] Initiating Ecliptix protocol - ConnectId: \(connectId)")

        Task {
            do {
                let deviceServiceClient = DeviceServiceClient(channelManager: channelManager)

                try await connectionManager.createConnection(
                    connectId: connectId,
                    appInstanceId: settings.appInstanceId,
                    deviceId: settings.deviceId,
                    membershipId: nil as UUID?,
                    deviceServiceClient: deviceServiceClient
                )

                Log.info("[NetworkProvider] [OK] Anonymous protocol initialized - ConnectId: \(connectId)")

            } catch {
                Log.error("[NetworkProvider] Failed to initiate protocol: \(error.localizedDescription)")
            }
        }
    }

    public func recreateProtocolWithMasterKey(
        masterKeyHandle: SecureMemoryHandle,
        membershipId: UUID,
        connectId: UInt32,
        appInstanceId: UUID,
        deviceId: UUID
    ) async -> Result<Void, NetworkFailure> {

        Log.info("[NetworkProvider] Recreating protocol with master key - ConnectId: \(connectId)")

        do {

            let masterKeyData = try masterKeyHandle.readData()

            let identityPrivateKey = masterKeyData

            let deviceServiceClient = DeviceServiceClient(channelManager: channelManager)

            try await connectionManager.createConnection(
                connectId: connectId,
                appInstanceId: appInstanceId,
                deviceId: deviceId,
                membershipId: membershipId,
                identityPrivateKey: identityPrivateKey,
                deviceServiceClient: deviceServiceClient
            )

            Log.info("[NetworkProvider] [OK] Authenticated protocol created - ConnectId: \(connectId)")

            return .success(())

        } catch {
            Log.error("[NetworkProvider] Failed to recreate protocol: \(error.localizedDescription)")
            return .failure(NetworkFailure(
                type: .unauthenticated,
                message: "Failed to recreate protocol with master key: \(error.localizedDescription)"
            ))
        }
    }

    public func restoreSession(
        connectId: UInt32,
        stateData: Data,
        membershipId: UUID
    ) async -> Result<Void, NetworkFailure> {

        Log.info("[NetworkProvider] Restoring session - ConnectId: \(connectId)")

        do {
            let deviceServiceClient = DeviceServiceClient(channelManager: channelManager)

            try await connectionManager.restoreConnection(
                connectId: connectId,
                stateData: stateData,
                membershipId: membershipId,
                deviceServiceClient: deviceServiceClient
            )

            Log.info("[NetworkProvider] [OK] Session restored successfully - ConnectId: \(connectId)")

            return .success(())

        } catch {
            Log.error("[NetworkProvider] Failed to restore session: \(error.localizedDescription)")
            return .failure(NetworkFailure(
                type: .sessionExpired,
                message: "Failed to restore session: \(error.localizedDescription)"
            ))
        }
    }

    public func establishSecrecyChannel(connectId: UInt32) async -> Result<Data, NetworkFailure> {

        Log.info("[NetworkProvider] Establishing secrecy channel - ConnectId: \(connectId)")

        let result = await retryStrategy.executeRPCOperation(
            operationName: "EstablishSecrecyChannel",
            connectId: connectId,
            serviceType: NetworkProvider.RPCServiceType.establishSecureChannel,
            maxRetries: 5
        ) { attempt in

            Log.info("[NetworkProvider] Establishing channel attempt \(attempt) - ConnectId: \(connectId)")

            do {
                let deviceServiceClient = DeviceServiceClient(channelManager: self.channelManager)

                let sessionState = try await self.connectionManager.establishSecureChannel(
                    connectId: connectId,
                    deviceServiceClient: deviceServiceClient,
                    exchangeType: .dataCenterEphemeralConnect
                )

                Log.info("[NetworkProvider] [OK] Secrecy channel established - ConnectId: \(connectId)")

                return .success(sessionState)

            } catch {
                Log.error("[NetworkProvider] Channel establishment failed: \(error.localizedDescription)")
                return Result<Data, NetworkFailure>.failure(NetworkFailure(
                    type: .handshakeFailed,
                    message: "Failed to establish secrecy channel: \(error.localizedDescription)"
                ))
            }
        }

        return result
    }

    public func registerDevice(
        connectId: UInt32,
        appInstanceId: UUID,
        deviceId: UUID,
        culture: String
    ) async -> Result<Void, NetworkFailure> {

        Log.info("[NetworkProvider] Registering device - ConnectId: \(connectId)")

        let result = await retryStrategy.executeRPCOperation(
            operationName: "RegisterDevice",
            connectId: connectId,
            serviceType: NetworkProvider.RPCServiceType.registerDevice,
            maxRetries: 3
        ) { attempt in

            Log.info("[NetworkProvider] Device registration attempt \(attempt) - ConnectId: \(connectId)")

            Log.info("[NetworkProvider] [OK] Device registered (placeholder) - ConnectId: \(connectId)")

            return Result<Void, NetworkFailure>.success(())
        }

        return result
    }
}
