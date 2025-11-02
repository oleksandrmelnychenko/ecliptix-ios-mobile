import SwiftUI

struct WelcomeView: View {
    @State private var service: WelcomeService
    let onSignIn: () -> Void
    let onRegister: () -> Void

    init(
        service: WelcomeService,
        onSignIn: @escaping () -> Void,
        onRegister: @escaping () -> Void
    ) {
        _service = State(initialValue: service)
        self.onSignIn = onSignIn
        self.onRegister = onRegister
    }

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.2), .purple.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 140, height: 140)

                    Image(systemName: "shield.checkered")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                Text(service.welcomeTitle)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                Text(service.welcomeTagline)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 16) {
                Button {
                    Task {
                        await performSignIn()
                    }
                } label: {
                    HStack {
                        if service.isSignInBusy {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Text(service.signInButtonText)
                                .font(.system(size: 18, weight: .semibold))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                }
                .disabled(!service.canNavigate)
                .opacity(service.canNavigate ? 1.0 : 0.6)

                Button {
                    Task {
                        await performCreateAccount()
                    }
                } label: {
                    HStack {
                        if service.isCreateAccountBusy {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.blue)
                        } else {
                            Text(service.createAccountButtonText)
                                .font(.system(size: 18, weight: .semibold))
                        }
                    }
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.white)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue, lineWidth: 2)
                    )
                }
                .disabled(!service.canNavigate)
                .opacity(service.canNavigate ? 1.0 : 0.6)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 50)
        }
        .padding()
    }

    private func performSignIn() async {
        let context = await service.navigateToSignIn()
        Log.info("[WelcomeView] Sign in navigation completed. Context: \(context)")
        onSignIn()
    }

    private func performCreateAccount() async {
        let context = await service.navigateToCreateAccount()
        Log.info("[WelcomeView] Create account navigation completed. Context: \(context)")
        onRegister()
    }
}

#Preview {
    Text("WelcomeView Preview")
}
