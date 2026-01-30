import SwiftUI

struct AddEditXPView: View {
    enum Mode {
        case add
        case edit(XP)

        var title: String {
            switch self {
            case .add: return "New XP"
            case .edit: return "Edit XP"
            }
        }
    }

    let mode: Mode
    @EnvironmentObject var xpManager: XPManager
    @Environment(\.dismiss) private var dismiss

    @State private var keyword: String = ""
    @State private var richTextAttributedString: NSAttributedString = NSAttributedString()
    @State private var outputPlainText: Bool = false
    @State private var tags: [String] = []
    @State private var newTag: String = ""
    @State private var folder: String = ""
    @State private var showingFolderPicker: Bool = false

    @State private var showingError: Bool = false
    @State private var errorMessage: String = ""

    init(mode: Mode) {
        self.mode = mode

        switch mode {
        case .add:
            break
        case .edit(let xp):
            _keyword = State(initialValue: xp.keyword)
            _outputPlainText = State(initialValue: xp.outputPlainText)
            _tags = State(initialValue: xp.tags)
            _folder = State(initialValue: xp.folder ?? "")

            // Load rich text data if available, otherwise convert plain text
            if xp.isRichText, let attributedStr = xp.attributedString {
                _richTextAttributedString = State(initialValue: attributedStr)
            } else {
                _richTextAttributedString = State(initialValue: XP.makeAttributedString(from: xp.expansion))
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(mode.title)
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
            }
            .padding()

            Divider()

            // Form
            Form {
                Section("Keyword") {
                    TextField("e.g., xintro", text: $keyword)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: keyword) { newValue in
                            // Strip spaces - they're not allowed in keywords
                            let noSpaces = newValue.replacingOccurrences(of: " ", with: "")
                            if noSpaces != newValue {
                                keyword = noSpaces
                            }
                        }

                    if hasKeywordConflict {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("This keyword is already in use")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }

                Section("Expansion") {
                    RichTextEditorWithToolbar(attributedString: $richTextAttributedString)
                        .frame(minHeight: 150)
                }

                Section("Organization") {
                    // Tags
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tags")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            TextField("Add tag", text: $newTag, onCommit: addTag)
                                .textFieldStyle(.roundedBorder)

                            Button("Add") {
                                addTag()
                            }
                            .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                        }

                        if !tags.isEmpty {
                            FlowLayout(spacing: 6) {
                                ForEach(tags, id: \.self) { tag in
                                    HStack(spacing: 4) {
                                        Text(tag)
                                            .font(.caption)
                                        Button(action: { removeTag(tag) }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.2))
                                    .cornerRadius(8)
                                }
                            }
                        }
                    }

                    // Folder
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Folder")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            if !xpManager.allFolders.isEmpty {
                                Menu {
                                    Button("None") {
                                        folder = ""
                                    }
                                    Divider()
                                    ForEach(xpManager.allFolders, id: \.self) { existingFolder in
                                        Button(existingFolder) {
                                            folder = existingFolder
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(folder.isEmpty ? "Select folder..." : folder)
                                        Image(systemName: "chevron.down")
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Text("or")
                                    .foregroundColor(.secondary)
                            }

                            TextField("New folder name", text: $folder)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button(mode.title == "New XP" ? "Create" : "Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 500, height: 600)
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    private var isValid: Bool {
        let hasKeyword = !keyword.trimmingCharacters(in: .whitespaces).isEmpty
        let hasContent = !richTextAttributedString.string.trimmingCharacters(in: .whitespaces).isEmpty
        return hasKeyword && hasContent
    }

    private var hasKeywordConflict: Bool {
        guard !keyword.isEmpty else { return false }

        let lowercaseKeyword = keyword.lowercased()

        // Check if this keyword would create any conflicts
        for xp in xpManager.xps {
            let otherKeyword = xp.keyword.lowercased()

            // Skip comparing with itself in edit mode
            if case .edit(let originalXP) = mode, xp.id == originalXP.id {
                continue
            }

            // Check for exact match
            if otherKeyword == lowercaseKeyword {
                return true
            }

            // Check if one is a prefix of the other
            if lowercaseKeyword.hasPrefix(otherKeyword) || otherKeyword.hasPrefix(lowercaseKeyword) {
                return true
            }
        }

        return false
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

    private func save() {
        guard isValid else { return }

        if hasKeywordConflict {
            errorMessage = "This keyword is already in use. Please choose a different keyword."
            showingError = true
            return
        }

        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespaces)
        let trimmedFolder = folder.trimmingCharacters(in: .whitespaces)

        // Always save as rich text
        let expansionText = richTextAttributedString.string
        let richTextData = XP.makeRichTextData(from: richTextAttributedString)

        switch mode {
        case .add:
            let newXP = XP(
                keyword: trimmedKeyword,
                expansion: expansionText,
                isRichText: true,
                richTextData: richTextData,
                outputPlainText: outputPlainText,
                tags: tags,
                folder: trimmedFolder.isEmpty ? nil : trimmedFolder
            )
            xpManager.add(newXP)

        case .edit(let originalXP):
            var updatedXP = originalXP
            updatedXP.keyword = trimmedKeyword
            updatedXP.expansion = expansionText
            updatedXP.isRichText = true
            updatedXP.richTextData = richTextData
            updatedXP.outputPlainText = outputPlainText
            updatedXP.tags = tags
            updatedXP.folder = trimmedFolder.isEmpty ? nil : trimmedFolder
            xpManager.update(updatedXP)
        }

        dismiss()
    }
}
