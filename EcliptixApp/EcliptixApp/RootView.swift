import SwiftUI
import EcliptixCore
import EcliptixAuthentication

struct RootView: View {
    @EnvironmentObject var authStateManager: AuthenticationStateManager

    var body: some View {
        Group {
            switch authStateManager.authenticationState {
            case .initializing:
                SplashView()
            case .anonymous:
                AuthenticationView()
            case .authenticated:
                MainView()
            }
        }
        .animation(.easeInOut, value: authStateManager.authenticationState)
    }
}

#Preview {
    RootView()
        .environmentObject(AuthenticationStateManager())
}
