import SwiftUI

struct AuthenticationView: View {
    @State private var selectedTab: AuthTab = .welcome

    enum AuthTab {
        case welcome
        case signIn
        case register
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
                        onSignIn: { selectedTab = .signIn },
                        onRegister: { selectedTab = .register }
                    )
                case .signIn:
                    SignInView(onBack: { selectedTab = .welcome })
                case .register:
                    RegistrationView(onBack: { selectedTab = .welcome })
                }
            }
        }
    }
}

#Preview {
    AuthenticationView()
}
