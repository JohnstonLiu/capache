import Combine
import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var code = ""
    @State private var pendingEmail: String?
    @State private var isWorking = false
    @State private var resendAvailableAt = Date.distantPast
    @State private var now = Date()

    private let resendCooldownSeconds: TimeInterval = 30
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var resendSecondsRemaining: Int {
        max(0, Int(ceil(resendAvailableAt.timeIntervalSince(now))))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)

                    if pendingEmail != nil {
                        TextField("Code", text: $code)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.oneTimeCode)
                            .keyboardType(.numberPad)
                    }
                } footer: {
                    Text("Signing in is only needed for sync. Check your email for the code.")
                }

                if let message = auth.errorMessage {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task {
                            await submit()
                        }
                    } label: {
                        if isWorking {
                            ProgressView()
                        } else {
                            Text(pendingEmail == nil ? "Send Code" : "Verify Code")
                        }
                    }
                    .disabled(isWorking || (pendingEmail != nil && code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))

                    if pendingEmail != nil {
                        Button(resendSecondsRemaining > 0 ? "Resend Code in \(resendSecondsRemaining)s" : "Resend Code") {
                            Task {
                                await resendCode()
                            }
                        }
                        .disabled(isWorking || resendSecondsRemaining > 0)
                    }
                }
            }
            .navigationTitle("Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .onReceive(timer) { date in
                now = date
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func submit() async {
        isWorking = true
        defer { isWorking = false }

        if pendingEmail == nil {
            let success = await auth.sendCode(to: email)
            if success {
                pendingEmail = email
                resendAvailableAt = Date().addingTimeInterval(resendCooldownSeconds)
            } else if auth.errorMessage?.localizedCaseInsensitiveContains("rate limit") == true {
                resendAvailableAt = Date().addingTimeInterval(resendCooldownSeconds)
            }
        } else {
            if await auth.verifyCode(email: pendingEmail ?? email, token: code) {
                dismiss()
            }
        }
    }

    private func resendCode() async {
        guard let pendingEmail, resendSecondsRemaining == 0 else { return }

        isWorking = true
        defer { isWorking = false }

        let success = await auth.sendCode(to: pendingEmail)
        if success || auth.errorMessage?.localizedCaseInsensitiveContains("rate limit") == true {
            resendAvailableAt = Date().addingTimeInterval(resendCooldownSeconds)
        }
    }
}
