import EcliptixCore
import Foundation
import Observation
import SwiftUI

public enum NavigationDestination: Equatable {
    case splash
    case authentication
    case main
}

@MainActor
@Observable
public final class ApplicationRouter {

    public private(set) var currentDestination: NavigationDestination = .splash

    public var navigationPath = NavigationPath()

    private let stateManager: ApplicationStateManager

    public init(stateManager: ApplicationStateManager) {
        self.stateManager = stateManager
        Log.debug("[ApplicationRouter] Initialized")
    }

    public func navigateToAuthentication() async {
        Log.info("[ApplicationRouter] Navigating to Authentication")
        withAnimation(.easeInOut(duration: 0.3)) {
            currentDestination = .authentication
            navigationPath = NavigationPath()
        }
    }

    public func navigateToMain() async {
        Log.info("[ApplicationRouter] Navigating to Main")
        withAnimation(.easeInOut(duration: 0.3)) {
            currentDestination = .main
            navigationPath = NavigationPath()
        }
    }

    public func transitionFromSplash(isAuthenticated: Bool) async {
        Log.info("[ApplicationRouter] Transitioning from Splash. Authenticated: \(isAuthenticated)")

        try? await Task.sleep(nanoseconds: 500_000_000)

        if isAuthenticated {
            await navigateToMain()
        } else {
            await navigateToAuthentication()
        }
    }

    public func handleStateChange(_ state: ApplicationState) async {
        Log.info("[ApplicationRouter] Handling state change: \(state)")

        switch state {
        case .initializing:

            withAnimation(.easeInOut(duration: 0.3)) {
                currentDestination = .splash
            }

        case .anonymous:

            await navigateToAuthentication()

        case .authenticated:

            await navigateToMain()
        }
    }

    public func navigateBack() {
        Log.debug("[ApplicationRouter] Navigating back")
        if !navigationPath.isEmpty {
            navigationPath.removeLast()
        }
    }

    public func popToRoot() {
        Log.debug("[ApplicationRouter] Popping to root")
        navigationPath = NavigationPath()
    }

    public func reset() {
        Log.info("[ApplicationRouter] Resetting router")
        withAnimation(.easeInOut(duration: 0.3)) {
            currentDestination = .splash
            navigationPath = NavigationPath()
        }
    }
}

public extension ApplicationRouter {

    var isOnSplash: Bool {
        currentDestination == .splash
    }

    var isOnAuthentication: Bool {
        currentDestination == .authentication
    }

    var isOnMain: Bool {
        currentDestination == .main
    }

    @ViewBuilder
    func viewForDestination() -> some View {
        switch currentDestination {
        case .splash:
            SplashView()
                .transition(.opacity)

        case .authentication:
            AuthenticationView()
                .transition(.move(edge: .trailing).combined(with: .opacity))

        case .main:
            MainView()
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
}

public struct RouterView: View {
    @State var router: ApplicationRouter

    public init(router: ApplicationRouter) {
        _router = State(wrappedValue: router)
    }

    public var body: some View {
        router.viewForDestination()
            .animation(SwiftUI.Animation.easeInOut, value: router.currentDestination)
    }
}
