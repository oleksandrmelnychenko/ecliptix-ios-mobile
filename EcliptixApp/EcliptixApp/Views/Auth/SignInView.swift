import SwiftUI

struct SignInView: View {
    let onBack: () -> Void

    @State private var mobileNumber = ""
    @State private var secureKey = ""
    @State private var isLoading = false

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
                Text("Sign In")
                    .font(.system(size: 32, weight: .bold, design: .rounded))

                Text("Enter your credentials to continue")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mobile Number")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)

                    TextField("Enter mobile number", text: $mobileNumber)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Secure Key")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)

                    SecureField("Enter secure key", text: $secureKey)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                }

                Button(action: {}) {
                    Text("Forgot Password?")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.blue)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)

            Button(action: handleSignIn) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Sign In")
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
                .opacity(canSignIn ? 1.0 : 0.6)
            }
            .disabled(!canSignIn || isLoading)
            .padding(.horizontal, 32)
            .padding(.top, 20)

            Spacer()
        }
        .padding(.top, 20)
    }

    private var canSignIn: Bool {
        !mobileNumber.isEmpty && !secureKey.isEmpty
    }

    private func handleSignIn() {
        isLoading = true
        // TODO: Implement sign-in logic
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isLoading = false
        }
    }
}

#Preview {
    SignInView(onBack: {})
}
