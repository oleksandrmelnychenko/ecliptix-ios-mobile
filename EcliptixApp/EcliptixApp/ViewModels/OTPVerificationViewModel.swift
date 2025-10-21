import Foundation
import Combine
import EcliptixCore

// MARK: - OTP Verification ViewModel
/// ViewModel for OTP verification flow
/// Migrated from: Ecliptix.Core/Features/Authentication/ViewModels/Registration/VerifyOtpViewModel.cs
@MainActor
public final class OTPVerificationViewModel: BaseViewModel {

    // MARK: - Published Properties
    @Published public var otpCode: String = ""
    @Published public var otpError: String?
    @Published public var hasOTPError: Bool = false
    @Published public var canVerify: Bool = false
    @Published public var canResend: Bool = true

    @Published public var timeRemaining: Int = 0
    @Published public var isTimerActive: Bool = false

    // MARK: - Private Properties
    private let membershipService: MembershipServiceClient
    private let mobileNumber: String
    private let otpLength = 6
    private let resendCooldown: TimeInterval = 60.0 // 60 seconds
    private var resendTimer: Timer?

    // MARK: - Initialization
    public init(membershipService: MembershipServiceClient, mobileNumber: String) {
        self.membershipService = membershipService
        self.mobileNumber = mobileNumber
        super.init()
        setupValidation()
    }

    // MARK: - Setup Validation
    private func setupValidation() {
        $otpCode
            .map { code in
                // Allow only digits
                let filtered = code.filter { $0.isNumber }
                // Limit to OTP length
                return String(filtered.prefix(self.otpLength))
            }
            .removeDuplicates()
            .assign(to: &$otpCode)

        $otpCode
            .map { $0.count == self.otpLength }
            .assign(to: &$canVerify)

        $otpCode
            .sink { [weak self] code in
                guard let self = self else { return }

                if code.count == self.otpLength {
                    // Auto-submit when complete
                    self.verifyOTP()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Verify OTP
    public func verifyOTP() {
        guard otpCode.count == otpLength else {
            otpError = "Please enter the complete \(otpLength)-digit code"
            hasOTPError = true
            return
        }

        executeAsync {
            Log.info("[OTP] Verifying code: \(String(repeating: "*", count: self.otpLength))")

            // TODO: Call membershipService.verifyOTP(envelope)

            // Simulate network delay
            try await Task.sleep(nanoseconds: 1_000_000_000)

            // Placeholder - simulate success/failure
            if self.otpCode == "123456" {
                Log.info("[OTP] Verification successful")
                return true
            } else {
                throw NetworkError.unknown("Invalid OTP code")
            }

        } onSuccess: { _ in
            Log.info("[OTP] OTP verified successfully")
            // Proceed to next step
            self.otpError = nil
            self.hasOTPError = false

        } onError: { error in
            self.otpError = "Invalid code. Please try again."
            self.hasOTPError = true
            self.otpCode = "" // Clear for retry
        }
    }

    // MARK: - Resend OTP
    public func resendOTP() {
        guard canResend else {
            Log.warning("[OTP] Cannot resend - cooldown active")
            return
        }

        executeAsync {
            Log.info("[OTP] Resending OTP to: \(self.mobileNumber)")

            // TODO: Call membershipService to resend OTP

            // Simulate network delay
            try await Task.sleep(nanoseconds: 1_000_000_000)

            Log.info("[OTP] OTP resent")

        } onSuccess: { _ in
            self.startResendCooldown()
            // Show success message
        }
    }

    // MARK: - Resend Cooldown
    private func startResendCooldown() {
        canResend = false
        timeRemaining = Int(resendCooldown)
        isTimerActive = true

        resendTimer?.invalidate()
        resendTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            Task { @MainActor in
                self.timeRemaining -= 1

                if self.timeRemaining <= 0 {
                    self.stopResendCooldown()
                }
            }
        }
    }

    private func stopResendCooldown() {
        resendTimer?.invalidate()
        resendTimer = nil
        canResend = true
        isTimerActive = false
        timeRemaining = 0
    }

    // MARK: - Format Time
    public var formattedTimeRemaining: String {
        let minutes = timeRemaining / 60
        let seconds = timeRemaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Reset
    public override func reset() {
        super.reset()

        otpCode = ""
        otpError = nil
        hasOTPError = false
        canVerify = false

        stopResendCooldown()
        canResend = true
    }

    // MARK: - Cleanup
    deinit {
        resendTimer?.invalidate()
    }
}
