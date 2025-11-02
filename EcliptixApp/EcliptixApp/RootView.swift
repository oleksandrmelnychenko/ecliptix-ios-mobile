import EcliptixAuthentication
import EcliptixCore
import SwiftUI

struct RootView: View {
    @Environment(\.applicationStateManager) private var stateManager: ApplicationStateManager
    @Environment(\.applicationRouter) private var router: ApplicationRouter
    @StateObject private var connectivityService = DefaultConnectivityService()
    @StateObject private var localization = DefaultLocalizationService()
    @StateObject private var connectivityNotification: ConnectivityNotification

    init() {
        let sharedConnectivity = DefaultConnectivityService()
        let sharedLocalization = DefaultLocalizationService()

        _connectivityNotification = StateObject(
            wrappedValue: ConnectivityNotification(
                connectivityService: sharedConnectivity,
                localization: sharedLocalization
            )
        )

        _connectivityService = StateObject(wrappedValue: sharedConnectivity)
        _localization = StateObject(wrappedValue: sharedLocalization)
    }

    var body: some View {
        Group {
            router.viewForDestination()
        }
        .animation(.easeInOut, value: router.currentDestination)
        .connectivityBanner(notification: connectivityNotification)
        .connectivityService(connectivityService)
        .localizationService(localization)
        .task {
            for await state in stateManager.stateChanges.values {
                await router.handleStateChange(state)
            }
        }
    }
}

#Preview {
    RootView()
        .environmentObject(AuthenticationStateManager())
}
