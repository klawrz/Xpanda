import SwiftUI

struct XPDetailView: View {
    let xp: XP
    @EnvironmentObject var xpManager: XPManager

    @State private var keyword: String
    @State private var richTextAttributedString: NSAttributedString
    @State private var outputPlainText: Bool
    @State private var tags: [String]
    @State private var folder: String
    @State private var newTag: String = ""
    @State private var showingReferences = false

    @State private var saveTask: Task<Void, Never>?

    init(xp: XP) {
        self.xp = xp
        _keyword = State(initialValue: xp.keyword)
        _outputPlainText = State(initialValue: xp.outputPlainText)
        _tags = State(initialValue: xp.tags)
        _folder = State(initialValue: xp.folder ?? "")

        // Load rich text data if available, otherwise convert plain text
        if xp.isRichText, let attributedStr = xp.attributedString {
            _richTextAttributedString = State(initialValue: attributedStr)
        } else {
            // Convert plain text to attributed string with proper formatting
            _richTextAttributedString = State(initialValue: XP.makeAttributedString(from: xp.expansion))
        }
    }

    var hasConflict: Bool {
        guard !keyword.isEmpty else { return false }
        return xpManager.conflictingKeywords[keyword.lowercased()] != nil
    }

    var conflictingKeywords: [String] {
        guard !keyword.isEmpty else { return [] }
        return xpManager.getConflictingKeywords(for: keyword)
    }

    var conflictMessage: String {
        if conflictingKeywords.isEmpty {
            return "This keyword conflicts with another XP"
        } else if conflictingKeywords.count == 1 {
            return "Conflicts with: \(conflictingKeywords[0])"
        } else {
            return "Conflicts with: \(conflictingKeywords.joined(separator: ", "))"
        }
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
                        // Show % prefix as non-editable for variables
                        if xp.isVariable {
                            Text("%")
                                .font(.title)
                                .bold()
                                .foregroundColor(Color(red: 0.3, green: 0.8, blue: 0.4))
                        }

                        TextField("Keyword", text: Binding(
                            get: {
                                // Remove % prefix for display if it's a variable
                                if xp.isVariable && keyword.hasPrefix("%") {
                                    return String(keyword.dropFirst())
                                }
                                return keyword
                            },
                            set: { newValue in
                                // Add % prefix back when saving if it's a variable
                                if xp.isVariable {
                                    keyword = "%" + newValue
                                } else {
                                    keyword = newValue
                                }
                            }
                        ))
                            .textFieldStyle(.plain)
                            .font(.title)
                            .bold()
                            .onChange(of: keyword) { _ in debouncedSave() }

                        if hasConflict {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .help(conflictMessage)
                        }
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                    // Show variable indicator if keyword starts with %
                    if keyword.hasPrefix("%") {
                        HStack(alignment: .top, spacing: 4) {
                            Image(systemName: "function")
                                .font(.caption)
                                .foregroundColor(Color(red: 0.3, green: 0.8, blue: 0.4))
                            Text("This is a Variable. Variable keywords are automatically preceded with %.")
                                .font(.caption)
                                .foregroundColor(Color(red: 0.3, green: 0.8, blue: 0.4))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 4)
                    }
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

                        Toggle("Output as Plain Text", isOn: $outputPlainText)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .help("Strip formatting when expanding (for JSON, code, etc.)")
                            .onChange(of: outputPlainText) { _ in debouncedSave() }
                    }

                    RichTextEditorWithToolbar(attributedString: $richTextAttributedString)
                        .frame(minHeight: 200)
                        .onChange(of: richTextAttributedString) { _ in debouncedSave() }
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

                // Variable Usage Section (only for variables)
                if xp.isVariable {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Usage")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)

                        let references = xpManager.findReferences(toVariable: xp)

                        if references.isEmpty {
                            Text("Not used in any XPs")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        } else {
                            HStack {
                                Text("Used in \(references.count) XP\(references.count == 1 ? "" : "s")")
                                    .font(.callout)
                                    .foregroundColor(Color(red: 0.3, green: 0.8, blue: 0.4))

                                Button(action: { showingReferences.toggle() }) {
                                    Image(systemName: showingReferences ? "chevron.up" : "chevron.down")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }

                            if showingReferences {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(references, id: \.id) { referencingXP in
                                        HStack {
                                            Text("• \(referencingXP.keyword)")
                                                .font(.callout)
                                                .foregroundColor(.primary)
                                            Spacer()
                                        }
                                        .padding(.vertical, 4)
                                        .padding(.horizontal, 8)
                                        .background(Color(NSColor.controlBackgroundColor))
                                        .cornerRadius(4)
                                    }
                                }
                                .padding(.top, 4)
                            }
                        }
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
        .background(xp.isVariable ? Color(red: 0.3, green: 0.8, blue: 0.4).opacity(0.08) : Color(white: 1.0, opacity: 0.03))
    }

    private var isValid: Bool {
        let hasKeyword = !keyword.trimmingCharacters(in: .whitespaces).isEmpty
        let hasContent = !richTextAttributedString.string.trimmingCharacters(in: .whitespaces).isEmpty
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
        // Always save, even if empty - let the user work
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespaces)
        let trimmedFolder = folder.trimmingCharacters(in: .whitespaces)

        // Always save as rich text
        let expansionText = richTextAttributedString.string
        let richTextData = XP.makeRichTextData(from: richTextAttributedString)

        // Auto-detect if this is a variable based on % prefix
        let isVariable = trimmedKeyword.hasPrefix("%")

        var updatedXP = xp
        updatedXP.keyword = trimmedKeyword
        updatedXP.expansion = expansionText
        updatedXP.isRichText = true
        updatedXP.richTextData = richTextData
        updatedXP.outputPlainText = outputPlainText
        updatedXP.isVariable = isVariable
        updatedXP.tags = tags
        updatedXP.folder = trimmedFolder.isEmpty ? nil : trimmedFolder

        xpManager.update(updatedXP)
    }
}
