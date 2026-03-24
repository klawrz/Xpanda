import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var xpManager: XPManager

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            AISettingsView()
                .tabItem {
                    Label("AI", systemImage: "sparkles")
                }

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 500, height: 400)
    }
}

struct GeneralSettingsView: View {
    @State private var expansionSoundEnabled = UserDefaults.standard.object(forKey: "expansionSoundEnabled") as? Bool ?? true
    @State private var phraseSuggestionsEnabled = PhraseSuggestionTracker.shared.isEnabled
    @State private var phraseSuggestionThreshold = PhraseSuggestionTracker.shared.suggestionThreshold

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Accessibility Permissions")
                        .font(.headline)

                    Text("Xpanda needs Accessibility permissions to monitor keyboard input and perform text expansions.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button("Open System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Storage Location")
                        .font(.headline)

                    let fileManager = FileManager.default
                    let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                    let appDirectory = appSupport.appendingPathComponent("Xpanda")

                    Text(appDirectory.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)

                    Button("Open in Finder") {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: appDirectory.path)
                    }
                }
                .padding(.vertical, 8)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sound")
                        .font(.headline)

                    Toggle("Play sound on expansion", isOn: $expansionSoundEnabled)
                        .onChange(of: expansionSoundEnabled) { newValue in
                            UserDefaults.standard.set(newValue, forKey: "expansionSoundEnabled")
                        }

                    Text("Plays the Pong sound each time an XP is expanded.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Phrase Suggestions")
                        .font(.headline)

                    Toggle("Suggest XPs for frequently typed phrases", isOn: $phraseSuggestionsEnabled)
                        .onChange(of: phraseSuggestionsEnabled) { newValue in
                            PhraseSuggestionTracker.shared.isEnabled = newValue
                        }

                    Text("When enabled, Xpanda detects phrases you type repeatedly and suggests creating an XP for them.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if phraseSuggestionsEnabled {
                        Stepper("Suggestion threshold: \(phraseSuggestionThreshold)", value: $phraseSuggestionThreshold, in: 2...10)
                            .onChange(of: phraseSuggestionThreshold) { newValue in
                                PhraseSuggestionTracker.shared.suggestionThreshold = newValue
                            }

                        Text("Number of times a phrase must be typed before suggesting an XP.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button("Clear Phrase History") {
                            PhraseSuggestionTracker.shared.clearAll()
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Close button row
            HStack {
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(12)

            // Main content
            VStack(spacing: 20) {
                // Panda branding
                Image("PandaLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)

                Text("Xpanda")
                    .font(.title)
                    .bold()

                Text("Version 1.0.0")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Your friendly text replacement system")
                    .font(.body)
                    .foregroundColor(.secondary)

                Spacer()

                VStack(spacing: 8) {
                    HStack {
                        Image("PandaLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                        Text("Powered by pandas and productivity")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text("Built by Baeside")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("© 2026 Baeside")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
        }
        .frame(width: 400, height: 400)
    }
}
