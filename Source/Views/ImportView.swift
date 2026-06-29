import SwiftUI
import UniformTypeIdentifiers
import Darwin

struct ImportView: View {
    @EnvironmentObject var xpManager: XPManager
    @Environment(\.dismiss) private var dismiss

    @State private var importMode: ImportMode = .merge
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccess = false
    @State private var isTargeted = false
    @State private var pendingFileURL: URL?

    enum ImportMode {
        case merge
        case replace
    }

    var previousVersionURL: URL? {
        // getpwuid bypasses the sandbox to give the real home directory,
        // unlike NSHomeDirectory() which returns the container path.
        guard let pw = getpwuid(getuid()), let homeCStr = pw.pointee.pw_dir else { return nil }
        let url = URL(fileURLWithPath: String(cString: homeCStr))
            .appendingPathComponent("Library/Application Support/Xpanda/xpanda_data.json")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
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

            VStack(spacing: 16) {
                // Previous version migration
                if let prevURL = previousVersionURL {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.title2)
                            .foregroundColor(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Previous version data found")
                                .font(.headline)
                            Text("Import XPs from your previous Xpanda install")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Import") {
                            pendingFileURL = prevURL
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.08))
                    .cornerRadius(10)

                    HStack {
                        VStack { Divider() }
                        Text("or import from file")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        VStack { Divider() }
                    }
                }

                // Drop zone
                VStack(spacing: 12) {
                    if let fileURL = pendingFileURL {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.blue)

                        Text(fileURL.lastPathComponent)
                            .font(.title3)
                            .fontWeight(.medium)

                        Text("Ready to \(importMode == .merge ? "merge" : "replace")")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 12) {
                            Button("Remove") {
                                pendingFileURL = nil
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)

                            Button("Import") {
                                importFile(from: fileURL)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                    } else {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 48))
                            .foregroundColor(isTargeted ? .white : .blue)

                        Text("Drag & drop a JSON file here")
                            .font(.title3)
                            .foregroundColor(isTargeted ? .white : .primary)

                        Text("Drag a JSON export file from Finder")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isTargeted ? Color.accentColor.opacity(0.2) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                            style: StrokeStyle(lineWidth: 2, dash: [8])
                        )
                )
                .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
                    handleDrop(providers)
                }

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
        .frame(width: 500, height: 560)
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

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

            if url.pathExtension.lowercased() == "json" {
                DispatchQueue.main.async {
                    pendingFileURL = url
                }
            } else {
                DispatchQueue.main.async {
                    errorMessage = "Only JSON files are supported."
                    showingError = true
                }
            }
        }

        return true
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
