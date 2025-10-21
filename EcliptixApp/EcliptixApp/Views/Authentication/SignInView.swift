import SwiftUI

// MARK: - Sign In View
/// Modern SwiftUI view for user sign-in
/// Uses service-based architecture with @Observable
struct SignInView: View {

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme
    @State private var authService: AuthenticationService

    // MARK: - State

    @State private var mobileNumber: String = ""
    @State private var secureKey: String = ""
    @State private var showSecureKey: Bool = false
    @State private var showError: Bool = false

    // MARK: - Initialization

    init(authService: AuthenticationService) {
        _authService = State(initialValue: authService)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                backgroundColor
                    .ignoresSafeArea()

                // Content
                ScrollView {
                    VStack(spacing: 32) {
                        // Logo and title
                        headerSection

                        // Input fields
                        inputSection

                        // Sign in button
                        signInButton

                        // Alternative actions
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
                    authService.errorMessage = nil
                }
            } message: {
                Text(authService.errorMessage ?? "An error occurred")
            }
        }
    }

    // MARK: - Components

    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }

    private var headerSection: some View {
        VStack(spacing: 16) {
            // Logo placeholder
            Circle()
                .fill(Color.blue.gradient)
                .frame(width: 80, height: 80)
                .overlay {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                }

            VStack(spacing: 8) {
                Text("Welcome Back")
                    .font(.system(size: 32, weight: .bold))

                Text("Sign in to continue to Ecliptix")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var inputSection: some View {
        VStack(spacing: 20) {
            // Mobile number field
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
                            .stroke(focusedField == .mobile ? Color.blue : Color.clear, lineWidth: 2)
                    )
            }

            // Secure key field
            VStack(alignment: .leading, spacing: 8) {
                Text("Secure Key")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)

                HStack {
                    if showSecureKey {
                        TextField("Enter your secure key", text: $secureKey)
                            .textContentType(.password)
                    } else {
                        SecureField("Enter your secure key", text: $secureKey)
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
                        .stroke(focusedField == .secureKey ? Color.blue : Color.clear, lineWidth: 2)
                )
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
                if authService.isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Text("Sign In")
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(isSignInEnabled ? Color.blue : Color.secondary.opacity(0.3))
            .foregroundColor(.white)
            .cornerRadius(16)
        }
        .disabled(!isSignInEnabled || authService.isLoading)
    }

    private var alternativeActionsSection: some View {
        VStack(spacing: 16) {
            // Forgot secure key
            Button {
                // Navigate to recovery
            } label: {
                Text("Forgot your secure key?")
                    .font(.system(size: 15))
                    .foregroundColor(.blue)
            }

            Divider()
                .padding(.vertical, 8)

            // Register
            HStack(spacing: 4) {
                Text("Don't have an account?")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)

                Button {
                    // Navigate to registration
                } label: {
                    Text("Register")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.blue)
                }
            }
        }
    }

    // MARK: - Computed Properties

    @FocusState private var focusedField: Field?

    private enum Field {
        case mobile
        case secureKey
    }

    private var isSignInEnabled: Bool {
        !mobileNumber.isEmpty && !secureKey.isEmpty
    }

    // MARK: - Actions

    private func performSignIn() async {
        // Hide keyboard
        focusedField = nil

        // Perform sign-in via service
        let result = await authService.signIn(
            mobileNumber: mobileNumber,
            secureKey: secureKey
        )

        switch result {
        case .success:
            // Navigation handled by service or coordinator
            break
        case .failure:
            showError = true
        }
    }
}

// MARK: - Preview

#Preview {
    SignInView(authService: AuthenticationService(
        networkProvider: nil // Preview with nil
    ))
}
