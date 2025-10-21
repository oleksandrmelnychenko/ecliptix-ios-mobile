import Foundation
import GRPC
import EcliptixCore

// MARK: - RPC Service Type
/// Types of RPC services
/// Migrated from: Ecliptix.Core/Services/Network/Rpc/RpcServiceType.cs
public enum RPCServiceType: String {
    case registerDevice = "RegisterAppDevice"
    case validateMobileNumber = "ValidateMobileNumber"
    case checkMobileAvailability = "CheckMobileNumberAvailability"
    case registrationInit = "RegistrationInit"
    case registrationComplete = "RegistrationComplete"
    case verifyOtp = "VerifyOtp"
    case signInInit = "SignInInitRequest"
    case signInComplete = "SignInCompleteRequest"
    case logout = "Logout"
    case restoreSecureChannel = "RestoreSecureChannel"
}

// MARK: - RPC Request Context
/// Context for RPC requests
public struct RPCRequestContext {
    public let attemptNumber: Int
    public let serviceType: RPCServiceType
    public let timeout: TimeInterval

    public init(attemptNumber: Int, serviceType: RPCServiceType, timeout: TimeInterval = 30.0) {
        self.attemptNumber = attemptNumber
        self.serviceType = serviceType
        self.timeout = timeout
    }

    public static func createNew(serviceType: RPCServiceType, attempt: Int = 1) -> RPCRequestContext {
        return RPCRequestContext(attemptNumber: attempt, serviceType: serviceType)
    }
}

// MARK: - Base RPC Service
/// Base class for RPC services with common functionality
/// Migrated from: Common RPC service patterns in C#
open class BaseRPCService {

    // MARK: - Properties
    protected let channelManager: GRPCChannelManager
    protected let retryPolicy: RetryPolicy

    // MARK: - Initialization
    public init(
        channelManager: GRPCChannelManager,
        retryPolicy: RetryPolicy = RetryPolicy()
    ) {
        self.channelManager = channelManager
        self.retryPolicy = retryPolicy
    }

    // MARK: - Execute RPC Call
    /// Executes a gRPC call with retry logic
    protected func executeRPCCall<Request, Response>(
        serviceType: RPCServiceType,
        request: Request,
        call: @escaping (Request, CallOptions) async throws -> Response
    ) async -> Result<Response, NetworkFailure> {

        let operationName = serviceType.rawValue

        do {
            let response = try await retryPolicy.execute(operationName: operationName) { attempt in
                // Get channel
                let channel = try self.channelManager.getChannel()

                // Create call options
                let context = RPCRequestContext.createNew(serviceType: serviceType, attempt: attempt)
                let callOptions = self.createCallOptions(for: context)

                // Execute the call
                return try await call(request, callOptions)
            }

            return .success(response)

        } catch let error as NetworkError {
            return .failure(NetworkFailure.from(error))

        } catch {
            Log.error("[\(operationName)] RPC call failed: \(error.localizedDescription)")
            return .failure(NetworkFailure.unknown(
                "RPC call failed: \(error.localizedDescription)",
                error: error
            ))
        }
    }

    // MARK: - Execute Secure Envelope Call
    /// Executes a gRPC call with SecureEnvelope
    protected func executeSecureEnvelopeCall(
        serviceType: RPCServiceType,
        envelope: SecureEnvelope,
        call: @escaping (SecureEnvelope, CallOptions) async throws -> SecureEnvelope
    ) async -> Result<SecureEnvelope, NetworkFailure> {

        return await executeRPCCall(
            serviceType: serviceType,
            request: envelope,
            call: call
        )
    }

    // MARK: - Create Call Options
    private func createCallOptions(for context: RPCRequestContext) -> CallOptions {
        var callOptions = CallOptions()
        callOptions.timeLimit = .timeout(.seconds(Int64(context.timeout)))

        // Add metadata
        callOptions.customMetadata.add(name: "x-attempt-number", value: String(context.attemptNumber))
        callOptions.customMetadata.add(name: "x-service-type", value: context.serviceType.rawValue)

        return callOptions
    }
}

// MARK: - NetworkFailure Extension
extension NetworkFailure {
    static func from(_ networkError: NetworkError) -> NetworkFailure {
        switch networkError {
        case .timeout(let seconds):
            return .timeout("Request timed out after \(seconds) seconds")

        case .retriesExhausted(let operation):
            return .dataCenterNotResponding("All retry attempts exhausted for \(operation)")

        case .connectionFailed(let reason):
            return .networkUnavailable(reason)

        case .invalidResponse:
            return .serverError("Invalid response from server")

        case .unknown(let message):
            return .unknown(message)
        }
    }
}
