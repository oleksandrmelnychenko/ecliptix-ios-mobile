import Foundation
import Observation
import EcliptixCore
import EcliptixNetworking
import EcliptixSecurity

// MARK: - Authentication Service
/// Modern service-based architecture for authentication flows
/// Replaces SignInViewModel and RegistrationViewModel with cleaner service pattern
@MainActor
@Observable
public final class AuthenticationService {

    // MARK: - Published State
    public var isLoading: Bool = false
    public var errorMessage: String?
    public var currentStep: AuthenticationStep = .signIn

    // MARK: - Authentication Step
    public enum AuthenticationStep: Equatable {
        case signIn
        case registration
        case otpVerification(mobileNumber: String)
        case secureKeySetup
        case complete(userId: String)
    }

    // MARK: - Dependencies
    private let networkProvider: NetworkProvider
    private let identityKeys: IdentityKeys
    private let connectId: UInt32 = 1 // Default connection ID for auth

    // MARK: - Initialization
    public init(
        networkProvider: NetworkProvider,
        identityKeys: IdentityKeys
    ) {
        self.networkProvider = networkProvider
        self.identityKeys = identityKeys

        // Initialize protocol connection for authentication
        networkProvider.initiateProtocolConnection(connectId: connectId, identityKeys: identityKeys)
    }

    // MARK: - Sign In

    /// Signs in a user with mobile number and secure key
    /// Migrated from: SignInViewModel.signIn()
    public func signIn(mobileNumber: String, secureKey: String) async -> Result<String, Error> {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Validate inputs
        guard validateMobileNumber(mobileNumber) else {
            let error = AuthenticationError.invalidMobileNumber("Please enter a valid mobile number")
            errorMessage = error.localizedDescription
            return .failure(error)
        }

        guard validateSecureKey(secureKey) else {
            let error = AuthenticationError.invalidSecureKey("Secure key must be at least 12 characters")
            errorMessage = error.localizedDescription
            return .failure(error)
        }

        // TODO: Create sign-in request payload
        // This will use OPAQUE protocol once integrated
        let signInRequest = createSignInRequest(mobileNumber: mobileNumber, secureKey: secureKey)

        // Execute sign-in via NetworkProvider
        let result = await networkProvider.executeUnaryRequest(
            connectId: connectId,
            serviceType: .signInInit,
            plainBuffer: signInRequest,
            allowDuplicates: false,
            waitForRecovery: true
        ) { responseData in
            // Process sign-in response
            try await self.processSignInResponse(responseData)
        }

        switch result {
        case .success:
            currentStep = .complete(userId: "user-id-placeholder")
            return .success("user-id-placeholder")

        case .failure(let networkFailure):
            let error = AuthenticationError.networkError(networkFailure.message)
            errorMessage = error.localizedDescription
            return .failure(error)
        }
    }

    // MARK: - Registration

    /// Starts registration flow with mobile number
    public func startRegistration(mobileNumber: String) async -> Result<Void, Error> {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Validate mobile number
        guard validateMobileNumber(mobileNumber) else {
            let error = AuthenticationError.invalidMobileNumber("Please enter a valid mobile number")
            errorMessage = error.localizedDescription
            return .failure(error)
        }

        // Check mobile availability
        let availabilityResult = await checkMobileAvailability(mobileNumber)
        guard case .success(let isAvailable) = availabilityResult else {
            if case .failure(let error) = availabilityResult {
                errorMessage = error.localizedDescription
                return .failure(error)
            }
            return .failure(AuthenticationError.unknown("Failed to check mobile availability"))
        }

        guard isAvailable else {
            let error = AuthenticationError.mobileAlreadyRegistered("This mobile number is already registered")
            errorMessage = error.localizedDescription
            return .failure(error)
        }

        // Send OTP
        let otpResult = await sendOTP(to: mobileNumber)
        guard case .success = otpResult else {
            if case .failure(let error) = otpResult {
                errorMessage = error.localizedDescription
                return .failure(error)
            }
            return .failure(AuthenticationError.unknown("Failed to send OTP"))
        }

        // Move to OTP verification step
        currentStep = .otpVerification(mobileNumber: mobileNumber)
        return .success(())
    }

    /// Verifies OTP code
    public func verifyOTP(code: String, mobileNumber: String) async -> Result<Void, Error> {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Validate OTP format
        guard code.count == 6, code.allSatisfy({ $0.isNumber }) else {
            let error = AuthenticationError.invalidOTP("OTP must be 6 digits")
            errorMessage = error.localizedDescription
            return .failure(error)
        }

        // Create OTP verification request
        let otpRequest = createOTPVerificationRequest(code: code, mobileNumber: mobileNumber)

        // Verify via NetworkProvider
        let result = await networkProvider.executeUnaryRequest(
            connectId: connectId,
            serviceType: .verifyOtp,
            plainBuffer: otpRequest,
            allowDuplicates: false,
            waitForRecovery: true
        ) { responseData in
            try await self.processOTPResponse(responseData)
        }

        switch result {
        case .success:
            currentStep = .secureKeySetup
            return .success(())

        case .failure(let networkFailure):
            let error = AuthenticationError.networkError(networkFailure.message)
            errorMessage = error.localizedDescription
            return .failure(error)
        }
    }

    /// Completes registration with secure key
    public func completeRegistration(secureKey: String, passPhrase: String) async -> Result<String, Error> {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Validate secure key complexity
        guard validateSecureKeyComplexity(secureKey) else {
            let error = AuthenticationError.weakSecureKey(
                "Secure key must be at least 12 characters with uppercase, lowercase, number, and special character"
            )
            errorMessage = error.localizedDescription
            return .failure(error)
        }

        // TODO: Create registration complete request with OPAQUE
        let registrationRequest = createRegistrationCompleteRequest(secureKey: secureKey, passPhrase: passPhrase)

        // Execute registration complete
        let result = await networkProvider.executeUnaryRequest(
            connectId: connectId,
            serviceType: .registrationComplete,
            plainBuffer: registrationRequest,
            allowDuplicates: false,
            waitForRecovery: true
        ) { responseData in
            try await self.processRegistrationCompleteResponse(responseData)
        }

        switch result {
        case .success:
            currentStep = .complete(userId: "user-id-placeholder")
            return .success("user-id-placeholder")

        case .failure(let networkFailure):
            let error = AuthenticationError.networkError(networkFailure.message)
            errorMessage = error.localizedDescription
            return .failure(error)
        }
    }

    // MARK: - Validation

    private func validateMobileNumber(_ mobileNumber: String) -> Bool {
        let digitsOnly = mobileNumber.filter { $0.isNumber }
        return digitsOnly.count >= 10 && digitsOnly.count <= 15
    }

    private func validateSecureKey(_ secureKey: String) -> Bool {
        return secureKey.count >= 12
    }

    private func validateSecureKeyComplexity(_ secureKey: String) -> Bool {
        guard secureKey.count >= 12 else { return false }

        let hasUppercase = secureKey.contains(where: { $0.isUppercase })
        let hasLowercase = secureKey.contains(where: { $0.isLowercase })
        let hasNumber = secureKey.contains(where: { $0.isNumber })
        let hasSpecial = secureKey.contains(where: { !$0.isLetter && !$0.isNumber })

        return hasUppercase && hasLowercase && hasNumber && hasSpecial
    }

    // MARK: - Network Operations

    private func checkMobileAvailability(_ mobileNumber: String) async -> Result<Bool, Error> {
        let request = createMobileAvailabilityRequest(mobileNumber)

        let result = await networkProvider.executeUnaryRequest(
            connectId: connectId,
            serviceType: .checkMobileAvailability,
            plainBuffer: request,
            allowDuplicates: false,
            waitForRecovery: true
        ) { responseData in
            try await self.processMobileAvailabilityResponse(responseData)
        }

        switch result {
        case .success:
            return .success(true) // Placeholder
        case .failure(let error):
            return .failure(AuthenticationError.networkError(error.message))
        }
    }

    private func sendOTP(to mobileNumber: String) async -> Result<Void, Error> {
        let request = createOTPRequest(mobileNumber)

        let result = await networkProvider.executeUnaryRequest(
            connectId: connectId,
            serviceType: .validateMobileNumber,
            plainBuffer: request,
            allowDuplicates: false,
            waitForRecovery: true
        ) { responseData in
            try await self.processOTPSendResponse(responseData)
        }

        switch result {
        case .success:
            return .success(())
        case .failure(let error):
            return .failure(AuthenticationError.networkError(error.message))
        }
    }

    // MARK: - Request Creation (Placeholders for OPAQUE integration)

    private func createSignInRequest(mobileNumber: String, secureKey: String) -> Data {
        // TODO: Implement OPAQUE sign-in request
        // For now, create placeholder JSON
        let request = [
            "mobileNumber": mobileNumber,
            "secureKey": secureKey
        ]
        return (try? JSONEncoder().encode(request)) ?? Data()
    }

    private func createMobileAvailabilityRequest(_ mobileNumber: String) -> Data {
        let request = ["mobileNumber": mobileNumber]
        return (try? JSONEncoder().encode(request)) ?? Data()
    }

    private func createOTPRequest(_ mobileNumber: String) -> Data {
        let request = ["mobileNumber": mobileNumber]
        return (try? JSONEncoder().encode(request)) ?? Data()
    }

    private func createOTPVerificationRequest(code: String, mobileNumber: String) -> Data {
        let request = [
            "code": code,
            "mobileNumber": mobileNumber
        ]
        return (try? JSONEncoder().encode(request)) ?? Data()
    }

    private func createRegistrationCompleteRequest(secureKey: String, passPhrase: String) -> Data {
        // TODO: Implement OPAQUE registration complete request
        let request = [
            "secureKey": secureKey,
            "passPhrase": passPhrase
        ]
        return (try? JSONEncoder().encode(request)) ?? Data()
    }

    // MARK: - Response Processing (Placeholders)

    private func processSignInResponse(_ data: Data) async throws {
        // TODO: Process actual sign-in response
        Log.info("[AuthenticationService] Processing sign-in response: \(data.count) bytes")
    }

    private func processMobileAvailabilityResponse(_ data: Data) async throws {
        // TODO: Parse actual response
        Log.info("[AuthenticationService] Processing mobile availability response: \(data.count) bytes")
    }

    private func processOTPSendResponse(_ data: Data) async throws {
        // TODO: Parse actual response
        Log.info("[AuthenticationService] Processing OTP send response: \(data.count) bytes")
    }

    private func processOTPResponse(_ data: Data) async throws {
        // TODO: Parse actual OTP verification response
        Log.info("[AuthenticationService] Processing OTP verification response: \(data.count) bytes")
    }

    private func processRegistrationCompleteResponse(_ data: Data) async throws {
        // TODO: Parse actual registration complete response
        Log.info("[AuthenticationService] Processing registration complete response: \(data.count) bytes")
    }
}

// MARK: - Authentication Error
public enum AuthenticationError: LocalizedError {
    case invalidMobileNumber(String)
    case invalidSecureKey(String)
    case weakSecureKey(String)
    case invalidOTP(String)
    case mobileAlreadyRegistered(String)
    case networkError(String)
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .invalidMobileNumber(let message),
             .invalidSecureKey(let message),
             .weakSecureKey(let message),
             .invalidOTP(let message),
             .mobileAlreadyRegistered(let message),
             .networkError(let message),
             .unknown(let message):
            return message
        }
    }
}
