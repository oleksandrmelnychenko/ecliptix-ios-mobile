import SwiftUI

struct RegistrationView: View {

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var authService: AuthenticationService

    @State private var mobileNumber: String = ""
    @State private var secureKey: String = ""
    @State private var confirmSecureKey: String = ""
    @State private var showSecureKey: Bool = false
    @State private var showConfirmSecureKey: Bool = false
    @State private var showError: Bool = false
    @State private var currentStep: RegistrationStep = .mobileNumber

    private enum RegistrationStep {
        case mobileNumber
        case secureKey
        case confirmation
    }

    init(authService: AuthenticationService) {
        _authService = State(initialValue: authService)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundColor
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    progressIndicator

                    ScrollView {
                        VStack(spacing: 32) {
                            headerSection

                            currentStepContent

                            actionButton

                            if currentStep == .mobileNumber {
                                alternativeActionsSection
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 32)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if currentStep != .mobileNumber {
                        Button {
                            previousStep()
                        } label: {
                            Image(systemName: "chevron.left")
                                .foregroundColor(.primary)
                        }
                    } else {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {
                    showError = false
                    authService.errorMessage = nil
                }
            } message: {
                Text(authService.errorMessage ?? "An error occurred")
            }
        }
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }

    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach([RegistrationStep.mobileNumber, .secureKey, .confirmation], id: \.self) { step in
                Rectangle()
                    .fill(stepIndex(step) <= stepIndex(currentStep) ? Color.blue : Color.secondary.opacity(0.3))
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    private var headerSection: some View {
        VStack(spacing: 16) {
            Circle()
                .fill(Color.blue.gradient)
                .frame(width: 60, height: 60)
                .overlay {
                    Image(systemName: currentStepIcon)
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                }

            VStack(spacing: 8) {
                Text(currentStepTitle)
                    .font(.system(size: 28, weight: .bold))

                Text(currentStepSubtitle)
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private var currentStepContent: some View {
        switch currentStep {
        case .mobileNumber:
            mobileNumberStep
        case .secureKey:
            secureKeyStep
        case .confirmation:
            confirmationStep
        }
    }

    private var mobileNumberStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mobile Number")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)

            TextField("Enter your mobile number", text: $mobileNumber)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue, lineWidth: 2)
                )

            Text("We'll send you an OTP to verify your number")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
    }

    private var secureKeyStep: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Create Secure Key")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)

                HStack {
                    if showSecureKey {
                        TextField("Enter secure key", text: $secureKey)
                            .textContentType(.newPassword)
                    } else {
                        SecureField("Enter secure key", text: $secureKey)
                            .textContentType(.newPassword)
                    }

                    Button {
                        showSecureKey.toggle()
                    } label: {
                        Image(systemName: showSecureKey ? "eye.slash.fill" : "eye.fill")
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)
            }

            secureKeyRequirements
        }
    }

    private var secureKeyRequirements: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Requirements:")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)

            RequirementRow(
                text: "At least 12 characters",
                isMet: secureKey.count >= 12
            )

            RequirementRow(
                text: "Contains uppercase letter",
                isMet: secureKey.contains(where: { $0.isUppercase })
            )

            RequirementRow(
                text: "Contains lowercase letter",
                isMet: secureKey.contains(where: { $0.isLowercase })
            )

            RequirementRow(
                text: "Contains number",
                isMet: secureKey.contains(where: { $0.isNumber })
            )

            RequirementRow(
                text: "Contains special character",
                isMet: secureKey.contains(where: { !$0.isLetter && !$0.isNumber })
            )
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }

    private var confirmationStep: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Confirm Secure Key")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)

                HStack {
                    if showConfirmSecureKey {
                        TextField("Re-enter secure key", text: $confirmSecureKey)
                            .textContentType(.newPassword)
                    } else {
                        SecureField("Re-enter secure key", text: $confirmSecureKey)
                            .textContentType(.newPassword)
                    }

                    Button {
                        showConfirmSecureKey.toggle()
                    } label: {
                        Image(systemName: showConfirmSecureKey ? "eye.slash.fill" : "eye.fill")
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)
            }

            if !confirmSecureKey.isEmpty {
                HStack {
                    Image(systemName: secureKeysMatch ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(secureKeysMatch ? .green : .red)

                    Text(secureKeysMatch ? "Secure keys match" : "Secure keys don't match")
                        .font(.system(size: 14))
                        .foregroundColor(secureKeysMatch ? .green : .red)
                }
            }
        }
    }

    private var actionButton: some View {
        Button {
            Task {
                await handleAction()
            }
        } label: {
            HStack {
                if authService.isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Text(actionButtonTitle)
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(isActionEnabled ? Color.blue : Color.secondary.opacity(0.3))
            .foregroundColor(.white)
            .cornerRadius(16)
        }
        .disabled(!isActionEnabled || authService.isLoading)
    }

    private var alternativeActionsSection: some View {
        VStack(spacing: 16) {
            Divider()
                .padding(.vertical, 8)

            HStack(spacing: 4) {
                Text("Already have an account?")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)

                Button {
                    dismiss()
                } label: {
                    Text("Sign In")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.blue)
                }
            }
        }
    }

    private var currentStepIcon: String {
        switch currentStep {
        case .mobileNumber: return "phone.fill"
        case .secureKey: return "key.fill"
        case .confirmation: return "checkmark.shield.fill"
        }
    }

    private var currentStepTitle: String {
        switch currentStep {
        case .mobileNumber: return "Register"
        case .secureKey: return "Secure Key"
        case .confirmation: return "Confirm"
        }
    }

    private var currentStepSubtitle: String {
        switch currentStep {
        case .mobileNumber: return "Enter your mobile number to get started"
        case .secureKey: return "Create a strong secure key"
        case .confirmation: return "Confirm your secure key"
        }
    }

    private var actionButtonTitle: String {
        switch currentStep {
        case .mobileNumber: return "Continue"
        case .secureKey: return "Continue"
        case .confirmation: return "Complete Registration"
        }
    }

    private var isActionEnabled: Bool {
        switch currentStep {
        case .mobileNumber:
            return !mobileNumber.isEmpty
        case .secureKey:
            return isSecureKeyValid
        case .confirmation:
            return secureKeysMatch && !confirmSecureKey.isEmpty
        }
    }

    private var isSecureKeyValid: Bool {
        secureKey.count >= 12 &&
        secureKey.contains(where: { $0.isUppercase }) &&
        secureKey.contains(where: { $0.isLowercase }) &&
        secureKey.contains(where: { $0.isNumber }) &&
        secureKey.contains(where: { !$0.isLetter && !$0.isNumber })
    }

    private var secureKeysMatch: Bool {
        secureKey == confirmSecureKey
    }

    private func stepIndex(_ step: RegistrationStep) -> Int {
        switch step {
        case .mobileNumber: return 0
        case .secureKey: return 1
        case .confirmation: return 2
        }
    }

    private func handleAction() async {
        switch currentStep {
        case .mobileNumber:
            await checkMobileAvailability()

        case .secureKey:
            currentStep = .confirmation

        case .confirmation:
            await performRegistration()
        }
    }

    private func checkMobileAvailability() async {
        currentStep = .secureKey
    }

    private func performRegistration() async {
        let result = await authService.register(
            mobileNumber: mobileNumber,
            secureKey: secureKey
        )

        switch result {
        case .success:
            break
        case .failure:
            showError = true
        }
    }

    private func previousStep() {
        switch currentStep {
        case .mobileNumber:
            break
        case .secureKey:
            currentStep = .mobileNumber
        case .confirmation:
            currentStep = .secureKey
        }
    }
}

private struct RequirementRow: View {
    let text: String
    let isMet: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isMet ? .green : .secondary)
                .font(.system(size: 14))

            Text(text)
                .font(.system(size: 13))
                .foregroundColor(isMet ? .primary : .secondary)

            Spacer()
        }
    }
}

#Preview {
    Text("RegistrationView Preview")
}
