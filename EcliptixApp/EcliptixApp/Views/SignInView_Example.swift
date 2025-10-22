import SwiftUI
import EcliptixCore

// MARK: - Sign In View (Modern Service-Based Architecture)
/// Example showing how clean SwiftUI views are with service architecture
/// Compare this to ViewModel approach - much simpler!
struct SignInView: View {

    // MARK: - Dependencies
    @State private var authService: AuthenticationService

    // MARK: - Form State
    @State private var mobileNumber: String = ""
    @State private var secureKey: String = ""

    // MARK: - Initialization
    init(authService: AuthenticationService) {
        self._authService = State(initialValue: authService)
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)

                    Text("Sign In to Ecliptix")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                .padding(.top, 40)

                // Form Fields
                VStack(spacing: 16) {
                    // Mobile Number
                    TextField("Mobile Number", text: $mobileNumber)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                        .textFieldStyle(.roundedBorder)
                        .disabled(authService.isLoading)

                    // Secure Key
                    SecureField("Secure Key", text: $secureKey)
                        .textContentType(.password)
                        .textFieldStyle(.roundedBorder)
                        .disabled(authService.isLoading)
                }
                .padding(.horizontal)

                // Error Message
                if let error = authService.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Sign In Button
                Button {
                    Task {
                        await signIn()
                    }
                } label: {
                    if authService.isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Text("Sign In")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(canSignIn ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(10)
                .disabled(!canSignIn || authService.isLoading)
                .padding(.horizontal)

                // Registration Link
                Button {
                    authService.currentStep = .registration
                } label: {
                    Text("Don't have an account? Register")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
                .disabled(authService.isLoading)

                Spacer()
            }
            .navigationTitle("Ecliptix")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Computed Properties
    private var canSignIn: Bool {
        !mobileNumber.isEmpty && !secureKey.isEmpty
    }

    // MARK: - Actions
    private func signIn() async {
        let result = await authService.signIn(
            mobileNumber: mobileNumber,
            secureKey: secureKey
        )

        // Navigation handled by observing authService.currentStep
        if case .success = result {
            Log.info("[SignInView] Sign in successful")
        }
    }
}

// MARK: - Preview
#Preview {
    // Example setup for preview
    let networkProvider = NetworkProvider(
        channelManager: GRPCChannelManager(configuration: .default),
        retryPolicy: RetryPolicy()
    )

    let identityKeys = try! IdentityKeys.create(oneTimeKeyCount: 10).get()

    let authService = AuthenticationService(
        networkProvider: networkProvider,
        identityKeys: identityKeys
    )

    return SignInView(authService: authService)
}
