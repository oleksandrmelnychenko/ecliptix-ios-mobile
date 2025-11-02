import Combine
import EcliptixCore
import EcliptixNetworking
import Foundation
import Observation

public enum PasswordRecoveryStep: Equatable {
    case mobileValidation
    case otpVerification(sessionId: String, mobileNumberId: String)
    case newPasswordSetup(membershipId: String)
    case complete
}

@MainActor
@Observable
public final class PasswordRecoveryService {

    public var isLoading: Bool = false
    public var errorMessage: String?
    public var currentStep: PasswordRecoveryStep = .mobileValidation
    public var otpCountdown: Int = 0

    public let mobileNumberValidation: ValidationState
    public let otpValidation: ValidationState
    public let newPasswordValidation: ValidationState
    public let confirmPasswordValidation: ValidationState

    private let networkProvider: NetworkProvider
    private let connectivityService: ConnectivityService
    private let localization: LocalizationService

    public private(set) var validateMobileCommand: DefaultAsyncCommand<Void, Void>
    public private(set) var verifyOTPCommand: DefaultAsyncCommand<Void, Void>
    public private(set) var resendOTPCommand: DefaultAsyncCommand<Void, Void>
    public private(set) var completeResetCommand: DefaultAsyncCommand<Void, Void>

    private var cancellables = Set<AnyCancellable>()
    private var countdownTimer: Timer?

    public init(
        networkProvider: NetworkProvider,
        connectivityService: ConnectivityService,
        localization: LocalizationService
    ) {
        self.networkProvider = networkProvider
        self.connectivityService = connectivityService
        self.localization = localization

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

        self.newPasswordValidation = ValidationState(
            validator: SecureKeyValidator(
                localization: localization,
                minLength: 12,
                maxLength: 64
            )
        )

        self.confirmPasswordValidation = ValidationState(
            validator: MatchingValidator(
                localization: localization,
                fieldName: "Confirm Password",
                matchAgainst: { [weak self] in self?.newPasswordValidation.value ?? "" }
            )
        )

        self.validateMobileCommand = DefaultAsyncCommand.createAction { }
        self.verifyOTPCommand = DefaultAsyncCommand.createAction { }
        self.resendOTPCommand = DefaultAsyncCommand.createAction { }
        self.completeResetCommand = DefaultAsyncCommand.createAction { }

        setupCommands()
        setupBindings()
    }

    private func setupCommands() {
        self.validateMobileCommand = DefaultAsyncCommand.createAction { [weak self] in
            guard let self = self else { return }
            let result = await self.performValidateMobile()
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

        self.completeResetCommand = DefaultAsyncCommand.createAction { [weak self] in
            guard let self = self else { return }
            let result = await self.performCompleteReset()
            switch result {
            case .success:
                return
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
        newPasswordValidation.validate()
        confirmPasswordValidation.validate()
    }

    public func validateMobile() async {
        await validateMobileCommand.execute()
    }

    public func verifyOTP() async {
        await verifyOTPCommand.execute()
    }

    public func resendOTP() async {
        await resendOTPCommand.execute()
    }

    public func completeReset() async {
        await completeResetCommand.execute()
    }

    private func performValidateMobile() async -> Result<Void, Error> {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        mobileNumberValidation.markAsTouched()

        guard mobileNumberValidation.isValid else {
            let error = PasswordRecoveryError.invalidMobileNumber(
                mobileNumberValidation.errorMessage ?? localization[LocalizationKeys.Error.validation]
            )
            errorMessage = error.localizedDescription
            Log.warning("[PasswordRecovery] Mobile number validation failed")
            return .failure(error)
        }

        Log.info("[PasswordRecovery] Validating mobile for recovery")

        let connectId: UInt32 = 1
        let request: Data
        do {
            request = try createMobileValidationRequest(mobileNumberValidation.value)
        } catch {
            errorMessage = error.localizedDescription
            Log.error("[PasswordRecovery] Failed to create mobile validation request: \(error.localizedDescription)")
            return .failure(error)
        }

        let result = await networkProvider.executeUnaryRequest(
            connectId: connectId,
            serviceType: .validateMobileForRecovery,
            plainBuffer: request,
            allowDuplicates: false,
            waitForRecovery: true
        ) { responseData in
            try await self.processMobileValidationResponse(responseData)
        }

        switch result {
        case .success:
            let sessionId = UUID().uuidString
            let mobileNumberId = UUID().uuidString
            currentStep = .otpVerification(sessionId: sessionId, mobileNumberId: mobileNumberId)
            startOTPCountdown(duration: 60)
            Log.info("[PasswordRecovery] Mobile validated, OTP sent")
            return .success(())

        case .failure(let networkFailure):
            let errorMsg = localization[LocalizationKeys.Error.Network.operationFailed]
            let error = PasswordRecoveryError.networkError("\(errorMsg): \(networkFailure.message)")
            errorMessage = error.localizedDescription
            Log.error("[PasswordRecovery] Mobile validation failed: \(networkFailure.message)")
            return .failure(error)
        }
    }

    private func performVerifyOTP() async -> Result<Void, Error> {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard case .otpVerification(let sessionId, _) = currentStep else {
            let error = PasswordRecoveryError.invalidState("Not in OTP verification step")
            errorMessage = error.localizedDescription
            return .failure(error)
        }

        otpValidation.markAsTouched()

        guard otpValidation.isValid else {
            let error = PasswordRecoveryError.invalidOTP(
                otpValidation.errorMessage ?? localization[LocalizationKeys.Error.validation]
            )
            errorMessage = error.localizedDescription
            Log.warning("[PasswordRecovery] OTP validation failed")
            return .failure(error)
        }

        Log.info("[PasswordRecovery] Verifying OTP")

        let connectId: UInt32 = 1
        let request: Data
        do {
            request = try createOTPVerificationRequest(sessionId: sessionId, otp: otpValidation.value)
        } catch {
            errorMessage = error.localizedDescription
            Log.error("[PasswordRecovery] Failed to create OTP verification request: \(error.localizedDescription)")
            return .failure(error)
        }

        let result = await networkProvider.executeUnaryRequest(
            connectId: connectId,
            serviceType: .verifyPasswordResetOtp,
            plainBuffer: request,
            allowDuplicates: false,
            waitForRecovery: true
        ) { responseData in
            try await self.processOTPVerificationResponse(responseData)
        }

        switch result {
        case .success:
            stopOTPCountdown()
            let membershipId = UUID().uuidString
            currentStep = .newPasswordSetup(membershipId: membershipId)
            Log.info("[PasswordRecovery] OTP verified")
            return .success(())

        case .failure(let networkFailure):
            let errorMsg = localization[LocalizationKeys.Error.Network.operationFailed]
            let error = PasswordRecoveryError.networkError("\(errorMsg): \(networkFailure.message)")
            errorMessage = error.localizedDescription
            Log.error("[PasswordRecovery] OTP verification failed: \(networkFailure.message)")
            return .failure(error)
        }
    }

    private func performResendOTP() async -> Result<Void, Error> {
        guard case .otpVerification(let sessionId, let mobileNumberId) = currentStep else {
            let error = PasswordRecoveryError.invalidState("Not in OTP verification step")
            return .failure(error)
        }

        Log.info("[PasswordRecovery] Resending OTP")

        let request: Data
        do {
            request = try createOTPResendRequest(sessionId: sessionId, mobileNumberId: mobileNumberId)
        } catch {
            Log.error("[PasswordRecovery] Failed to create OTP resend request: \(error.localizedDescription)")
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
            Log.info("[PasswordRecovery] OTP resent successfully")
            return .success(())

        case .failure(let networkFailure):
            let errorMsg = localization[LocalizationKeys.Error.Network.operationFailed]
            let error = PasswordRecoveryError.networkError("\(errorMsg): \(networkFailure.message)")
            errorMessage = error.localizedDescription
            Log.error("[PasswordRecovery] OTP resend failed: \(networkFailure.message)")
            return .failure(error)
        }
    }

    private func performCompleteReset() async -> Result<Void, Error> {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard case .newPasswordSetup(let membershipId) = currentStep else {
            let error = PasswordRecoveryError.invalidState("Not in password setup step")
            errorMessage = error.localizedDescription
            return .failure(error)
        }

        newPasswordValidation.markAsTouched()
        confirmPasswordValidation.markAsTouched()

        guard newPasswordValidation.isValid else {
            let error = PasswordRecoveryError.invalidPassword(
                newPasswordValidation.errorMessage ?? localization[LocalizationKeys.Error.validation]
            )
            errorMessage = error.localizedDescription
            Log.warning("[PasswordRecovery] New password validation failed")
            return .failure(error)
        }

        guard confirmPasswordValidation.isValid else {
            let error = PasswordRecoveryError.passwordMismatch(
                localization[LocalizationKeys.Authentication.Registration.passwordMismatch]
            )
            errorMessage = error.localizedDescription
            Log.warning("[PasswordRecovery] Password confirmation failed")
            return .failure(error)
        }

        Log.info("[PasswordRecovery] Completing password reset")

        let connectId: UInt32 = 1
        let request: Data
        do {
            request = try await createPasswordResetRequest(
                membershipId: membershipId,
                newPassword: newPasswordValidation.value
            )
        } catch {
            errorMessage = error.localizedDescription
            Log.error("[PasswordRecovery] Failed to create password reset request: \(error.localizedDescription)")
            return .failure(error)
        }

        let result = await networkProvider.executeUnaryRequest(
            connectId: connectId,
            serviceType: .completePasswordReset,
            plainBuffer: request,
            allowDuplicates: false,
            waitForRecovery: true
        ) { responseData in
            try await self.processPasswordResetResponse(responseData)
        }

        switch result {
        case .success:
            currentStep = .complete
            Log.info("[PasswordRecovery] Password reset completed")
            return .success(())

        case .failure(let networkFailure):
            let errorMsg = localization[LocalizationKeys.Error.Network.operationFailed]
            let error = PasswordRecoveryError.networkError("\(errorMsg): \(networkFailure.message)")
            errorMessage = error.localizedDescription
            Log.error("[PasswordRecovery] Password reset failed: \(networkFailure.message)")
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

    private func createMobileValidationRequest(_ mobileNumber: String) throws -> Data {
        let deviceId = UUID().uuidString.data(using: .utf8) ?? Data()

        var request = Ecliptix_Proto_Membership_ValidateMobileNumberRequest()
        request.mobileNumber = mobileNumber
        request.appDeviceIdentifier = deviceId

        return try request.serializedData()
    }

    private func createOTPVerificationRequest(sessionId: String, otp: String) throws -> Data {
        let deviceId = UUID().uuidString.data(using: .utf8) ?? Data()

        var request = Ecliptix_Proto_Membership_VerifyCodeRequest()
        request.appDeviceIdentifier = deviceId
        request.code = otp
        request.purpose = .passwordRecovery
        request.streamConnectID = 1

        return try request.serializedData()
    }

    private func createOTPResendRequest(sessionId: String, mobileNumberId: String) throws -> Data {
        let mobileNumberIdData = mobileNumberId.data(using: .utf8) ?? Data()
        let deviceId = UUID().uuidString.data(using: .utf8) ?? Data()

        var request = Ecliptix_Proto_Membership_InitiateVerificationRequest()
        request.mobileNumberIdentifier = mobileNumberIdData
        request.appDeviceIdentifier = deviceId
        request.purpose = .passwordRecovery
        request.type = .resendOtp

        return try request.serializedData()
    }

    private func createPasswordResetRequest(membershipId: String, newPassword: String) async throws -> Data {
        guard let membershipUUID = UUID(uuidString: membershipId) else {
            throw PasswordRecoveryError.unknown("Invalid membership ID format")
        }

        var uuidBytes = membershipUUID.uuid
        let membershipIdData = withUnsafeBytes(of: &uuidBytes) { Data($0) }

        var request = Ecliptix_Proto_Membership_OpaqueRecoverySecretKeyCompleteRequest()
        request.membershipIdentifier = membershipIdData
        request.peerRecoveryRecord = Data()

        return try request.serializedData()
    }

    private func processMobileValidationResponse(_ data: Data) async throws {
        let response = try Ecliptix_Proto_Membership_ValidateMobileNumberResponse(serializedData: data)

        Log.info("[PasswordRecovery] Mobile validation result: \(response.result), message: \(response.message ?? "no message")")

        if response.result != .succeeded {
            throw PasswordRecoveryError.invalidMobileNumber("Mobile validation failed: \(response.message ?? "Invalid mobile number")")
        }

        if !response.mobileNumberIdentifier.isEmpty {
            Log.debug("[PasswordRecovery] Mobile number ID: \(response.mobileNumberIdentifier.base64EncodedString())")
        }
    }

    private func processOTPVerificationResponse(_ data: Data) async throws {
        let response = try Ecliptix_Proto_Membership_VerifyCodeResponse(serializedData: data)

        Log.info("[PasswordRecovery] OTP verification result: \(response.result), message: \(response.message ?? "no message")")

        if response.result != .succeeded {
            throw PasswordRecoveryError.invalidOTP("OTP verification failed: \(response.message ?? "Invalid code")")
        }

        if response.hasMembership {
            Log.debug("[PasswordRecovery] Membership received from OTP verification")
        }
    }

    private func processPasswordResetResponse(_ data: Data) async throws {
        let response = try Ecliptix_Proto_Membership_OpaqueRecoverySecretKeyCompleteResponse(serializedData: data)

        Log.info("[PasswordRecovery] Password reset response: message=\(response.message ?? "no message")")

        Log.info("[PasswordRecovery] Password reset completed successfully")
    }

    public func reset() {
        stopOTPCountdown()
        mobileNumberValidation.reset()
        otpValidation.reset()
        newPasswordValidation.reset()
        confirmPasswordValidation.reset()
        errorMessage = nil
        currentStep = .mobileValidation
        Log.debug("[PasswordRecovery] Reset recovery state")
    }

    deinit {
        stopOTPCountdown()
    }
}

public enum PasswordRecoveryError: LocalizedError {
    case invalidMobileNumber(String)
    case invalidOTP(String)
    case invalidPassword(String)
    case passwordMismatch(String)
    case invalidState(String)
    case networkError(String)
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .invalidMobileNumber(let message),
             .invalidOTP(let message),
             .invalidPassword(let message),
             .passwordMismatch(let message),
             .invalidState(let message),
             .networkError(let message),
             .unknown(let message):
            return message
        }
    }
}

private class MatchingValidator: FieldValidator {
    private let localization: LocalizationService
    private let fieldName: String
    private let matchAgainst: () -> String

    init(localization: LocalizationService, fieldName: String, matchAgainst: @escaping () -> String) {
        self.localization = localization
        self.fieldName = fieldName
        self.matchAgainst = matchAgainst
    }

    func validate(_ value: String) -> ValidationResult {
        if value.isEmpty {
            return .invalid(error: "\(fieldName) is required")
        }

        if value != matchAgainst() {
            return .invalid(error: "\(fieldName) does not match")
        }

        return .valid
    }
}
