import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var xpManager: XPManager

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 500, height: 300)
    }
}

struct GeneralSettingsView: View {
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
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header with close button
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
            .padding(.top, 16)
            .padding(.trailing, 16)

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

                Text("Your friendly text expander")
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

                    Text("© 2024 Xpanda")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom)
            }
            .padding(.horizontal)
        }
        .frame(width: 400, height: 350)
    }
}
