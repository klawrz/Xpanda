import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                // Branding
                VStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .cornerRadius(18)

                    Text("Xpanda")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Sign in to get started")
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                // Sign in with Apple
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    authManager.handleSignInWithApple(result: result)
                }
                .signInWithAppleButtonStyle(.white)
                .frame(width: 220, height: 44)
                .cornerRadius(8)

                Button("Continue without signing in") {
                    authManager.skipSignIn()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .font(.caption)
            }

            Spacer()

            Text("By signing in, you agree to our Terms of Service and Privacy Policy.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.bottom, 24)
        }
        .frame(width: 480, height: 520)
    }
}
