import SwiftUI

struct RegistrationView: View {
    let onBack: () -> Void

    @State private var mobileNumber = ""
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
                Text("Create Account")
                    .font(.system(size: 32, weight: .bold, design: .rounded))

                Text("Register with your mobile number")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }

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
            .padding(.horizontal, 32)
            .padding(.top, 20)

            Button(action: handleRegister) {
                HStack {
                    if isLoading {
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
                .opacity(canContinue ? 1.0 : 0.6)
            }
            .disabled(!canContinue || isLoading)
            .padding(.horizontal, 32)
            .padding(.top, 20)

            Spacer()
        }
        .padding(.top, 20)
    }

    private var canContinue: Bool {
        !mobileNumber.isEmpty
    }

    private func handleRegister() {
        isLoading = true
        // TODO: Implement registration logic
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isLoading = false
        }
    }
}

#Preview {
    RegistrationView(onBack: {})
}
