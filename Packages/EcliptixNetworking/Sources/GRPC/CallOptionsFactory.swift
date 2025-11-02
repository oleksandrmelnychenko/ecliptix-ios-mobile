import EcliptixCore
import Foundation
import GRPCCore

public struct CallOptionsFactory: @unchecked Sendable {

    private let defaultTimeout: Duration
    private let serviceTimeouts: [NetworkProvider.RPCServiceType: Duration]

    public init(
        defaultTimeout: Duration = .seconds(30),
        serviceTimeouts: [NetworkProvider.RPCServiceType: Duration] = [:]
    ) {
        self.defaultTimeout = defaultTimeout
        self.serviceTimeouts = serviceTimeouts
    }

    public func createOptions(
        for serviceType: NetworkProvider.RPCServiceType,
        connectId: UInt32,
        correlationId: String? = nil,
        attemptNumber: Int = 1,
        idempotencyKey: String? = nil,
        additionalMetadata: [String: String] = [:]
    ) -> CallOptions {

        var options = CallOptions.defaults
        options.timeout = getTimeout(for: serviceType)

        Log.debug("[CallOptionsFactory] Created options for \(serviceType) - Timeout: \(options.timeout ?? .seconds(30))")

        return options
    }

    public func createSecureChannelOptions(
        exchangeType: PubKeyExchangeType,
        connectId: UInt32,
        correlationId: String? = nil
    ) -> CallOptions {

        let options = createOptions(
            for: .establishSecureChannel,
            connectId: connectId,
            correlationId: correlationId
        )

        return options
    }

    public func createAuthenticatedOptions(
        for serviceType: NetworkProvider.RPCServiceType,
        connectId: UInt32,
        sessionToken: String,
        correlationId: String? = nil
    ) -> CallOptions {

        let options = createOptions(
            for: serviceType,
            connectId: connectId,
            correlationId: correlationId
        )

        return options
    }

    private func getTimeout(for serviceType: NetworkProvider.RPCServiceType) -> Duration {
        if let timeout = serviceTimeouts[serviceType] {
            return timeout
        }

        switch serviceType {
        case .establishSecureChannel, .restoreSecureChannel:

            return .seconds(45)

        case .registerDevice, .registrationInit, .registrationComplete:

            return .seconds(40)

        case .signInInit, .signInComplete:

            return .seconds(35)

        case .validateMobileNumber, .checkMobileAvailability:

            return .seconds(15)

        case .verifyOtp:

            return .seconds(20)

        case .sendMessage:

            return .seconds(30)

        default:
            return defaultTimeout
        }
    }

    public static func generateCorrelationId() -> String {
        return UUID().uuidString
    }

    public static func generateIdempotencyKey() -> String {
        return UUID().uuidString
    }
}

extension CallOptionsFactory {

    public static let `default` = CallOptionsFactory()
}

public enum MetadataKeys {
    public static let correlationId = "correlation-id"
    public static let connectId = "connect-id"
    public static let attemptNumber = "attempt-number"
    public static let idempotencyKey = "idempotency-key"
    public static let clientVersion = "client-version"
    public static let exchangeType = "exchange-type"
    public static let authorization = "authorization"
    public static let locale = "locale"
    public static let deviceId = "device-id"
    public static let userId = "user-id"
}
