import SwiftUI

struct MainView: View {
    @EnvironmentObject var authStateManager: AuthenticationStateManager

    var body: some View {
        NavigationStack {
            VStack {
                Spacer()

                VStack(spacing: 20) {
                    Image(systemName: "checkmark.shield.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 100)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.green, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Text("Welcome!")
                        .font(.system(size: 32, weight: .bold, design: .rounded))

                    Text("You are successfully authenticated")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                Button(action: handleLogout) {
                    Text("Logout")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 50)
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func handleLogout() {
        Task {
            await authStateManager.updateState(.anonymous)
        }
    }
}

#Preview {
    MainView()
        .environmentObject(AuthenticationStateManager())
}
