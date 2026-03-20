import SwiftUI

// MARK: - AddEditAutocorrectView (sheet for creating/editing autocorrect entries)

struct AddEditAutocorrectView: View {
    enum Mode: Equatable {
        case add
        case edit(XP)

        var title: String {
            switch self {
            case .add: return "Add Autocorrect"
            case .edit: return "Edit Autocorrect"
            }
        }

        static func == (lhs: Mode, rhs: Mode) -> Bool {
            switch (lhs, rhs) {
            case (.add, .add): return true
            case (.edit(let a), .edit(let b)): return a.id == b.id
            default: return false
            }
        }
    }

    let mode: Mode
    @EnvironmentObject var xpManager: XPManager
    @Environment(\.dismiss) private var dismiss

    @State private var misspelling: String = ""
    @State private var correction: String = ""
    @State private var showingError = false
    @State private var errorMessage = ""

    init(mode: Mode) {
        self.mode = mode
        if case .edit(let xp) = mode {
            _misspelling = State(initialValue: xp.keyword)
            _correction = State(initialValue: xp.expansion)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(mode.title)
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Misspelling")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("", text: $misspelling)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: misspelling) { newValue in
                            misspelling = newValue.replacingOccurrences(of: " ", with: "")
                        }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Correction")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("", text: $correction)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: correction) { newValue in
                            correction = newValue.replacingOccurrences(of: " ", with: "")
                        }
                }
            }
            .padding()

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(mode == .add ? "Create" : "Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(misspelling.isEmpty || correction.isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 280)
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    private func save() {
        let keyword = misspelling.trimmingCharacters(in: .whitespaces)
        let expansion = correction.trimmingCharacters(in: .whitespaces)

        guard !keyword.isEmpty, !expansion.isEmpty else { return }

        // Check for keyword conflicts with existing non-autocorrect entries
        if case .add = mode {
            let conflict = xpManager.xps.first { $0.keyword.lowercased() == keyword.lowercased() && !$0.isAutocorrect }
            if let conflict = conflict {
                errorMessage = "\"\(keyword)\" is already used as a keyword for \"\(conflict.expansion.prefix(30))\""
                showingError = true
                return
            }
        }

        switch mode {
        case .add:
            let newXP = XP(
                keyword: keyword,
                expansion: expansion,
                isRichText: false,
                isAutocorrect: true,
                tags: [],
                folder: nil
            )
            xpManager.add(newXP)
        case .edit(let xp):
            var updated = xp
            updated.keyword = keyword
            updated.expansion = expansion
            updated.dateModified = Date()
            xpManager.update(updated)
        }

        dismiss()
    }
}
