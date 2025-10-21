import Foundation
import Combine
import EcliptixCore

// MARK: - Sign In ViewModel
/// ViewModel for sign-in flow
/// Migrated from: Ecliptix.Core/Features/Authentication/ViewModels/SignIn/SignInViewModel.cs
@MainActor
public final class SignInViewModel: BaseViewModel {

    // MARK: - Published Properties
    @Published public var mobileNumber: String = ""
    @Published public var secureKey: String = ""

    @Published public var mobileNumberError: String?
    @Published public var secureKeyError: String?

    @Published public var hasMobileNumberError: Bool = false
    @Published public var hasSecureKeyError: Bool = false

    @Published public var canSignIn: Bool = false

    // MARK: - Private Properties
    private let membershipService: MembershipServiceClient
    private var hasMobileNumberBeenTouched = false
    private var hasSecureKeyBeenTouched = false

    // Minimum secure key length (adjust based on requirements)
    private let minSecureKeyLength = 8
    private let maxSecureKeyLength = 64

    // MARK: - Initialization
    public init(membershipService: MembershipServiceClient) {
        self.membershipService = membershipService
        super.init()
        setupValidation()
    }

    // MARK: - Setup Validation
    private func setupValidation() {
        // Validate mobile number on change
        $mobileNumber
            .dropFirst() // Skip initial value
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.hasMobileNumberBeenTouched = true
                self.validateMobileNumber()
                self.updateCanSignIn()
            }
            .store(in: &cancellables)

        // Validate secure key on change
        $secureKey
            .dropFirst()
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.hasSecureKeyBeenTouched = true
                self.validateSecureKey()
                self.updateCanSignIn()
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

        // Basic mobile number validation (digits only, 10-15 chars)
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

        secureKeyError = nil
        hasSecureKeyError = false
    }

    private func updateCanSignIn() {
        canSignIn = !mobileNumber.isEmpty &&
                    !secureKey.isEmpty &&
                    !hasMobileNumberError &&
                    !hasSecureKeyError &&
                    !isLoading
    }

    // MARK: - Sign In Action
    public func signIn() {
        // Mark fields as touched for validation
        hasMobileNumberBeenTouched = true
        hasSecureKeyBeenTouched = true

        // Validate
        validateMobileNumber()
        validateSecureKey()

        guard canSignIn else {
            Log.warning("[SignIn] Cannot sign in - validation failed")
            return
        }

        executeAsync {
            // TODO: Implement actual sign-in flow
            // 1. Call membershipService.signInInit(envelope)
            // 2. Process response
            // 3. Call membershipService.signInComplete(envelope)
            // 4. Handle authentication result

            Log.info("[SignIn] Signing in with mobile: \(self.mobileNumber)")

            // Simulate network delay
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

            // Placeholder - actual implementation will use OPAQUE protocol
            throw NetworkError.unknown("Sign-in not yet implemented - waiting for OPAQUE integration")

        } onSuccess: { _ in
            Log.info("[SignIn] Sign-in successful")
            // Navigate to main screen
        } onError: { error in
            Log.error("[SignIn] Sign-in failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Reset
    public override func reset() {
        super.reset()

        mobileNumber = ""
        secureKey = ""

        mobileNumberError = nil
        secureKeyError = nil

        hasMobileNumberError = false
        hasSecureKeyError = false

        hasMobileNumberBeenTouched = false
        hasSecureKeyBeenTouched = false

        canSignIn = false
    }

    // MARK: - Account Recovery
    public func navigateToAccountRecovery() {
        Log.info("[SignIn] Navigating to account recovery")
        // TODO: Implement navigation
    }

    // MARK: - Create Account
    public func navigateToRegistration() {
        Log.info("[SignIn] Navigating to registration")
        // TODO: Implement navigation
    }
}
