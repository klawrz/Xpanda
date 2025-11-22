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
    @State private var expansion: String = ""
    @State private var isRichText: Bool = false
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
            _expansion = State(initialValue: xp.expansion)
            _isRichText = State(initialValue: xp.isRichText)
            _tags = State(initialValue: xp.tags)
            _folder = State(initialValue: xp.folder ?? "")
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
                    TextEditor(text: $expansion)
                        .frame(minHeight: 100)
                        .font(.body)
                        .border(Color.secondary.opacity(0.2))

                    Toggle("Use Rich Text", isOn: $isRichText)
                        .disabled(true) // Will be enabled in future version
                        .help("Rich text support coming soon")
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
        !keyword.trimmingCharacters(in: .whitespaces).isEmpty &&
        !expansion.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var hasKeywordConflict: Bool {
        guard !keyword.isEmpty else { return false }

        switch mode {
        case .add:
            return xpManager.findXP(forKeyword: keyword) != nil
        case .edit(let originalXP):
            if let existingXP = xpManager.findXP(forKeyword: keyword) {
                return existingXP.id != originalXP.id
            }
            return false
        }
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
        let trimmedExpansion = expansion.trimmingCharacters(in: .whitespaces)
        let trimmedFolder = folder.trimmingCharacters(in: .whitespaces)

        switch mode {
        case .add:
            let newXP = XP(
                keyword: trimmedKeyword,
                expansion: trimmedExpansion,
                isRichText: isRichText,
                tags: tags,
                folder: trimmedFolder.isEmpty ? nil : trimmedFolder
            )
            xpManager.add(newXP)

        case .edit(let originalXP):
            var updatedXP = originalXP
            updatedXP.keyword = trimmedKeyword
            updatedXP.expansion = trimmedExpansion
            updatedXP.isRichText = isRichText
            updatedXP.tags = tags
            updatedXP.folder = trimmedFolder.isEmpty ? nil : trimmedFolder
            xpManager.update(updatedXP)
        }

        dismiss()
    }
}
