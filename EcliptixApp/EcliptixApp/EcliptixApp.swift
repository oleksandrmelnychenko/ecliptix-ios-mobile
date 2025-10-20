import SwiftUI
import EcliptixCore
import EcliptixAuthentication

@main
struct EcliptixApp: App {
    @StateObject private var authStateManager = AuthenticationStateManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authStateManager)
        }
    }
}
