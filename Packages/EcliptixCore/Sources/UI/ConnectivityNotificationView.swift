import SwiftUI

public struct ConnectivityNotificationView: View {

    @ObservedObject var notification: ConnectivityNotification

    public var body: some View {
        VStack(spacing: 0) {
            if notification.isVisible {
                bannerContent
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: notification.isVisible)
            }
        }
    }

    private var bannerContent: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {

                Image(systemName: notification.icon)
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 4) {

                    Text(notification.title)
                        .font(.headline)
                        .foregroundColor(.white)

                    Text(notification.message)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)

                    if notification.retryCountdown > 0 {
                        Text("Retrying in \(notification.retryCountdown)s...")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.top, 4)
                    }
                }

                Spacer()

                Button {
                    Task {
                        await notification.dismissCommand.execute()
                        notification.dismiss()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(8)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            if notification.showRetryButton {
                Divider()
                    .background(Color.white.opacity(0.3))

                Button {
                    Task {
                        await notification.retryCommand.execute()
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text(notification.retryButtonTitle)
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .disabled(!notification.retryCommand.canExecute)
                .opacity(notification.retryCommand.canExecute ? 1.0 : 0.5)
            }
        }
        .background(backgroundColor)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var backgroundColor: Color {
        notification.type.color
    }

    public init(notification: ConnectivityNotification) {
        self.notification = notification
    }
}

#if DEBUG
struct ConnectivityNotificationView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {

            ConnectivityNotificationView(
                notification: makePreviewNotification(
                    isVisible: true,
                    title: "No Internet Connection",
                    message: "Please check your network settings and try again.",
                    type: .warning
                )
            )

            ConnectivityNotificationView(
                notification: makePreviewNotification(
                    isVisible: true,
                    title: "Retries Exhausted",
                    message: "Connection failed after 5 attempts. Please try again manually.",
                    type: .error,
                    showRetry: true
                )
            )

            ConnectivityNotificationView(
                notification: makePreviewNotification(
                    isVisible: true,
                    title: "Connected",
                    message: "Successfully connected to server.",
                    type: .success
                )
            )

            Spacer()
        }
        .background(Color.gray.opacity(0.1))
    }

    static func makePreviewNotification(
        isVisible: Bool,
        title: String,
        message: String,
        type: ConnectivityNotification.NotificationType,
        showRetry: Bool = false
    ) -> ConnectivityNotification {
        let connectivityService = DefaultConnectivityService()
        let localization = DefaultLocalizationService()
        let notification = ConnectivityNotification(
            connectivityService: connectivityService,
            localization: localization
        )

        return notification
    }
}
#endif
