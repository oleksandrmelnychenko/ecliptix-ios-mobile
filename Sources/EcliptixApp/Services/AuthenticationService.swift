import Combine
import EcliptixAuthentication
import EcliptixCore
import EcliptixNetworking
import EcliptixProto
import EcliptixSecurity
import Foundation
import Observation
import SwiftProtobuf

@MainActor
@Observable
public final class AuthenticationService {
    public var isLoading: Bool = false
    public var errorMessage: String?
    public var currentStep: AuthenticationStep = .signIn
    public var canExecuteAuthOperations: Bool = true

    public let mobileNumberValidation: ValidationState
    public let secureKeyValidation: ValidationState
    public let otpValidation: ValidationState
    public let passphraseValidation: ValidationState

    public enum AuthenticationStep: Equatable {
        case signIn
        case registration
        case otpVerification(mobileNumber: String)
        case secureKeySetup
        case complete(userId: String)
    }

    private let networkProvider: NetworkProvider
    private let identityKeys: IdentityKeys
    private let connectivityService: ConnectivityService
    private let localization: LocalizationService
    private let opaqueAuthService: OpaqueAuthenticationService
    private let connectId: UInt32 = 1

    private let onIdentityKeysGenerated: (() async -> Void)?

    public private(set) var signInCommand: DefaultAsyncCommand<Void, String>
    public private(set) var startRegistrationCommand: DefaultAsyncCommand<Void, Void>
    public private(set) var verifyOTPCommand: DefaultAsyncCommand<Void, Void>
    public private(set) var completeRegistrationCommand: DefaultAsyncCommand<Void, String>

    private var cancellables = Set<AnyCancellable>()

    public init(
        networkProvider: NetworkProvider,
        identityKeys: IdentityKeys,
        connectivityService: ConnectivityService,
        localization: LocalizationService,
        opaqueAuthService: OpaqueAuthenticationService,
        onIdentityKeysGenerated: (() async -> Void)? = nil
    ) {
        self.networkProvider = networkProvider
        self.identityKeys = identityKeys
        self.connectivityService = connectivityService
        self.localization = localization
        self.opaqueAuthService = opaqueAuthService
        self.onIdentityKeysGenerated = onIdentityKeysGenerated

        self.mobileNumberValidation = ValidationState(
            validator: MobileNumberValidator(
                localization: localization,
                allowInternational: true
            )
        )

        self.secureKeyValidation = ValidationState(
            validator: SecureKeyValidator(
                localization: localization,
                minLength: 12,
                maxLength: 64
            )
        )

        self.otpValidation = ValidationState(
            validator: OTPValidator(
                localization: localization,
                length: 6
            )
        )

        self.passphraseValidation = ValidationState(
            validator: PassphraseValidator(
                localization: localization,
                minWords: 12
            )
        )

        self.signInCommand = DefaultAsyncCommand.createAction { "" }
        self.startRegistrationCommand = DefaultAsyncCommand.createAction { }
        self.verifyOTPCommand = DefaultAsyncCommand.createAction { }
        self.completeRegistrationCommand = DefaultAsyncCommand.createAction { "" }

        setupCommands()
        setupBindings()
    }

    private func setupCommands() {
        self.signInCommand = DefaultAsyncCommand.createAction { [weak self] in
            guard let self = self else { return "" }
            let result = await self.performSignIn()
            switch result {
            case .success(let userId):
                return userId
            case .failure(let error):
                self.errorMessage = error.localizedDescription
                throw error
            }
        }

        self.startRegistrationCommand = DefaultAsyncCommand.createAction { [weak self] in
            guard let self = self else { return }
            let result = await self.performStartRegistration()
            switch result {
            case .success:
                return
            case .failure(let error):
                self.errorMessage = error.localizedDescription
                throw error
            }
        }

        self.verifyOTPCommand = DefaultAsyncCommand.createAction { [weak self] in
            guard let self = self else { return }
            let result = await self.performVerifyOTP()
            switch result {
            case .success:
                return
            case .failure(let error):
                self.errorMessage = error.localizedDescription
                throw error
            }
        }

        self.completeRegistrationCommand = DefaultAsyncCommand.createAction { [weak self] in
            guard let self = self else { return "" }
            let result = await self.performCompleteRegistration()
            switch result {
            case .success(let userId):
                return userId
            case .failure(let error):
                self.errorMessage = error.localizedDescription
                throw error
            }
        }
    }

    private func setupBindings() {
        connectivityService.offlinePublisher
            .map { !$0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] canExecute in
                self?.canExecuteAuthOperations = canExecute
                self?.updateCommandStates()
            }
            .store(in: &cancellables)

        localization.languageChanged
            .sink { [weak self] _ in
                self?.revalidateAll()
            }
            .store(in: &cancellables)

        connectivityService.connectivityRestoredPublisher
            .sink { [weak self] _ in
                Log.info("[AuthenticationService] Connectivity restored")
                self?.errorMessage = nil
            }
            .store(in: &cancellables)
    }

    private func updateCommandStates() {
        let canExecute = canExecuteAuthOperations
        signInCommand.updateCanExecute(canExecute)
        startRegistrationCommand.updateCanExecute(canExecute)
        verifyOTPCommand.updateCanExecute(canExecute)
        completeRegistrationCommand.updateCanExecute(canExecute)
    }

    private func revalidateAll() {
        mobileNumberValidation.validate()
        secureKeyValidation.validate()
        otpValidation.validate()
        passphraseValidation.validate()
    }

    public func signIn() async {
        await signInCommand.execute()
    }

    public func startRegistration() async {
        await startRegistrationCommand.execute()
    }

    public func verifyOTP() async {
        await verifyOTPCommand.execute()
    }

    public func completeRegistration() async {
        await completeRegistrationCommand.execute()
    }

    private func performSignIn() async -> Result<String, Error> {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        mobileNumberValidation.markAsTouched()
        secureKeyValidation.markAsTouched()

        guard mobileNumberValidation.isValid else {
            let error = AuthenticationError.invalidMobileNumber(
                mobileNumberValidation.errorMessage ?? localization[LocalizationKeys.Error.validation]
            )
            errorMessage = error.localizedDescription
            Log.warning("[AuthenticationService] Mobile number validation failed")
            return .failure(error)
        }

        guard secureKeyValidation.isValid else {
            let error = AuthenticationError.invalidSecureKey(
                secureKeyValidation.errorMessage ?? localization[LocalizationKeys.Error.validation]
            )
            errorMessage = error.localizedDescription
            Log.warning("[AuthenticationService] Secure key validation failed")
            return .failure(error)
        }

        Log.info("[AuthenticationService] Starting sign-in flow using OPAQUE protocol")

        let signInInitResult = await opaqueAuthService.signInInit(
            mobileNumber: mobileNumberValidation.value,
            password: secureKeyValidation.value
        )

        switch signInInitResult {
        case .success(let initResponse):
            guard initResponse.result == .succeeded else {
                let error = AuthenticationError.opaqueError("Sign-in init failed: \(initResponse.message)")
                errorMessage = error.localizedDescription
                Log.error("[AuthenticationService] OPAQUE sign-in init failed: \(initResponse.message)")
                return .failure(error)
            }

            Log.info("[AuthenticationService] OPAQUE sign-in init successful (received KE2)")

            let signInFinalizeResult = await opaqueAuthService.signInFinalize(
                mobileNumber: mobileNumberValidation.value,
                ke2Response: initResponse
            )

            switch signInFinalizeResult {
            case .success(let finalizeResponse):
                guard finalizeResponse.result == .succeeded else {
                    let error = AuthenticationError.opaqueError("Sign-in finalize failed: \(finalizeResponse.message)")
                    errorMessage = error.localizedDescription
                    Log.error("[AuthenticationService] OPAQUE sign-in finalize failed: \(finalizeResponse.message)")
                    return .failure(error)
                }

                let userId = String(data: finalizeResponse.membershipIdentifier, encoding: .utf8) ?? UUID().uuidString

                guard let userUUID = UUID(uuidString: userId) else {
                    let error = AuthenticationError.invalidUserId("Invalid user ID format")
                    errorMessage = error.localizedDescription
                    Log.error("[AuthenticationService] Invalid user ID format: \(userId)")
                    return .failure(error)
                }

                let hasIdentity = await identityKeys.hasStoredIdentity(membershipId: userUUID)
                if !hasIdentity {
                    Log.warning("[AuthenticationService] No identity keys found for user, may need recovery")
                } else {
                    Log.info("[AuthenticationService] Identity keys verified for user: \(userId)")
                }

                await onIdentityKeysGenerated?()

                currentStep = .complete(userId: userId)
                Log.info("[AuthenticationService] Sign-in completed successfully with OPAQUE protocol")
                return .success(userId)

            case .failure(let serviceFailure):
                let errorMsg = localization[LocalizationKeys.Error.Network.operationFailed]
                let error = AuthenticationError.networkError("\(errorMsg): \(serviceFailure.message)")
                errorMessage = error.localizedDescription
                Log.error("[AuthenticationService] OPAQUE sign-in finalize failed: \(serviceFailure.message)")
                return .failure(error)
            }

        case .failure(let serviceFailure):
            let errorMsg = localization[LocalizationKeys.Error.Network.operationFailed]
            let error = AuthenticationError.networkError("\(errorMsg): \(serviceFailure.message)")
            errorMessage = error.localizedDescription
            Log.error("[AuthenticationService] OPAQUE sign-in init failed: \(serviceFailure.message)")
            return .failure(error)
        }
    }

    private func performStartRegistration() async -> Result<Void, Error> {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        mobileNumberValidation.markAsTouched()

        guard mobileNumberValidation.isValid else {
            let error = AuthenticationError.invalidMobileNumber(
                mobileNumberValidation.errorMessage ?? localization[LocalizationKeys.Error.validation]
            )
            errorMessage = error.localizedDescription
            Log.warning("[AuthenticationService] Mobile number validation failed")
            return .failure(error)
        }

        Log.info("[AuthenticationService] Starting registration flow")

        let availabilityResult = await checkMobileAvailability(mobileNumberValidation.value)
        guard case .success(let isAvailable) = availabilityResult else {
            if case .failure(let error) = availabilityResult {
                errorMessage = error.localizedDescription
                Log.error("[AuthenticationService] Mobile availability check failed")
                return .failure(error)
            }
            let unknownError = AuthenticationError.unknown(
                localization[LocalizationKeys.Error.unknown]
            )
            errorMessage = unknownError.localizedDescription
            return .failure(unknownError)
        }

        guard isAvailable else {
            let error = AuthenticationError.mobileAlreadyRegistered(
                localization[LocalizationKeys.Authentication.Registration.mobileAlreadyRegistered]
            )
            errorMessage = error.localizedDescription
            Log.warning("[AuthenticationService] Mobile number already registered")
            return .failure(error)
        }

        let otpResult = await sendOTP(to: mobileNumberValidation.value)
        guard case .success = otpResult else {
            if case .failure(let error) = otpResult {
                errorMessage = error.localizedDescription
                Log.error("[AuthenticationService] Failed to send OTP")
                return .failure(error)
            }
            let unknownError = AuthenticationError.unknown(
                localization[LocalizationKeys.Error.unknown]
            )
            errorMessage = unknownError.localizedDescription
            return .failure(unknownError)
        }

        Log.info("[AuthenticationService] OTP sent, moving to verification step")
        currentStep = .otpVerification(mobileNumber: mobileNumberValidation.value)
        return .success(())
    }

    private func performVerifyOTP() async -> Result<Void, Error> {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard case .otpVerification(let mobileNumber) = currentStep else {
            let error = AuthenticationError.unknown(
                localization[LocalizationKeys.Error.unknown]
            )
            errorMessage = error.localizedDescription
            Log.error("[AuthenticationService] Invalid state for OTP verification")
            return .failure(error)
        }

        otpValidation.markAsTouched()

        guard otpValidation.isValid else {
            let error = AuthenticationError.invalidOTP(
                otpValidation.errorMessage ?? localization[LocalizationKeys.Error.validation]
            )
            errorMessage = error.localizedDescription
            Log.warning("[AuthenticationService] OTP validation failed")
            return .failure(error)
        }

        Log.info("[AuthenticationService] Verifying OTP")

        let otpRequest: Data
        do {
            otpRequest = try createOTPVerificationRequest(
                code: otpValidation.value,
                mobileNumber: mobileNumber
            )
        } catch {
            errorMessage = error.localizedDescription
            return .failure(error)
        }

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
            Log.info("[AuthenticationService] OTP verified, moving to secure key setup")
            currentStep = .secureKeySetup
            return .success(())

        case .failure(let networkFailure):
            let errorMsg = localization[LocalizationKeys.Error.Network.operationFailed]
            let error = AuthenticationError.networkError("\(errorMsg): \(networkFailure.message)")
            errorMessage = error.localizedDescription
            Log.error("[AuthenticationService] OTP verification failed: \(networkFailure.message)")
            return .failure(error)
        }
    }

    private func performCompleteRegistration() async -> Result<String, Error> {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        secureKeyValidation.markAsTouched()
        passphraseValidation.markAsTouched()

        guard secureKeyValidation.isValid else {
            let error = AuthenticationError.weakSecureKey(
                secureKeyValidation.errorMessage ?? localization[LocalizationKeys.Error.validation]
            )
            errorMessage = error.localizedDescription
            Log.warning("[AuthenticationService] Secure key validation failed")
            return .failure(error)
        }

        guard passphraseValidation.isValid else {
            let error = AuthenticationError.invalidPassphrase(
                passphraseValidation.errorMessage ?? localization[LocalizationKeys.Error.validation]
            )
            errorMessage = error.localizedDescription
            Log.warning("[AuthenticationService] Passphrase validation failed")
            return .failure(error)
        }

        Log.info("[AuthenticationService] Completing registration")

        let registrationRequest: Data
        do {
            registrationRequest = try await createRegistrationCompleteRequest(
                secureKey: secureKeyValidation.value,
                passPhrase: passphraseValidation.value
            )
        } catch {
            errorMessage = error.localizedDescription
            Log.error("[AuthenticationService] Failed to create registration request: \(error.localizedDescription)")
            return .failure(error)
        }

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
            Log.info("[AuthenticationService] Registration completed successfully")
            currentStep = .complete(userId: "user-id-placeholder")
            return .success("user-id-placeholder")

        case .failure(let networkFailure):
            let errorMsg = localization[LocalizationKeys.Error.Network.operationFailed]
            let error = AuthenticationError.networkError("\(errorMsg): \(networkFailure.message)")
            errorMessage = error.localizedDescription
            Log.error("[AuthenticationService] Registration completion failed: \(networkFailure.message)")
            return .failure(error)
        }
    }

    public func updateMobileNumber(_ value: String) {
        mobileNumberValidation.updateValue(value)
    }

    public func updateSecureKey(_ value: String) {
        secureKeyValidation.updateValue(value)
    }

    public func updateOTP(_ value: String) {
        otpValidation.updateValue(value)
    }

    public func updatePassphrase(_ value: String) {
        passphraseValidation.updateValue(value)
    }

    public func reset() {
        mobileNumberValidation.reset()
        secureKeyValidation.reset()
        otpValidation.reset()
        passphraseValidation.reset()
        errorMessage = nil
        currentStep = .signIn
        Log.debug("[AuthenticationService] Reset authentication state")
    }

    private func checkMobileAvailability(_ mobileNumber: String) async -> Result<Bool, Error> {
        Log.info("[AuthenticationService] Checking mobile availability: \(mobileNumber)")

        let request: Data
        do {
            request = try createMobileAvailabilityRequest(mobileNumber)
        } catch {
            return .failure(error)
        }

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
            Log.info("[AuthenticationService] Mobile is available")
            return .success(true)
        case .failure(let networkFailure):
            let errorMsg = localization[LocalizationKeys.Error.Network.operationFailed]
            Log.error("[AuthenticationService] Mobile availability check failed: \(networkFailure.message)")
            return .failure(AuthenticationError.networkError("\(errorMsg): \(networkFailure.message)"))
        }
    }

    private func sendOTP(to mobileNumber: String) async -> Result<Void, Error> {
        Log.info("[AuthenticationService] Sending OTP to: \(mobileNumber)")

        let request: Data
        do {
            request = try createOTPRequest(mobileNumber)
        } catch {
            return .failure(error)
        }

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
            Log.info("[AuthenticationService] OTP sent successfully")
            return .success(())
        case .failure(let networkFailure):
            let errorMsg = localization[LocalizationKeys.Error.Network.operationFailed]
            Log.error("[AuthenticationService] OTP send failed: \(networkFailure.message)")
            return .failure(AuthenticationError.networkError("\(errorMsg): \(networkFailure.message)"))
        }
    }

    private func createSignInRequest(mobileNumber: String, secureKey: String) async throws -> Data {
        let signInResult = await opaqueAuthService.signInInit(
            mobileNumber: mobileNumber,
            password: secureKey
        )

        switch signInResult {
        case .success(let response):
            var request = Ecliptix_Proto_Membership_OpaqueSignInInitRequest()
            request.mobileNumber = mobileNumber
            request.peerOprf = response.serverOprfResponse
            return try request.serializedData()

        case .failure(let serviceFailure):
            throw AuthenticationError.networkError("OPAQUE sign-in init failed: \(serviceFailure.message)")
        }
    }

    private func createMobileAvailabilityRequest(_ mobileNumber: String) throws -> Data {
        let mobileNumberId = mobileNumber.data(using: .utf8) ?? Data()

        var request = Ecliptix_Proto_Membership_CheckMobileNumberAvailabilityRequest()
        request.mobileNumberIdentifier = mobileNumberId

        return try request.serializedData()
    }

    private func createOTPRequest(_ mobileNumber: String) throws -> Data {
        let mobileNumberId = mobileNumber.data(using: .utf8) ?? Data()
        let deviceId = UUID().uuidString.data(using: .utf8) ?? Data()

        var request = Ecliptix_Proto_Membership_InitiateVerificationRequest()
        request.mobileNumberIdentifier = mobileNumberId
        request.appDeviceIdentifier = deviceId
        request.purpose = .registration
        request.type = .sendOtp

        return try request.serializedData()
    }

    private func createOTPVerificationRequest(code: String, mobileNumber: String) throws -> Data {
        let deviceId = UUID().uuidString.data(using: .utf8) ?? Data()

        var request = Ecliptix_Proto_Membership_VerifyCodeRequest()
        request.appDeviceIdentifier = deviceId
        request.code = code
        request.purpose = .registration
        request.streamConnectID = connectId

        return try request.serializedData()
    }

    private func createRegistrationCompleteRequest(secureKey: String, passPhrase: String) async throws -> Data {
        throw AuthenticationError.opaqueError("Use performCompleteRegistration with OPAQUE flow instead")
    }

    private func processSignInResponse(_ data: Data) async throws {

        Log.info("[AuthenticationService] Processing sign-in response: \(data.count) bytes")
    }

    private func processMobileAvailabilityResponse(_ data: Data) async throws {
        let response = try Ecliptix_Proto_Membership_CheckMobileNumberAvailabilityResponse(serializedData: data)

        Log.info("[AuthenticationService] Mobile availability status: \(response.status)")

        if response.status.lowercased() != "available" {
            throw AuthenticationError.mobileNumberTaken("Mobile number is not available")
        }
    }

    private func processOTPSendResponse(_ data: Data) async throws {
        let response = try Ecliptix_Proto_Membership_InitiateVerificationResponse(serializedData: data)

        Log.info("[AuthenticationService] OTP send result: \(response.result), message: \(response.message)")

        if response.result != .succeeded {
            throw AuthenticationError.otpSendFailed("Failed to send OTP: \(response.message)")
        }

        if !response.sessionIdentifier.isEmpty {
            Log.debug("[AuthenticationService] OTP session ID: \(response.sessionIdentifier.base64EncodedString())")
        }
    }

    private func processOTPResponse(_ data: Data) async throws {
        let response = try Ecliptix_Proto_Membership_VerifyCodeResponse(serializedData: data)

        Log.info("[AuthenticationService] OTP verification result: \(response.result), message: \(response.message ?? "no message")")

        if response.result != .succeeded {
            throw AuthenticationError.invalidOTP("OTP verification failed: \(response.message ?? "Invalid code")")
        }

        if response.hasMembership {
            Log.debug("[AuthenticationService] Membership received from OTP verification")
        }
    }

    private func processRegistrationCompleteResponse(_ data: Data) async throws {
        let response = try Ecliptix_Proto_Membership_OpaqueRegistrationCompleteResponse(serializedData: data)

        Log.info("[AuthenticationService] Registration complete result: \(response.result), message: \(response.message ?? "no message")")

        if response.result != .succeeded {
            throw AuthenticationError.registrationFailed("Registration failed: \(response.message ?? "Unknown error")")
        }

        if response.hasSessionKey {
            Log.debug("[AuthenticationService] Session key received: \(response.sessionKey.count) bytes")
        }

        if !response.availableAccounts.isEmpty {
            Log.info("[AuthenticationService] Available accounts: \(response.availableAccounts.count)")
        }
    }
}

public enum AuthenticationError: LocalizedError {
    case invalidMobileNumber(String)
    case invalidSecureKey(String)
    case weakSecureKey(String)
    case invalidOTP(String)
    case invalidPassphrase(String)
    case mobileAlreadyRegistered(String)
    case mobileNumberTaken(String)
    case otpSendFailed(String)
    case registrationFailed(String)
    case invalidUserId(String)
    case networkError(String)
    case opaqueError(String)
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .invalidMobileNumber(let message),
             .invalidSecureKey(let message),
             .weakSecureKey(let message),
             .invalidOTP(let message),
             .invalidPassphrase(let message),
             .mobileAlreadyRegistered(let message),
             .mobileNumberTaken(let message),
             .otpSendFailed(let message),
             .registrationFailed(let message),
             .invalidUserId(let message),
             .networkError(let message),
             .opaqueError(let message),
             .unknown(let message):
            return message
        }
    }
}

public extension AuthenticationService {

    var mobileNumber: String {
        get { mobileNumberValidation.value }
        set { mobileNumberValidation.updateValue(newValue) }
    }

    var secureKey: String {
        get { secureKeyValidation.value }
        set { secureKeyValidation.updateValue(newValue) }
    }

    var otp: String {
        get { otpValidation.value }
        set { otpValidation.updateValue(newValue) }
    }

    var passphrase: String {
        get { passphraseValidation.value }
        set { passphraseValidation.updateValue(newValue) }
    }

    var canSignIn: Bool {
        mobileNumberValidation.isValid && secureKeyValidation.isValid && canExecuteAuthOperations
    }

    var canStartRegistration: Bool {
        mobileNumberValidation.isValid && canExecuteAuthOperations
    }

    var canVerifyOTP: Bool {
        otpValidation.isValid && canExecuteAuthOperations
    }

    var canCompleteRegistration: Bool {
        secureKeyValidation.isValid && passphraseValidation.isValid && canExecuteAuthOperations
    }
}
