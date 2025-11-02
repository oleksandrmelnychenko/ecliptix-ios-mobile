import Combine
import EcliptixAuthentication
import EcliptixCore
import EcliptixNetworking
import EcliptixProto
import EcliptixSecurity
import Foundation
import Observation
import SwiftProtobuf

public enum RegistrationStep: Equatable {
    case mobileNumber
    case otpVerification(sessionId: String, mobileNumberId: String)
    case secureKeySetup
    case passphraseSetup
    case complete(userId: String)
}

@MainActor
@Observable
public final class RegistrationService {

    public var isLoading: Bool = false
    public var errorMessage: String?
    public var currentStep: RegistrationStep = .mobileNumber
    public var otpCountdown: Int = 0

    public let mobileNumberValidation: ValidationState
    public let otpValidation: ValidationState
    public let secureKeyValidation: ValidationState
    public let passphraseValidation: ValidationState
    public let formValidation: FormValidationState

    private let networkProvider: NetworkProvider
    private let connectivityService: ConnectivityService
    private let localization: LocalizationService
    private let identityService: IdentityService
    private let opaqueAuthService: OpaqueAuthenticationService
    private let onIdentityKeysGenerated: (() async -> Void)?

    public private(set) var checkMobileAvailabilityCommand: DefaultAsyncCommand<Void, Void>
    public private(set) var sendOTPCommand: DefaultAsyncCommand<Void, Void>
    public private(set) var resendOTPCommand: DefaultAsyncCommand<Void, Void>
    public private(set) var verifyOTPCommand: DefaultAsyncCommand<Void, Void>
    public private(set) var completeRegistrationCommand: DefaultAsyncCommand<Void, String>

    private var cancellables = Set<AnyCancellable>()
    private var countdownTimer: Timer?

    public init(
        networkProvider: NetworkProvider,
        connectivityService: ConnectivityService,
        localization: LocalizationService,
        identityService: IdentityService,
        opaqueAuthService: OpaqueAuthenticationService,
        onIdentityKeysGenerated: (() async -> Void)? = nil
    ) {
        self.networkProvider = networkProvider
        self.connectivityService = connectivityService
        self.localization = localization
        self.identityService = identityService
        self.opaqueAuthService = opaqueAuthService
        self.onIdentityKeysGenerated = onIdentityKeysGenerated

        self.mobileNumberValidation = ValidationState(
            validator: MobileNumberValidator(
                localization: localization,
                allowInternational: true
            )
        )

        self.otpValidation = ValidationState(
            validator: OTPValidator(
                localization: localization,
                length: 6
            )
        )

        self.secureKeyValidation = ValidationState(
            validator: SecureKeyValidator(
                localization: localization,
                minLength: 12,
                maxLength: 64
            )
        )

        self.passphraseValidation = ValidationState(
            validator: PassphraseValidator(
                localization: localization,
                minWords: 12
            )
        )

        self.formValidation = FormValidationState(fields: [
            mobileNumberValidation,
            otpValidation,
            secureKeyValidation,
            passphraseValidation
        ])

        self.checkMobileAvailabilityCommand = DefaultAsyncCommand.createAction { }
        self.sendOTPCommand = DefaultAsyncCommand.createAction { }
        self.resendOTPCommand = DefaultAsyncCommand.createAction { }
        self.verifyOTPCommand = DefaultAsyncCommand.createAction { }
        self.completeRegistrationCommand = DefaultAsyncCommand.createAction { "" }

        setupCommands()
        setupBindings()
    }

    private func setupCommands() {
        self.checkMobileAvailabilityCommand = DefaultAsyncCommand.createAction { [weak self] in
            guard let self = self else { return }
            let result = await self.performCheckMobileAvailability()
            switch result {
            case .success:
                return
            case .failure(let error):
                self.errorMessage = error.localizedDescription
                throw error
            }
        }

        self.sendOTPCommand = DefaultAsyncCommand.createAction { [weak self] in
            guard let self = self else { return }
            let result = await self.performSendOTP()
            switch result {
            case .success:
                return
            case .failure(let error):
                self.errorMessage = error.localizedDescription
                throw error
            }
        }

        self.resendOTPCommand = DefaultAsyncCommand.createAction { [weak self] in
            guard let self = self else { return }
            let result = await self.performResendOTP()
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

        localization.languageChanged
            .sink { [weak self] _ in
                self?.revalidateAll()
            }
            .store(in: &cancellables)
    }

    private func revalidateAll() {
        mobileNumberValidation.validate()
        otpValidation.validate()
        secureKeyValidation.validate()
        passphraseValidation.validate()
    }

    public func checkMobileAvailability() async {
        await checkMobileAvailabilityCommand.execute()
    }

    public func sendOTP() async {
        await sendOTPCommand.execute()
    }

    public func resendOTP() async {
        await resendOTPCommand.execute()
    }

    public func verifyOTP() async {
        await verifyOTPCommand.execute()
    }

    public func completeRegistration() async {
        await completeRegistrationCommand.execute()
    }

    private func performCheckMobileAvailability() async -> Result<Void, Error> {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        mobileNumberValidation.markAsTouched()

        guard mobileNumberValidation.isValid else {
            let error = RegistrationError.invalidMobileNumber(
                mobileNumberValidation.errorMessage ?? localization[LocalizationKeys.Error.validation]
            )
            errorMessage = error.localizedDescription
            Log.warning("[Registration] Mobile number validation failed")
            return .failure(error)
        }

        Log.info("[Registration] Checking mobile availability")

        let connectId: UInt32 = 1
        let request = createMobileAvailabilityRequest(mobileNumberValidation.value)

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
            Log.info("[Registration] Mobile is available")
            return .success(())

        case .failure(let networkFailure):
            let errorMsg = localization[LocalizationKeys.Error.Network.operationFailed]
            let error = RegistrationError.networkError("\(errorMsg): \(networkFailure.message)")
            errorMessage = error.localizedDescription
            Log.error("[Registration] Availability check failed: \(networkFailure.message)")
            return .failure(error)
        }
    }

    private func performSendOTP() async -> Result<Void, Error> {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        mobileNumberValidation.markAsTouched()

        guard mobileNumberValidation.isValid else {
            let error = RegistrationError.invalidMobileNumber(
                mobileNumberValidation.errorMessage ?? localization[LocalizationKeys.Error.validation]
            )
            errorMessage = error.localizedDescription
            Log.warning("[Registration] Mobile number validation failed")
            return .failure(error)
        }

        Log.info("[Registration] Sending OTP")

        let connectId: UInt32 = 1
        let request = createOTPRequest(mobileNumberValidation.value)

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
            let sessionId = UUID().uuidString
            let mobileNumberId = UUID().uuidString
            currentStep = .otpVerification(sessionId: sessionId, mobileNumberId: mobileNumberId)
            startOTPCountdown(duration: 60)
            Log.info("[Registration] OTP sent successfully")
            return .success(())

        case .failure(let networkFailure):
            let errorMsg = localization[LocalizationKeys.Error.Network.operationFailed]
            let error = RegistrationError.networkError("\(errorMsg): \(networkFailure.message)")
            errorMessage = error.localizedDescription
            Log.error("[Registration] OTP send failed: \(networkFailure.message)")
            return .failure(error)
        }
    }

    private func performResendOTP() async -> Result<Void, Error> {
        guard case .otpVerification(let sessionId, let mobileNumberId) = currentStep else {
            let error = RegistrationError.invalidState("Not in OTP verification step")
            return .failure(error)
        }

        Log.info("[Registration] Resending OTP")

        let request: Data
        do {
            request = try createOTPResendRequest(sessionId: sessionId, mobileNumberId: mobileNumberId)
        } catch {
            Log.error("[Registration] Failed to create OTP resend request: \(error.localizedDescription)")
            return .failure(error)
        }

        let connectId: UInt32 = 1
        let result = await networkProvider.executeUnaryRequest(
            connectId: connectId,
            serviceType: .verifyOtp,
            plainBuffer: request,
            allowDuplicates: false,
            waitForRecovery: true
        ) { _ in }

        switch result {
        case .success:
            startOTPCountdown(duration: 60)
            Log.info("[Registration] OTP resent successfully")
            return .success(())

        case .failure(let networkFailure):
            let errorMsg = localization[LocalizationKeys.Error.Network.operationFailed]
            let error = RegistrationError.networkError("\(errorMsg): \(networkFailure.message)")
            errorMessage = error.localizedDescription
            Log.error("[Registration] OTP resend failed: \(networkFailure.message)")
            return .failure(error)
        }
    }

    private func performVerifyOTP() async -> Result<Void, Error> {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard case .otpVerification(let sessionId, _) = currentStep else {
            let error = RegistrationError.invalidState("Not in OTP verification step")
            errorMessage = error.localizedDescription
            return .failure(error)
        }

        otpValidation.markAsTouched()

        guard otpValidation.isValid else {
            let error = RegistrationError.invalidOTP(
                otpValidation.errorMessage ?? localization[LocalizationKeys.Error.validation]
            )
            errorMessage = error.localizedDescription
            Log.warning("[Registration] OTP validation failed")
            return .failure(error)
        }

        Log.info("[Registration] Verifying OTP")

        let connectId: UInt32 = 1
        let request: Data
        do {
            request = try createOTPVerificationRequest(sessionId: sessionId, otp: otpValidation.value)
        } catch {
            errorMessage = error.localizedDescription
            Log.error("[Registration] Failed to create OTP verification request: \(error.localizedDescription)")
            return .failure(error)
        }

        let result = await networkProvider.executeUnaryRequest(
            connectId: connectId,
            serviceType: .verifyOtp,
            plainBuffer: request,
            allowDuplicates: false,
            waitForRecovery: true
        ) { responseData in
            try await self.processOTPVerificationResponse(responseData)
        }

        switch result {
        case .success:
            stopOTPCountdown()
            currentStep = .secureKeySetup
            Log.info("[Registration] OTP verified")
            return .success(())

        case .failure(let networkFailure):
            let errorMsg = localization[LocalizationKeys.Error.Network.operationFailed]
            let error = RegistrationError.networkError("\(errorMsg): \(networkFailure.message)")
            errorMessage = error.localizedDescription
            Log.error("[Registration] OTP verification failed: \(networkFailure.message)")
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
            let error = RegistrationError.invalidSecureKey(
                secureKeyValidation.errorMessage ?? localization[LocalizationKeys.Error.validation]
            )
            errorMessage = error.localizedDescription
            Log.warning("[Registration] Secure key validation failed")
            return .failure(error)
        }

        guard passphraseValidation.isValid else {
            let error = RegistrationError.invalidPassphrase(
                passphraseValidation.errorMessage ?? localization[LocalizationKeys.Error.validation]
            )
            errorMessage = error.localizedDescription
            Log.warning("[Registration] Passphrase validation failed")
            return .failure(error)
        }

        Log.info("[Registration] Completing registration using OPAQUE protocol")

        let membershipIdentifier = Data(mobileNumberValidation.value.utf8)
        let registrationInitResult = await opaqueAuthService.registrationInit(
            mobileNumber: mobileNumberValidation.value,
            password: secureKeyValidation.value,
            membershipIdentifier: membershipIdentifier
        )

        switch registrationInitResult {
        case .success(let initResponse):
            guard initResponse.result == .succeeded else {
                let error = RegistrationError.opaqueError("Registration init failed: \(initResponse.message)")
                errorMessage = error.localizedDescription
                Log.error("[Registration] OPAQUE registration init failed: \(initResponse.message)")
                return .failure(error)
            }

            Log.info("[Registration] OPAQUE registration init successful")

            let registrationCompleteResult = await opaqueAuthService.registrationComplete(
                serverOprfResponse: initResponse.serverOprfResponse,
                membershipIdentifier: membershipIdentifier
            )

            switch registrationCompleteResult {
            case .success(let completeResponse):
                guard completeResponse.result == .succeeded else {
                    let error = RegistrationError.opaqueError("Registration complete failed: \(completeResponse.message)")
                    errorMessage = error.localizedDescription
                    Log.error("[Registration] OPAQUE registration complete failed: \(completeResponse.message)")
                    return .failure(error)
                }

                let userId = String(data: completeResponse.membershipIdentifier, encoding: .utf8) ?? UUID().uuidString

                do {
                    try await identityService.generateAndStoreIdentityKeys(
                        membershipId: userId,
                        recoveryPassphrase: passphraseValidation.value
                    )
                    Log.info("[Registration] Identity keys generated and stored successfully")
                } catch {
                    Log.error("[Registration] Failed to generate identity keys: \(error.localizedDescription)")
                    let registrationError = RegistrationError.identityKeyGenerationFailed(error.localizedDescription)
                    errorMessage = registrationError.localizedDescription
                    return .failure(registrationError)
                }

                await onIdentityKeysGenerated?()

                currentStep = .complete(userId: userId)
                Log.info("[Registration] [OK] Registration completed successfully with OPAQUE protocol")
                return .success(userId)

            case .failure(let serviceFailure):
                let errorMsg = localization[LocalizationKeys.Error.Network.operationFailed]
                let error = RegistrationError.networkError("\(errorMsg): \(serviceFailure.message)")
                errorMessage = error.localizedDescription
                Log.error("[Registration] OPAQUE registration complete failed: \(serviceFailure.message)")
                return .failure(error)
            }

        case .failure(let serviceFailure):
            let errorMsg = localization[LocalizationKeys.Error.Network.operationFailed]
            let error = RegistrationError.networkError("\(errorMsg): \(serviceFailure.message)")
            errorMessage = error.localizedDescription
            Log.error("[Registration] OPAQUE registration init failed: \(serviceFailure.message)")
            return .failure(error)
        }
    }

    private func startOTPCountdown(duration: Int) {
        stopOTPCountdown()
        otpCountdown = duration

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.otpCountdown > 0 {
                self.otpCountdown -= 1
            } else {
                self.stopOTPCountdown()
            }
        }
    }

    private func stopOTPCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        otpCountdown = 0
    }

    private func createMobileAvailabilityRequest(_ mobileNumber: String) -> Data {
        let request = ["mobileNumber": mobileNumber]
        return (try? JSONEncoder().encode(request)) ?? Data()
    }

    private func createOTPRequest(_ mobileNumber: String) -> Data {
        let request = ["mobileNumber": mobileNumber, "purpose": "registration"]
        return (try? JSONEncoder().encode(request)) ?? Data()
    }

    private func createOTPResendRequest(sessionId: String, mobileNumberId: String) throws -> Data {
        let mobileNumberIdData = mobileNumberId.data(using: .utf8) ?? Data()
        let deviceId = UUID().uuidString.data(using: .utf8) ?? Data()

        var request = Ecliptix_Proto_Membership_InitiateVerificationRequest()
        request.mobileNumberIdentifier = mobileNumberIdData
        request.appDeviceIdentifier = deviceId
        request.purpose = .registration
        request.type = .resendOtp  // Use RESEND_OTP type

        return try request.serializedData()
    }

    private func createOTPVerificationRequest(sessionId: String, otp: String) throws -> Data {
        let deviceId = UUID().uuidString.data(using: .utf8) ?? Data()

        var request = Ecliptix_Proto_Membership_VerifyCodeRequest()
        request.appDeviceIdentifier = deviceId
        request.code = otp
        request.purpose = .registration
        request.streamConnectID = 1  // connectId

        return try request.serializedData()
    }

    private func processMobileAvailabilityResponse(_ data: Data) async throws {
        let response = try Ecliptix_Proto_Membership_CheckMobileNumberAvailabilityResponse(serializedData: data)

        Log.info("[Registration] Mobile availability status: \(response.status)")

        if response.status.lowercased() != "available" {
            throw RegistrationError.mobileAlreadyRegistered("Mobile number is already registered")
        }
    }

    private func processOTPSendResponse(_ data: Data) async throws {
        let response = try Ecliptix_Proto_Membership_InitiateVerificationResponse(serializedData: data)

        Log.info("[Registration] OTP send result: \(response.result), message: \(response.message)")

        if response.result != .succeeded {
            throw RegistrationError.networkError("Failed to send OTP: \(response.message)")
        }

        if !response.sessionIdentifier.isEmpty {
            Log.debug("[Registration] OTP session ID: \(response.sessionIdentifier.base64EncodedString())")
        }
    }

    private func processOTPVerificationResponse(_ data: Data) async throws {
        let response = try Ecliptix_Proto_Membership_VerifyCodeResponse(serializedData: data)

        Log.info("[Registration] OTP verification result: \(response.result), message: \(response.message ?? "no message")")

        if response.result != .succeeded {
            throw RegistrationError.invalidOTP("OTP verification failed: \(response.message ?? "Invalid code")")
        }

        if response.hasMembership {
            Log.debug("[Registration] Membership received from OTP verification")
        }
    }

    public func reset() {
        stopOTPCountdown()
        mobileNumberValidation.reset()
        otpValidation.reset()
        secureKeyValidation.reset()
        passphraseValidation.reset()
        formValidation.resetAll()
        errorMessage = nil
        currentStep = .mobileNumber
        Log.debug("[Registration] Reset registration state")
    }

    deinit {
        stopOTPCountdown()
    }
}

public enum RegistrationError: LocalizedError {
    case invalidMobileNumber(String)
    case mobileAlreadyRegistered(String)
    case invalidOTP(String)
    case invalidSecureKey(String)
    case invalidPassphrase(String)
    case invalidState(String)
    case networkError(String)
    case opaqueError(String)
    case identityKeyGenerationFailed(String)
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .invalidMobileNumber(let message),
             .mobileAlreadyRegistered(let message),
             .invalidOTP(let message),
             .invalidSecureKey(let message),
             .invalidPassphrase(let message),
             .invalidState(let message),
             .networkError(let message),
             .opaqueError(let message),
             .identityKeyGenerationFailed(let message),
             .unknown(let message):
            return message
        }
    }
}

public extension RegistrationService {

    var canSendOTP: Bool {
        mobileNumberValidation.isValid
    }

    var canVerifyOTP: Bool {
        otpValidation.isValid
    }

    var canCompleteRegistration: Bool {
        secureKeyValidation.isValid && passphraseValidation.isValid
    }

    var canResendOTP: Bool {
        otpCountdown == 0
    }
}
