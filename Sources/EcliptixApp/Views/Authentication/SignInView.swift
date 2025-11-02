import SwiftUI

struct SignInView: View {

    @Environment(\.colorScheme) private var colorScheme
    @State private var service: SignInService

    @State private var showSecureKey: Bool = false
    @State private var showError: Bool = false

    let onBack: () -> Void
    let onForgotPassword: () -> Void

    init(
        service: SignInService,
        onBack: @escaping () -> Void,
        onForgotPassword: @escaping () -> Void
    ) {
        _service = State(initialValue: service)
        self.onBack = onBack
        self.onForgotPassword = onForgotPassword
    }

    var body: some View {
        NavigationStack {
            ZStack {

                backgroundColor
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 32) {
                        headerSection

                        inputSection

                        signInButton

                        alternativeActionsSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 60)
                }
            }
            .navigationBarHidden(true)
            .alert("Error", isPresented: $showError) {
                Button("OK") {
                    showError = false
                    service.serverError = nil
                }
            } message: {
                Text(service.serverError ?? "An error occurred")
            }
        }
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }

    private var headerSection: some View {
        VStack(spacing: 16) {
            Circle()
                .fill(Color.blue.gradient)
                .frame(width: 80, height: 80)
                .overlay {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                }

            VStack(spacing: 8) {
                Text(service.welcomeBackText)
                    .font(.system(size: 32, weight: .bold))

                Text(service.signInSubtitleText)
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var inputSection: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(service.mobileNumberLabelText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)

                TextField("Enter your mobile number", text: $service.mobileNumber)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                service.hasMobileNumberError ? Color.red :
                                    focusedField == .mobile ? Color.blue : Color.clear,
                                lineWidth: 2
                            )
                    )
                    .focused($focusedField, equals: .mobile)
                    .onSubmit {
                        service.markMobileNumberAsTouched()
                        focusedField = .secureKey
                    }

                if let error = service.mobileNumberError, !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .transition(.opacity)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(service.secureKeyLabelText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)

                HStack {
                    if showSecureKey {
                        TextField("Enter your secure key", text: $service.secureKey)
                            .textContentType(.password)
                    } else {
                        SecureField("Enter your secure key", text: $service.secureKey)
                            .textContentType(.password)
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
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            service.hasSecureKeyError ? Color.red :
                                focusedField == .secureKey ? Color.blue : Color.clear,
                            lineWidth: 2
                        )
                )
                .focused($focusedField, equals: .secureKey)
                .onSubmit {
                    service.markSecureKeyAsTouched()
                    if service.canSignIn {
                        Task {
                            await performSignIn()
                        }
                    }
                }

                if let error = service.secureKeyError, !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .transition(.opacity)
                }
            }
        }
    }

    private var signInButton: some View {
        Button {
            Task {
                await performSignIn()
            }
        } label: {
            HStack {
                if service.isBusy {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Text(service.signInButtonText)
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(service.canSignIn ? Color.blue : Color.secondary.opacity(0.3))
            .foregroundColor(.white)
            .cornerRadius(16)
        }
        .disabled(!service.canSignIn || service.isBusy)
    }

    private var alternativeActionsSection: some View {
        VStack(spacing: 16) {
            Button {
                service.startAccountRecovery()
                onForgotPassword()
            } label: {
                Text(service.forgotSecureKeyText)
                    .font(.system(size: 15))
                    .foregroundColor(.blue)
            }
            .disabled(service.isBusy)

            Divider()
                .padding(.vertical, 8)

            HStack(spacing: 4) {
                Text(service.noAccountText)
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)

                Button {
                    onBack()
                } label: {
                    Text(service.registerText)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.blue)
                }
            }
            .disabled(service.isBusy)
        }
    }

    @FocusState private var focusedField: Field?

    private enum Field {
        case mobile
        case secureKey
    }

    private func performSignIn() async {
        Log.info("[SignInView] Performing sign-in")

        focusedField = nil

        let result = await service.signIn()

        switch result {
        case .success(let userId):
            Log.info("[SignInView] Sign-in successful for user: \(userId)")

        case .failure(let error):
            Log.error("[SignInView] Sign-in failed: \(error.localizedDescription)")
            showError = true
        }
    }
}

#Preview {
    Text("SignInView Preview")
}
