import SwiftUI

public struct ConnectivityBannerModifier: ViewModifier {

    @ObservedObject var notification: ConnectivityNotification

    public func body(content: Content) -> some View {
        ZStack(alignment: .top) {

            content

            ConnectivityNotificationView(notification: notification)
                .zIndex(999)
        }
    }

    public init(notification: ConnectivityNotification) {
        self.notification = notification
    }
}

public extension View {

    func connectivityBanner(notification: ConnectivityNotification) -> some View {
        modifier(ConnectivityBannerModifier(notification: notification))
    }

    func connectivityBanner(
        connectivityService: ConnectivityService,
        localization: LocalizationService
    ) -> some View {
        let notification = ConnectivityNotification(
            connectivityService: connectivityService,
            localization: localization
        )
        return modifier(ConnectivityBannerModifier(notification: notification))
    }
}

private struct ConnectivityServiceKey: EnvironmentKey {
    static let defaultValue: ConnectivityService? = nil
}

private struct LocalizationServiceKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: LocalizationService? = nil
}

public extension EnvironmentValues {
    var connectivityService: ConnectivityService? {
        get { self[ConnectivityServiceKey.self] }
        set { self[ConnectivityServiceKey.self] = newValue }
    }

    var localizationService: LocalizationService? {
        get { self[LocalizationServiceKey.self] }
        set { self[LocalizationServiceKey.self] = newValue }
    }
}

public extension View {

    func connectivityService(_ service: ConnectivityService) -> some View {
        environment(\.connectivityService, service)
    }

    func localizationService(_ service: LocalizationService) -> some View {
        environment(\.localizationService, service)
    }
}

public struct AutoConnectivityBanner: ViewModifier {

    @Environment(\.connectivityService) private var connectivityService
    @Environment(\.localizationService) private var localizationService
    @StateObject private var notification: ConnectivityNotification

    public init() {
        let connectivity = DefaultConnectivityService()
        let localization = DefaultLocalizationService()

        _notification = StateObject(wrappedValue: ConnectivityNotification(
            connectivityService: connectivity,
            localization: localization
        ))
    }

    public func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content

            if let connectivity = connectivityService,
               let localization = localizationService {
                ConnectivityNotificationView(
                    notification: ConnectivityNotification(
                        connectivityService: connectivity,
                        localization: localization
                    )
                )
                .zIndex(999)
            } else {

                ConnectivityNotificationView(notification: notification)
                    .zIndex(999)
            }
        }
    }
}

public extension View {

    func autoConnectivityBanner() -> some View {
        modifier(AutoConnectivityBanner())
    }
}
