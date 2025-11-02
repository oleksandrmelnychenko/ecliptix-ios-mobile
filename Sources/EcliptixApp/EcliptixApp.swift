import SwiftUI

@main
struct EcliptixApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .task {
                    await appState.initialize()
                }
        }
    }
}

@MainActor
class AppState: ObservableObject {
    @Published var currentScreen: Screen = .splash

    enum Screen {
        case splash
        case authentication
        case main
    }

    func initialize() async {
        print("[AppState] App initialized")
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        currentScreen = .authentication
    }

    func navigateToMain() {
        currentScreen = .main
    }

    func logout() {
        currentScreen = .authentication
    }
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            switch appState.currentScreen {
            case .splash:
                SplashView()
            case .authentication:
                AuthenticationView()
            case .main:
                MainView()
            }
        }
        .animation(.easeInOut, value: appState.currentScreen)
    }
}
