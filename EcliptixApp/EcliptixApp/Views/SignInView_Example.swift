import EcliptixCore
import EcliptixNetworking
import EcliptixSecurity
import SwiftUI

struct SignInView: View {
    @State private var authService: AuthenticationService
    @State private var mobileNumber: String = ""
    @State private var secureKey: String = ""
    init(authService: AuthenticationService) {
        self._authService = State(initialValue: authService)
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)

                    Text("Sign In to Ecliptix")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                .padding(.top, 40)

                VStack(spacing: 16) {
                    TextField("Mobile Number", text: $mobileNumber)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                        .textFieldStyle(.roundedBorder)
                        .disabled(authService.isLoading)

                    SecureField("Secure Key", text: $secureKey)
                        .textContentType(.password)
                        .textFieldStyle(.roundedBorder)
                        .disabled(authService.isLoading)
                }
                .padding(.horizontal)

                if let error = authService.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

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
    private var canSignIn: Bool {
        !mobileNumber.isEmpty && !secureKey.isEmpty
    }
    private func signIn() async {
        let result = await authService.signIn(
            mobileNumber: mobileNumber,
            secureKey: secureKey
        )

        if case .success = result {
            Log.info("[SignInView] Sign in successful")
        }
    }
}
#Preview {
    Text("SignInView Preview")
}
