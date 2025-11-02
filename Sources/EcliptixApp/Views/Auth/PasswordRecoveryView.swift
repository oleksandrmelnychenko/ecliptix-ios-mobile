import SwiftUI

struct PasswordRecoveryView: View {
    let onBack: () -> Void

    @Environment(\.passwordRecoveryService) private var recoveryService: PasswordRecoveryService

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.blue)
                }
                Spacer()
            }
            .padding(.horizontal)

            Spacer()

            VStack(spacing: 16) {
                Text("Password Recovery")
                    .font(.system(size: 32, weight: .bold, design: .rounded))

                Text("Reset your secure key")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }

            if let errorMessage = recoveryService.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(errorMessage)
                        .font(.system(size: 14))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.leading)
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal, 32)
            }

            switch recoveryService.currentStep {
            case .mobileValidation:
                mobileValidationView
            case .otpVerification:
                otpVerificationView
            case .newPasswordSetup:
                newPasswordSetupView
            case .complete:
                completionView
            }

            Spacer()
        }
        .padding(.top, 20)
    }

    private var mobileValidationView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Mobile Number")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)

                TextField("Enter mobile number", text: $recoveryService.mobileNumberValidation.value)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                if recoveryService.mobileNumberValidation.isTouched,
                   let error = recoveryService.mobileNumberValidation.errorMessage {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 32)

            Button(action: { Task { await recoveryService.validateMobile() } }) {
                HStack {
                    if recoveryService.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Continue")
                            .font(.system(size: 18, weight: .semibold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
                .opacity(recoveryService.mobileNumberValidation.isValid ? 1.0 : 0.6)
            }
            .disabled(!recoveryService.mobileNumberValidation.isValid || recoveryService.isLoading)
            .padding(.horizontal, 32)
        }
    }

    private var otpVerificationView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Verification Code")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)

                TextField("Enter 6-digit code", text: $recoveryService.otpValidation.value)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                if recoveryService.otpValidation.isTouched,
                   let error = recoveryService.otpValidation.errorMessage {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }

                if recoveryService.otpCountdown > 0 {
                    Text("Resend code in \(recoveryService.otpCountdown)s")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 32)

            Button(action: { Task { await recoveryService.verifyOTP() } }) {
                HStack {
                    if recoveryService.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Verify Code")
                            .font(.system(size: 18, weight: .semibold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
                .opacity(recoveryService.otpValidation.isValid ? 1.0 : 0.6)
            }
            .disabled(!recoveryService.otpValidation.isValid || recoveryService.isLoading)
            .padding(.horizontal, 32)

            if recoveryService.otpCountdown == 0 {
                Button(action: { Task { await recoveryService.resendOTP() } }) {
                    Text("Resend Code")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.blue)
                }
            }
        }
    }

    private var newPasswordSetupView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("New Secure Key")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)

                SecureField("Enter new secure key", text: $recoveryService.newPasswordValidation.value)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.newPassword)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                if recoveryService.newPasswordValidation.isTouched,
                   let error = recoveryService.newPasswordValidation.errorMessage {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 32)

            VStack(alignment: .leading, spacing: 8) {
                Text("Confirm Secure Key")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)

                SecureField("Confirm secure key", text: $recoveryService.confirmPasswordValidation.value)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.newPassword)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                if recoveryService.confirmPasswordValidation.isTouched,
                   let error = recoveryService.confirmPasswordValidation.errorMessage {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 32)

            Button(action: { Task { await recoveryService.completeReset() } }) {
                HStack {
                    if recoveryService.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Reset Password")
                            .font(.system(size: 18, weight: .semibold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
                .opacity(canResetPassword ? 1.0 : 0.6)
            }
            .disabled(!canResetPassword || recoveryService.isLoading)
            .padding(.horizontal, 32)
        }
    }

    private var completionView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)

            Text("Password Reset Complete")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Text("Your secure key has been successfully reset")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: onBack) {
                Text("Return to Sign In")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
            }
            .padding(.horizontal, 32)
        }
    }

    private var canResetPassword: Bool {
        recoveryService.newPasswordValidation.isValid &&
        recoveryService.confirmPasswordValidation.isValid
    }
}

#Preview {
    PasswordRecoveryView(onBack: {})
}
