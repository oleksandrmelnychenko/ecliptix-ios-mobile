import Foundation
import Combine
import EcliptixCore

// MARK: - Registration Step
/// Steps in the registration flow
public enum RegistrationStep: Equatable {
    case mobileNumber
    case otpVerification
    case secureKeySetup
    case passPhrase
    case complete
}

// MARK: - Registration ViewModel
/// ViewModel for user registration flow
/// Migrated from: Ecliptix.Core/Features/Authentication/ViewModels/Registration/*
@MainActor
public final class RegistrationViewModel: BaseViewModel {

    // MARK: - Published Properties
    @Published public var mobileNumber: String = ""
    @Published public var countryCode: String = "+1"
    @Published public var secureKey: String = ""
    @Published public var secureKeyConfirmation: String = ""
    @Published public var passPhrase: [String] = []

    @Published public var currentStep: RegistrationStep = .mobileNumber

    @Published public var mobileNumberError: String?
    @Published public var secureKeyError: String?
    @Published public var secureKeyConfirmationError: String?

    @Published public var hasMobileNumberError: Bool = false
    @Published public var hasSecureKeyError: Bool = false
    @Published public var hasSecureKeyConfirmationError: Bool = false

    @Published public var canProceed: Bool = false
    @Published public var isMobileAvailable: Bool = false

    // MARK: - Private Properties
    private let membershipService: MembershipServiceClient
    private var hasMobileNumberBeenTouched = false
    private var hasSecureKeyBeenTouched = false
    private var hasSecureKeyConfirmationBeenTouched = false

    private let minSecureKeyLength = 12
    private let maxSecureKeyLength = 64
    private let passPhraseWordCount = 12

    // MARK: - Initialization
    public init(membershipService: MembershipServiceClient) {
        self.membershipService = membershipService
        super.init()
        setupValidation()
    }

    // MARK: - Setup Validation
    private func setupValidation() {
        // Validate mobile number
        $mobileNumber
            .dropFirst()
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.hasMobileNumberBeenTouched = true
                self.validateMobileNumber()
                self.updateCanProceed()
            }
            .store(in: &cancellables)

        // Validate secure key
        $secureKey
            .dropFirst()
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.hasSecureKeyBeenTouched = true
                self.validateSecureKey()
                self.updateCanProceed()
            }
            .store(in: &cancellables)

        // Validate secure key confirmation
        $secureKeyConfirmation
            .dropFirst()
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.hasSecureKeyConfirmationBeenTouched = true
                self.validateSecureKeyConfirmation()
                self.updateCanProceed()
            }
            .store(in: &cancellables)
    }

    // MARK: - Validation
    private func validateMobileNumber() {
        guard hasMobileNumberBeenTouched else {
            mobileNumberError = nil
            hasMobileNumberError = false
            return
        }

        if mobileNumber.isEmpty {
            mobileNumberError = "Mobile number is required"
            hasMobileNumberError = true
            return
        }

        let digitsOnly = mobileNumber.filter { $0.isNumber }
        if digitsOnly.count < 10 || digitsOnly.count > 15 {
            mobileNumberError = "Please enter a valid mobile number"
            hasMobileNumberError = true
            return
        }

        mobileNumberError = nil
        hasMobileNumberError = false
    }

    private func validateSecureKey() {
        guard hasSecureKeyBeenTouched else {
            secureKeyError = nil
            hasSecureKeyError = false
            return
        }

        if secureKey.isEmpty {
            secureKeyError = "Secure key is required"
            hasSecureKeyError = true
            return
        }

        if secureKey.count < minSecureKeyLength {
            secureKeyError = "Secure key must be at least \(minSecureKeyLength) characters"
            hasSecureKeyError = true
            return
        }

        if secureKey.count > maxSecureKeyLength {
            secureKeyError = "Secure key is too long"
            hasSecureKeyError = true
            return
        }

        // Check for complexity (at least one uppercase, lowercase, number, special char)
        let hasUppercase = secureKey.contains(where: { $0.isUppercase })
        let hasLowercase = secureKey.contains(where: { $0.isLowercase })
        let hasNumber = secureKey.contains(where: { $0.isNumber })
        let hasSpecial = secureKey.contains(where: { !$0.isLetter && !$0.isNumber })

        if !hasUppercase || !hasLowercase || !hasNumber || !hasSpecial {
            secureKeyError = "Secure key must include uppercase, lowercase, number, and special character"
            hasSecureKeyError = true
            return
        }

        secureKeyError = nil
        hasSecureKeyError = false
    }

    private func validateSecureKeyConfirmation() {
        guard hasSecureKeyConfirmationBeenTouched else {
            secureKeyConfirmationError = nil
            hasSecureKeyConfirmationError = false
            return
        }

        if secureKeyConfirmation.isEmpty {
            secureKeyConfirmationError = "Please confirm your secure key"
            hasSecureKeyConfirmationError = true
            return
        }

        if secureKeyConfirmation != secureKey {
            secureKeyConfirmationError = "Secure keys do not match"
            hasSecureKeyConfirmationError = true
            return
        }

        secureKeyConfirmationError = nil
        hasSecureKeyConfirmationError = false
    }

    private func updateCanProceed() {
        switch currentStep {
        case .mobileNumber:
            canProceed = !hasMobileNumberError && !mobileNumber.isEmpty && !isLoading

        case .otpVerification:
            canProceed = false // OTP is handled by OTPVerificationViewModel

        case .secureKeySetup:
            canProceed = !hasSecureKeyError &&
                        !hasSecureKeyConfirmationError &&
                        !secureKey.isEmpty &&
                        secureKey == secureKeyConfirmation &&
                        !isLoading

        case .passPhrase:
            canProceed = passPhrase.count == passPhraseWordCount

        case .complete:
            canProceed = false
        }
    }

    // MARK: - Check Mobile Availability
    public func checkMobileAvailability() {
        validateMobileNumber()

        guard !hasMobileNumberError else {
            Log.warning("[Registration] Cannot check availability - validation failed")
            return
        }

        executeAsync {
            Log.info("[Registration] Checking mobile availability: \(self.mobileNumber)")

            // TODO: Call membershipService.checkMobileAvailability(envelope)

            // Simulate network delay
            try await Task.sleep(nanoseconds: 1_000_000_000)

            // Placeholder
            return true

        } onSuccess: { isAvailable in
            self.isMobileAvailable = isAvailable

            if isAvailable {
                Log.info("[Registration] Mobile number is available")
                self.currentStep = .otpVerification
            } else {
                self.setError("This mobile number is already registered")
            }
        }
    }

    // MARK: - Start Registration
    public func startRegistration() {
        executeAsync {
            Log.info("[Registration] Starting registration for: \(self.mobileNumber)")

            // TODO: Call membershipService.registrationInit(envelope)

            // Simulate network delay
            try await Task.sleep(nanoseconds: 1_000_000_000)

            // Placeholder
            Log.info("[Registration] OTP sent")

        } onSuccess: { _ in
            // OTP sent, move to verification step
            self.currentStep = .otpVerification
        }
    }

    // MARK: - Complete Registration
    public func completeRegistration() {
        executeAsync {
            Log.info("[Registration] Completing registration")

            // TODO: Call membershipService.registrationComplete(envelope)

            // Simulate network delay
            try await Task.sleep(nanoseconds: 2_000_000_000)

            // Placeholder
            Log.info("[Registration] Registration complete")

        } onSuccess: { _ in
            self.currentStep = .complete
        }
    }

    // MARK: - Navigation
    public func proceedToSecureKeySetup() {
        currentStep = .secureKeySetup
    }

    public func proceedToPassPhrase() {
        validateSecureKey()
        validateSecureKeyConfirmation()

        guard !hasSecureKeyError && !hasSecureKeyConfirmationError else {
            return
        }

        // Generate pass phrase (12 random words)
        passPhrase = generatePassPhrase()
        currentStep = .passPhrase
    }

    // MARK: - Generate Pass Phrase
    private func generatePassPhrase() -> [String] {
        // TODO: Use actual BIP39 word list
        let sampleWords = ["apple", "banana", "cherry", "date", "elderberry", "fig",
                          "grape", "honey", "ivy", "jasmine", "kiwi", "lemon",
                          "mango", "nectarine", "orange", "peach", "quince", "raspberry"]

        return (0..<passPhraseWordCount).map { _ in
            sampleWords.randomElement() ?? "word"
        }
    }

    // MARK: - Reset
    public override func reset() {
        super.reset()

        mobileNumber = ""
        countryCode = "+1"
        secureKey = ""
        secureKeyConfirmation = ""
        passPhrase = []

        currentStep = .mobileNumber

        mobileNumberError = nil
        secureKeyError = nil
        secureKeyConfirmationError = nil

        hasMobileNumberError = false
        hasSecureKeyError = false
        hasSecureKeyConfirmationError = false

        hasMobileNumberBeenTouched = false
        hasSecureKeyBeenTouched = false
        hasSecureKeyConfirmationBeenTouched = false

        canProceed = false
        isMobileAvailable = false
    }
}
