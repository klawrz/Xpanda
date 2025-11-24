import SwiftUI

struct XPDetailView: View {
    let xp: XP
    @EnvironmentObject var xpManager: XPManager

    @State private var keyword: String
    @State private var expansion: String
    @State private var isRichText: Bool
    @State private var richTextAttributedString: NSAttributedString
    @State private var tags: [String]
    @State private var folder: String
    @State private var newTag: String = ""

    @State private var saveTask: Task<Void, Never>?

    init(xp: XP) {
        self.xp = xp
        _keyword = State(initialValue: xp.keyword)
        _expansion = State(initialValue: xp.expansion)
        _isRichText = State(initialValue: xp.isRichText)
        _tags = State(initialValue: xp.tags)
        _folder = State(initialValue: xp.folder ?? "")

        // Load rich text data if available
        if xp.isRichText, let attributedStr = xp.attributedString {
            _richTextAttributedString = State(initialValue: attributedStr)
        } else {
            _richTextAttributedString = State(initialValue: NSAttributedString(string: xp.expansion))
        }
    }

    var hasConflict: Bool {
        guard !keyword.isEmpty else { return false }
        if let existingXP = xpManager.findXP(forKeyword: keyword) {
            return existingXP.id != xp.id
        }
        return false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Keyword Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Keyword")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    HStack {
                        TextField("Keyword", text: $keyword)
                            .textFieldStyle(.plain)
                            .font(.title)
                            .bold()
                            .onChange(of: keyword) { _ in debouncedSave() }

                        if hasConflict {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .help("This keyword conflicts with another XP")
                        }
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }

                Divider()

                // Expansion Section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Expansion")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)

                        Spacer()

                        Toggle("Rich Text", isOn: $isRichText)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .onChange(of: isRichText) { newValue in
                                if newValue {
                                    // Convert plain text to attributed string
                                    richTextAttributedString = NSAttributedString(string: expansion)
                                } else {
                                    // Convert attributed string to plain text
                                    expansion = richTextAttributedString.string
                                }
                                debouncedSave()
                            }
                    }

                    if isRichText {
                        VStack(spacing: 0) {
                            RichTextToolbar(textView: nil)
                            RichTextEditor(attributedString: $richTextAttributedString)
                                .frame(minHeight: 200)
                                .border(Color.secondary.opacity(0.2))
                                .onChange(of: richTextAttributedString) { _ in debouncedSave() }
                        }
                    } else {
                        TextEditor(text: $expansion)
                            .frame(minHeight: 200)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(8)
                            .border(Color.secondary.opacity(0.2), width: 1)
                            .onChange(of: expansion) { _ in debouncedSave() }
                    }
                }

                Divider()

                // Tags Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tags")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    HStack {
                        TextField("Add tag", text: $newTag, onCommit: addTag)
                            .textFieldStyle(.roundedBorder)

                        Button("Add") {
                            addTag()
                            debouncedSave()
                        }
                        .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    if !tags.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(tags, id: \.self) { tag in
                                HStack(spacing: 4) {
                                    Text(tag)
                                        .font(.callout)
                                    Button(action: {
                                        removeTag(tag)
                                        debouncedSave()
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(8)
                            }
                        }
                    }
                }

                Divider()

                // Folder Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Folder")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    HStack {
                        if !xpManager.allFolders.isEmpty {
                            Menu {
                                Button("None") {
                                    folder = ""
                                    debouncedSave()
                                }
                                Divider()
                                ForEach(xpManager.allFolders, id: \.self) { existingFolder in
                                    Button(existingFolder) {
                                        folder = existingFolder
                                        debouncedSave()
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(folder.isEmpty ? "Select folder..." : folder)
                                        .foregroundColor(folder.isEmpty ? .secondary : .primary)
                                    Image(systemName: "chevron.down")
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Text("or")
                                .foregroundColor(.secondary)
                        }

                        TextField("New folder name", text: $folder)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: folder) { _ in debouncedSave() }
                    }
                }

                Divider()

                // Metadata
                VStack(alignment: .leading, spacing: 4) {
                    Text("Created: \(xp.dateCreated.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if xp.dateModified != xp.dateCreated {
                        Text("Modified: \(xp.dateModified.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Delete button
                Button("Delete XP") {
                    xpManager.delete(xp)
                }
                .foregroundColor(.red)
                .padding(.top, 8)

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isValid: Bool {
        let hasKeyword = !keyword.trimmingCharacters(in: .whitespaces).isEmpty
        let hasContent = isRichText ?
            !richTextAttributedString.string.trimmingCharacters(in: .whitespaces).isEmpty :
            !expansion.trimmingCharacters(in: .whitespaces).isEmpty
        return hasKeyword && hasContent
    }

    private func addTag() {
        let trimmedTag = newTag.trimmingCharacters(in: .whitespaces)
        guard !trimmedTag.isEmpty, !tags.contains(trimmedTag) else { return }
        tags.append(trimmedTag)
        newTag = ""
    }

    private func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }

    private func debouncedSave() {
        // Cancel previous save task
        saveTask?.cancel()

        // Create new save task with 0.5 second delay
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            // Check if task was cancelled
            guard !Task.isCancelled else { return }

            // Perform save on main thread
            await MainActor.run {
                saveChanges()
            }
        }
    }

    private func saveChanges() {
        guard isValid, !hasConflict else { return }

        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespaces)
        let trimmedFolder = folder.trimmingCharacters(in: .whitespaces)

        // Prepare expansion data based on format
        let expansionText: String
        let richTextData: Data?

        if isRichText {
            expansionText = richTextAttributedString.string
            richTextData = XP.makeRichTextData(from: richTextAttributedString)
        } else {
            expansionText = expansion.trimmingCharacters(in: .whitespaces)
            richTextData = nil
        }

        var updatedXP = xp
        updatedXP.keyword = trimmedKeyword
        updatedXP.expansion = expansionText
        updatedXP.isRichText = isRichText
        updatedXP.richTextData = richTextData
        updatedXP.tags = tags
        updatedXP.folder = trimmedFolder.isEmpty ? nil : trimmedFolder

        xpManager.update(updatedXP)
    }
}
