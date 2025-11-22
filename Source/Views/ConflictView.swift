import SwiftUI

struct ConflictView: View {
    @EnvironmentObject var xpManager: XPManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.title2)
                Text("Keyword Conflicts")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }
            .padding()

            Divider()

            if xpManager.conflictingKeywords.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                    Text("No Conflicts")
                        .font(.title2)
                    Text("All keywords are unique")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        Text("The following keywords are used in multiple XPs. Each keyword should be unique.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)

                        ForEach(Array(xpManager.conflictingKeywords.keys.sorted()), id: \.self) { keyword in
                            if let conflictingXPs = xpManager.conflictingKeywords[keyword] {
                                ConflictGroupView(keyword: keyword, xps: conflictingXPs)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(width: 600, height: 500)
    }
}

struct ConflictGroupView: View {
    let keyword: String
    let xps: [XP]
    @EnvironmentObject var xpManager: XPManager
    @State private var showingEditSheet = false
    @State private var xpToEdit: XP?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Keyword: \"\(keyword)\"")
                    .font(.headline)
                Text("(\(xps.count) conflicts)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(xps) { xp in
                    ConflictXPCard(xp: xp, onEdit: {
                        xpToEdit = xp
                        showingEditSheet = true
                    }, onDelete: {
                        xpManager.delete(xp)
                    })
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .sheet(isPresented: $showingEditSheet) {
            if let xp = xpToEdit {
                AddEditXPView(mode: .edit(xp))
                    .environmentObject(xpManager)
            }
        }
    }
}

struct ConflictXPCard: View {
    let xp: XP
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(xp.expansion)
                    .font(.body)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if !xp.tags.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "tag")
                                .font(.caption2)
                            Text(xp.tags.joined(separator: ", "))
                                .font(.caption2)
                        }
                        .foregroundColor(.secondary)
                    }

                    if let folder = xp.folder {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.caption2)
                            Text(folder)
                                .font(.caption2)
                        }
                        .foregroundColor(.secondary)
                    }
                }

                Text("Created: \(xp.dateCreated.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.bordered)
                .help("Edit this XP")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
                .help("Delete this XP")
            }
        }
        .padding()
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
    }
}
