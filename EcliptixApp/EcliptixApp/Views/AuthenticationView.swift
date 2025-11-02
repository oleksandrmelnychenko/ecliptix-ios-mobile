import SwiftUI

struct AuthenticationView: View {
    @Environment(\.welcomeService) private var welcomeService
    @Environment(\.signInService) private var signInService

    @State private var selectedTab: AuthTab = .welcome

    enum AuthTab {
        case welcome
        case signIn
        case register
        case forgotPassword
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                switch selectedTab {
                case .welcome:
                    WelcomeView(
                        service: welcomeService,
                        onSignIn: { selectedTab = .signIn },
                        onRegister: { selectedTab = .register }
                    )
                case .signIn:
                    SignInView(
                        service: signInService,
                        onBack: { selectedTab = .welcome },
                        onForgotPassword: { selectedTab = .forgotPassword }
                    )
                case .register:
                    RegistrationView(onBack: { selectedTab = .welcome })
                case .forgotPassword:
                    PasswordRecoveryView(onBack: { selectedTab = .signIn })
                }
            }
        }
    }
}

#Preview {
    AuthenticationView()
}
