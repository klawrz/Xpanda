import SwiftUI

struct ImportView: View {
    @EnvironmentObject var xpManager: XPManager
    @Environment(\.dismiss) private var dismiss

    @State private var importMode: ImportMode = .merge
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccess = false

    enum ImportMode {
        case merge
        case replace
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Import XPs")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
            }
            .padding()

            Divider()

            VStack(spacing: 20) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)

                Text("Import XPs from a file")
                    .font(.title3)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Import Mode")
                        .font(.headline)

                    Picker("Import Mode", selection: $importMode) {
                        Text("Merge with existing XPs").tag(ImportMode.merge)
                        Text("Replace all XPs").tag(ImportMode.replace)
                    }
                    .pickerStyle(.radioGroup)

                    Text(importMode == .merge ?
                         "New XPs will be added to your existing collection. Duplicates will be skipped." :
                         "All existing XPs will be deleted and replaced with imported ones.")
                        .font(.caption)
                        .foregroundColor(importMode == .replace ? .orange : .secondary)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                Button(action: selectFile) {
                    Label("Choose File...", systemImage: "doc")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if importMode == .replace {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Warning: This will delete all your existing XPs")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 500, height: 400)
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .alert("Success", isPresented: $showingSuccess) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("XPs imported successfully")
        }
    }

    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.json]
        panel.message = "Select an XP export file"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                importFile(from: url)
            }
        }
    }

    private func importFile(from url: URL) {
        do {
            try xpManager.importXPs(from: url, merge: importMode == .merge)
            showingSuccess = true
        } catch {
            errorMessage = "Failed to import XPs: \(error.localizedDescription)"
            showingError = true
        }
    }
}
