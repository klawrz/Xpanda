import SwiftUI

struct AISettingsView: View {
    @State private var selectedProvider: LLMProviderType = LLMRephraseService.shared.selectedProvider
    @State private var apiKey: String = ""
    @State private var showAPIKey: Bool = false
    @State private var customPrompt: String = LLMRephraseService.shared.customSystemPrompt ?? ""
    @State private var keySaved: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // AI Provider
                VStack(alignment: .leading, spacing: 8) {
                    Text("AI Provider")
                        .font(.headline)

                    Menu {
                        ForEach(LLMProviderType.allCases, id: \.self) { provider in
                            Button(provider.rawValue) {
                                selectedProvider = provider
                                LLMRephraseService.shared.selectedProvider = provider
                                loadKeyForCurrentProvider()
                                keySaved = false
                            }
                        }
                    } label: {
                        Text(selectedProvider.rawValue)
                    }
                    .menuIndicator(.visible)
                    .frame(width: 140, alignment: .leading)
                }

                Divider()

                // API Key
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Key")
                        .font(.headline)

                    HStack(spacing: 8) {
                        HStack {
                            if showAPIKey {
                                TextField("Enter your \(selectedProvider.rawValue) API key", text: $apiKey)
                                    .textFieldStyle(.plain)
                            } else {
                                SecureField("Enter your \(selectedProvider.rawValue) API key", text: $apiKey)
                                    .textFieldStyle(.plain)
                            }

                            Button(action: { showAPIKey.toggle() }) {
                                Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(showAPIKey ? "Hide API key" : "Show API key")
                        }
                        .padding(8)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(8)

                        Button("Save") {
                            saveAPIKey()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if keySaved {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text("Key saved")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }

                    Text("Stored securely in the macOS Keychain.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if KeychainHelper.loadString(forKey: selectedProvider.keychainKey) != nil {
                        Button("Remove Key") {
                            KeychainHelper.delete(forKey: selectedProvider.keychainKey)
                            apiKey = ""
                            keySaved = false
                        }
                        .foregroundColor(.red)
                    }
                }

                Divider()

                // Custom Instructions
                VStack(alignment: .leading, spacing: 8) {
                    Text("Custom Instructions")
                        .font(.headline)

                    TextEditor(text: $customPrompt)
                        .frame(height: 60)
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
        .onAppear {
            loadKeyForCurrentProvider()
        }
    }

    private func loadKeyForCurrentProvider() {
        if let existingKey = KeychainHelper.loadString(forKey: selectedProvider.keychainKey) {
            apiKey = existingKey
        } else {
            apiKey = ""
        }
    }

    private func saveAPIKey() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }
        KeychainHelper.saveString(trimmedKey, forKey: selectedProvider.keychainKey)
        keySaved = true
    }
}
