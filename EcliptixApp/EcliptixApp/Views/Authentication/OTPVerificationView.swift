import SwiftUI

struct OTPVerificationView: View {

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var authService: AuthenticationService

    @State private var otpDigits: [String] = Array(repeating: "", count: 6)
    @FocusState private var focusedIndex: Int?
    @State private var showError: Bool = false
    @State private var resendCountdown: Int = 60
    @State private var canResend: Bool = false

    private let mobileNumber: String
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(mobileNumber: String, authService: AuthenticationService) {
        self.mobileNumber = mobileNumber
        _authService = State(initialValue: authService)
    }

    var body: some View {
        NavigationStack {
            ZStack {

                backgroundColor
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 32) {
                        headerSection

                        otpInputSection

                        verifyButton

                        resendSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 60)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundColor(.primary)
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {
                    showError = false
                    authService.errorMessage = nil
                }
            } message: {
                Text(authService.errorMessage ?? "An error occurred")
            }
            .onReceive(timer) { _ in
                updateCountdown()
            }
            .onAppear {
                focusedIndex = 0
            }
        }
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }

    private var headerSection: some View {
        VStack(spacing: 16) {
            Circle()
                .fill(Color.blue.gradient)
                .frame(width: 80, height: 80)
                .overlay {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                }

            VStack(spacing: 8) {
                Text("Verification Code")
                    .font(.system(size: 28, weight: .bold))

                Text("Enter the 6-digit code sent to")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)

                Text(formatMobileNumber(mobileNumber))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
            }
        }
    }

    private var otpInputSection: some View {
        HStack(spacing: 12) {
            ForEach(0..<6, id: \.self) { index in
                OTPDigitField(
                    digit: $otpDigits[index],
                    isFocused: focusedIndex == index
                )
                .focused($focusedIndex, equals: index)
                .onChange(of: otpDigits[index]) { oldValue, newValue in
                    handleDigitChange(at: index, oldValue: oldValue, newValue: newValue)
                }
            }
        }
    }

    private var verifyButton: some View {
        Button {
            Task {
                await verifyOTP()
            }
        } label: {
            HStack {
                if authService.isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Text("Verify")
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(isVerifyEnabled ? Color.blue : Color.secondary.opacity(0.3))
            .foregroundColor(.white)
            .cornerRadius(16)
        }
        .disabled(!isVerifyEnabled || authService.isLoading)
    }

    private var resendSection: some View {
        VStack(spacing: 12) {
            if canResend {
                Button {
                    Task {
                        await resendOTP()
                    }
                } label: {
                    Text("Resend Code")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.blue)
                }
            } else {
                HStack(spacing: 4) {
                    Text("Resend code in")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)

                    Text("\(resendCountdown)s")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.blue)
                }
            }

            Button {
                dismiss()
            } label: {
                Text("Change mobile number")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var isVerifyEnabled: Bool {
        otpDigits.allSatisfy { !$0.isEmpty }
    }

    private var otpCode: String {
        otpDigits.joined()
    }

    private func handleDigitChange(at index: Int, oldValue: String, newValue: String) {
        if newValue.count > 1 {
            otpDigits[index] = String(newValue.last!)
        }

        if !newValue.isEmpty && index < 5 {
            focusedIndex = index + 1
        }

        if newValue.isEmpty && !oldValue.isEmpty && index > 0 {
            focusedIndex = index - 1
        }

        if otpDigits.allSatisfy({ !$0.isEmpty }) {
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                await verifyOTP()
            }
        }
    }

    private func verifyOTP() async {
        focusedIndex = nil

        let result = await authService.verifyOTP(code: otpCode)

        switch result {
        case .success:
            break
        case .failure:
            showError = true
            clearOTP()
        }
    }

    private func resendOTP() async {
        resendCountdown = 60
        canResend = false

        clearOTP()

        let result = await authService.resendOTP(mobileNumber: mobileNumber)

        switch result {
        case .success:
            break
        case .failure:
            showError = true
        }
    }

    private func clearOTP() {
        otpDigits = Array(repeating: "", count: 6)
        focusedIndex = 0
    }

    private func updateCountdown() {
        if resendCountdown > 0 {
            resendCountdown -= 1
        } else {
            canResend = true
        }
    }

    private func formatMobileNumber(_ number: String) -> String {
        guard number.count >= 10 else { return number }

        let areaCode = number.prefix(3)
        let middleDigits = number.dropFirst(3).prefix(3)
        let lastDigits = number.dropFirst(6).prefix(4)

        return "+1 (\(areaCode)) \(middleDigits)-\(lastDigits)"
    }
}

private struct OTPDigitField: View {
    @Binding var digit: String
    let isFocused: Bool

    var body: some View {
        TextField("", text: $digit)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .font(.system(size: 24, weight: .semibold))
            .frame(width: 50, height: 60)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(strokeColor, lineWidth: 2)
            )
    }

    private var strokeColor: Color {
        if !digit.isEmpty {
            return .blue
        } else if isFocused {
            return .blue.opacity(0.5)
        } else {
            return .clear
        }
    }
}

#Preview {
    Text("OTPVerificationView Preview")
}
