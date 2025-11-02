import EcliptixCore
import SwiftUI

struct RootView: View {
    let stateManager: ApplicationStateManager
    let router: ApplicationRouter

    var body: some View {
        Group {
            router.viewForDestination()
        }
        .animation(.easeInOut, value: router.currentDestination)
        .task {
            for await state in stateManager.stateChanges.values {
                await router.handleStateChange(state)
            }
        }
    }
}

#Preview {
    let manager = ApplicationStateManager()
    RootView(
        stateManager: manager,
        router: ApplicationRouter(stateManager: manager)
    )
}
