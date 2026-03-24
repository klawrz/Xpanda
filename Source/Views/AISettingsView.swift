import SwiftUI

struct AISettingsView: View {
    @EnvironmentObject var xpManager: XPManager
    @ObservedObject private var authManager = AuthManager.shared
    @State private var customPrompt: String = LLMRephraseService.shared.customSystemPrompt ?? ""
    @State private var showingPaywall = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Account
                VStack(alignment: .leading, spacing: 8) {
                    Text("Account")
                        .font(.headline)

                    if authManager.isSignedIn {
                        HStack(spacing: 10) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.title2)
                                .foregroundColor(.secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                if let name = authManager.displayName, !name.isEmpty {
                                    Text(name).font(.body)
                                }
                                if let email = authManager.email, !email.isEmpty {
                                    Text(email)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Baeside Account")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            Button("Sign Out") { authManager.signOut() }
                                .foregroundColor(.red)
                        }
                        .padding(10)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)

                        // Subscription status
                        HStack(spacing: 10) {
                            Image(systemName: authManager.isSubscribed ? "checkmark.seal.fill" : "lock.fill")
                                .foregroundColor(authManager.isSubscribed ? .green : .orange)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(authManager.isSubscribed ? "Subscribed" : "Free Plan")
                                    .font(.body)
                                    .fontWeight(.medium)
                                Text(authManager.isSubscribed
                                     ? "AI rephrasing is active."
                                     : "Upgrade to unlock AI rephrasing.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if !authManager.isSubscribed {
                                Button("Upgrade") { showingPaywall = true }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.orange)
                            }
                        }
                        .padding(10)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    } else {
                        Text("Not signed in.")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                // Custom Instructions
                VStack(alignment: .leading, spacing: 8) {
                    Text("Custom Instructions")
                        .font(.headline)

                    TextEditor(text: $customPrompt)
                        .frame(height: 80)
                        .font(.body)
                        .padding(4)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                        .onChange(of: customPrompt) { newValue in
                            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            LLMRephraseService.shared.customSystemPrompt = trimmed.isEmpty ? nil : trimmed
                        }

                    Text("Optional. Added to the default rephrase prompt as additional instructions.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(20)
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
                .environmentObject(authManager)
        }
    }
}
