import SwiftUI

struct XPDetailView: View {
    let xp: XP
    let onEdit: () -> Void
    @EnvironmentObject var xpManager: XPManager

    var hasConflict: Bool {
        (xpManager.conflictingKeywords[xp.keyword.lowercased()]?.count ?? 0) > 1
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(xp.keyword)
                                .font(.title)
                                .bold()

                            if hasConflict {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .help("This keyword conflicts with another XP")
                            }
                        }

                        Text("Created: \(xp.dateCreated.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if xp.dateModified != xp.dateCreated {
                            Text("Modified: \(xp.dateModified.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Button(action: onEdit) {
                        Label("Edit", systemImage: "pencil")
                    }
                }

                Divider()

                // Expansion preview
                VStack(alignment: .leading, spacing: 8) {
                    Text("Expansion")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text(xp.expansion)
                        .font(.body)
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                }

                // Type indicator
                HStack {
                    Image(systemName: xp.isRichText ? "doc.richtext" : "doc.plaintext")
                    Text(xp.isRichText ? "Rich Text" : "Plain Text")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Tags
                if !xp.tags.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tags")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        FlowLayout(spacing: 6) {
                            ForEach(xp.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.callout)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.blue.opacity(0.2))
                                    .cornerRadius(8)
                            }
                        }
                    }
                }

                // Folder
                if let folder = xp.folder {
                    HStack {
                        Image(systemName: "folder")
                        Text("Folder:")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text(folder)
                            .font(.body)
                    }
                }

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
