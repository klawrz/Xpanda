import SwiftUI

struct ContentView: View {
    @EnvironmentObject var xpManager: XPManager
    @State private var selectedXP: XP?
    @State private var showingConflicts = false
    @State private var showingImportExport = false
    @State private var scrollToNewXP: UUID?
    @State private var showingDeleteConfirmation = false
    @State private var xpToDelete: XP?

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
            // Sidebar
            VStack(spacing: 0) {
                // Search bar
                SearchBar(text: $xpManager.searchText)
                    .padding()

                // Filter section (folders/tags)
                if !xpManager.allTags.isEmpty || !xpManager.allFolders.isEmpty {
                    FilterSidebar()
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }

                // XP/Variable Filter Tabs
                HStack(spacing: 0) {
                    // XPs Tab with inline + button
                    Button(action: { xpManager.viewFilter = .xpsOnly }) {
                        HStack(spacing: 4) {
                            Text("XPs")
                            Spacer()
                            if xpManager.viewFilter == .xpsOnly {
                                Button(action: { addNewXP(isVariable: false) }) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 8)
                        .background(xpManager.viewFilter == .xpsOnly ? Color.gray.opacity(0.2) : Color.clear)
                        .foregroundColor(xpManager.viewFilter == .xpsOnly ? .primary : .secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // Variables Tab with inline + button
                    Button(action: { xpManager.viewFilter = .variablesOnly }) {
                        HStack(spacing: 4) {
                            Text("Variables")
                            Spacer()
                            if xpManager.viewFilter == .variablesOnly {
                                Button(action: { addNewXP(isVariable: true) }) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 8)
                        .background(xpManager.viewFilter == .variablesOnly ? Color(red: 0.3, green: 0.8, blue: 0.4).opacity(0.2) : Color.clear)
                        .foregroundColor(xpManager.viewFilter == .variablesOnly ? Color(red: 0.3, green: 0.8, blue: 0.4) : .secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(height: 32)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

                Divider()

                // XP List
                ScrollViewReader { proxy in
                    List(selection: $selectedXP) {
                        ForEach(xpManager.filteredXPs, id: \.id) { xp in
                            XPListRow(
                                xp: xp,
                                hasConflict: xpManager.conflictingKeywords[xp.keyword.lowercased()] != nil,
                                conflictingKeywords: xpManager.getConflictingKeywords(for: xp.keyword)
                            )
                            .tag(xp)
                                .contextMenu {
                                    Button("Delete", role: .destructive) {
                                        xpToDelete = xp
                                        showingDeleteConfirmation = true
                                    }
                                }
                        }
                    }
                    .onDeleteCommand {
                        if let xp = selectedXP {
                            xpToDelete = xp
                            showingDeleteConfirmation = true
                        }
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(xpManager.viewFilter == .variablesOnly ? .hidden : .visible)
                    .background(xpManager.viewFilter == .variablesOnly ? Color(red: 0.3, green: 0.8, blue: 0.4).opacity(0.1) : Color.clear)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        Color.clear.frame(height: 8)
                    }
                    .id(xpManager.xps.map { "\($0.id)-\($0.keyword)-\($0.dateModified)" }.joined())
                    .onChange(of: scrollToNewXP) { xpID in
                        // Only scroll when a new XP is created
                        if let id = xpID {
                            // Small delay to let the view render first
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation {
                                    proxy.scrollTo(id, anchor: .top)
                                }
                                // Reset after scrolling
                                scrollToNewXP = nil
                            }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 400)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack {
                        if xpManager.hasConflicts {
                            Button(action: { showingConflicts = true }) {
                                Label("View Conflicts", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                            }
                        }

                        Menu {
                            Button("Import XPs") {
                                showingImportExport = true
                            }
                            Button("Export XPs") {
                                exportXPs()
                            }
                        } label: {
                            Label("More", systemImage: "ellipsis.circle")
                        }
                    }
                }
            }
        } detail: {
            // Detail view - find the current version from the manager
            if let selectedID = selectedXP?.id,
               let currentXP = xpManager.xps.first(where: { $0.id == selectedID }) {
                XPDetailView(xp: currentXP)
                    .id(currentXP.id)
                    .navigationTitle("")
                    .toolbarBackground(.hidden, for: .windowToolbar)
            } else {
                VStack(spacing: 20) {
                    Image("PandaLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)

                    Text("Select an XP")
                        .font(.title2)
                        .foregroundColor(.primary)

                    Text("\(xpManager.xps.count) XPs total")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(white: 1.0, opacity: 0.03))
                .navigationTitle("")
                .toolbarBackground(.hidden, for: .windowToolbar)
            }
        }

            Divider()

            HStack(spacing: 8) {
                Image("PandaLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .padding(.leading, 12)

                ExperienceBar(progress: xpManager.progress)
            }
            .background(Color(red: 0.3, green: 0.1, blue: 0.5))
        }
        .sheet(isPresented: $showingConflicts) {
            ConflictView()
                .environmentObject(xpManager)
        }
        .sheet(isPresented: $showingImportExport) {
            ImportView()
                .environmentObject(xpManager)
        }
        .alert("Delete XP", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                xpToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let xp = xpToDelete {
                    if selectedXP?.id == xp.id {
                        selectedXP = nil
                    }
                    xpManager.delete(xp)
                    xpToDelete = nil
                }
            }
            .keyboardShortcut(.return, modifiers: [])
        } message: {
            if let xp = xpToDelete {
                Text("Are you sure you want to delete \"\(xp.keyword.isEmpty ? "(Untitled)" : xp.keyword)\"? This cannot be undone.")
            }
        }
    }

    private func exportXPs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "xpanda_export.json"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try xpManager.exportXPs(to: url)
                } catch {
                    print("Export failed: \(error)")
                }
            }
        }
    }

    private func addNewXP(isVariable: Bool) {
        // Create a blank XP or Variable
        let newXP = XP(
            keyword: isVariable ? "%" : "",
            expansion: "",
            isRichText: false,
            isVariable: isVariable,
            tags: [],
            folder: nil
        )

        // Add it to the manager
        xpManager.add(newXP)

        // Select it so the user can immediately edit it
        selectedXP = newXP

        // Trigger scroll to the new XP
        scrollToNewXP = newXP.id
    }
}

struct SearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search XPs...", text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.15))
        .cornerRadius(8)
    }
}

struct XPListRow: View {
    let xp: XP
    let hasConflict: Bool
    let conflictingKeywords: [String]

    var body: some View {
        HStack {
            // Variable icon indicator
            if xp.isVariable {
                Image(systemName: "function")
                    .font(.caption)
                    .foregroundColor(Color(red: 0.3, green: 0.8, blue: 0.4))
                    .frame(width: 20)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(xp.keyword.isEmpty ? "(Untitled)" : xp.keyword)
                        .font(.headline)
                        .foregroundColor(xp.keyword.isEmpty ? .secondary : .primary)
                    if hasConflict {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                            .help(conflictMessage)
                    }
                }

                if xp.previewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("(No content)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                        .lineLimit(1)
                } else {
                    PreviewWithPills(text: xp.previewText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                if !xp.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(xp.tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(4)
                        }
                        if xp.tags.count > 3 {
                            Text("+\(xp.tags.count - 3)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var conflictMessage: String {
        if conflictingKeywords.isEmpty {
            return "This keyword conflicts with another XP"
        } else if conflictingKeywords.count == 1 {
            return "Conflicts with: \(conflictingKeywords[0])"
        } else {
            return "Conflicts with: \(conflictingKeywords.joined(separator: ", "))"
        }
    }
}

struct FilterSidebar: View {
    @EnvironmentObject var xpManager: XPManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !xpManager.allFolders.isEmpty {
                Text("Folders")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(xpManager.allFolders, id: \.self) { folder in
                    Button(action: {
                        if xpManager.selectedFolder == folder {
                            xpManager.selectedFolder = nil
                        } else {
                            xpManager.selectedFolder = folder
                        }
                    }) {
                        HStack {
                            Image(systemName: "folder")
                            Text(folder)
                            Spacer()
                            if xpManager.selectedFolder == folder {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                }
            }

            if !xpManager.allTags.isEmpty {
                Text("Tags")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)

                FlowLayout(spacing: 4) {
                    ForEach(xpManager.allTags, id: \.self) { tag in
                        Button(action: {
                            if xpManager.selectedTags.contains(tag) {
                                xpManager.selectedTags.remove(tag)
                            } else {
                                xpManager.selectedTags.insert(tag)
                            }
                        }) {
                            Text(tag)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    xpManager.selectedTags.contains(tag) ?
                                    Color.blue : Color.secondary.opacity(0.2)
                                )
                                .foregroundColor(
                                    xpManager.selectedTags.contains(tag) ?
                                    .white : .primary
                                )
                                .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 12)
            }
        }
    }
}

// Simple flow layout for tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return CGSize(width: proposal.width ?? 0, height: result.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX,
                                     y: bounds.minY + result.frames[index].minY),
                         proposal: ProposedViewSize(result.frames[index].size))
        }
    }

    struct FlowResult {
        var frames: [CGRect] = []
        var height: CGFloat = 0

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                frames.append(CGRect(origin: CGPoint(x: currentX, y: currentY), size: size))
                currentX += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }

            height = currentY + lineHeight
        }
    }
}

// Preview view that shows grey pills for placeholders in sidebar
struct PreviewWithPills: View {
    let text: String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(components.enumerated()), id: \.offset) { _, component in
                if component.isPlaceholder {
                    Text(component.displayText)
                        .font(.caption2)
                        .foregroundColor(component.isVariable ? Color(red: 0.3, green: 0.8, blue: 0.4) : .gray)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(component.isVariable ? Color(red: 0.3, green: 0.8, blue: 0.4).opacity(0.2) : Color.gray.opacity(0.2))
                        .cornerRadius(3)
                } else {
                    Text(component.text)
                }
            }
        }
    }

    private var components: [TextComponent] {
        var result: [TextComponent] = []
        var remainingText = text

        while !remainingText.isEmpty {
            // Check if text starts with a fill-in token (pattern: {{fillin_single|label|defaultValue}})
            if remainingText.hasPrefix("{{fillin_single|") {
                if let endRange = remainingText.range(of: "}}") {
                    let tokenLength = remainingText.distance(from: remainingText.startIndex, to: endRange.upperBound)
                    let fullToken = String(remainingText.prefix(tokenLength))
                    result.append(TextComponent(text: fullToken, displayText: "single fill", isPlaceholder: true))
                    remainingText.removeFirst(tokenLength)
                    continue
                }
            }

            // Check if text starts with a multi-line fill-in token (pattern: {{fillin_multi|label|defaultValue}})
            if remainingText.hasPrefix("{{fillin_multi|") {
                if let endRange = remainingText.range(of: "}}") {
                    let tokenLength = remainingText.distance(from: remainingText.startIndex, to: endRange.upperBound)
                    let fullToken = String(remainingText.prefix(tokenLength))
                    result.append(TextComponent(text: fullToken, displayText: "multi fill", isPlaceholder: true))
                    remainingText.removeFirst(tokenLength)
                    continue
                }
            }

            // Check if text starts with a select fill-in token (pattern: {{fillin_select|label|option1,option2|defaultIndex}})
            if remainingText.hasPrefix("{{fillin_select|") {
                if let endRange = remainingText.range(of: "}}") {
                    let tokenLength = remainingText.distance(from: remainingText.startIndex, to: endRange.upperBound)
                    let fullToken = String(remainingText.prefix(tokenLength))
                    result.append(TextComponent(text: fullToken, displayText: "select fill", isPlaceholder: true))
                    remainingText.removeFirst(tokenLength)
                    continue
                }
            }

            // Check if text starts with a date token (pattern: {{date|format}})
            if remainingText.hasPrefix("{{date|") {
                if let endRange = remainingText.range(of: "}}") {
                    let tokenLength = remainingText.distance(from: remainingText.startIndex, to: endRange.upperBound)
                    let fullToken = String(remainingText.prefix(tokenLength))
                    result.append(TextComponent(text: fullToken, displayText: "date", isPlaceholder: true))
                    remainingText.removeFirst(tokenLength)
                    continue
                }
            }

            // Check if text starts with a time token (pattern: {{time|format}})
            if remainingText.hasPrefix("{{time|") {
                if let endRange = remainingText.range(of: "}}") {
                    let tokenLength = remainingText.distance(from: remainingText.startIndex, to: endRange.upperBound)
                    let fullToken = String(remainingText.prefix(tokenLength))
                    result.append(TextComponent(text: fullToken, displayText: "time", isPlaceholder: true))
                    remainingText.removeFirst(tokenLength)
                    continue
                }
            }

            // Check if text starts with a variable token (pattern: {{variable|%keyword}})
            if remainingText.hasPrefix("{{variable|") {
                if let endRange = remainingText.range(of: "}}") {
                    let tokenLength = remainingText.distance(from: remainingText.startIndex, to: endRange.upperBound)
                    let fullToken = String(remainingText.prefix(tokenLength))
                    // Extract the keyword from {{variable|%keyword}}
                    let keyword = fullToken
                        .replacingOccurrences(of: "{{variable|", with: "")
                        .replacingOccurrences(of: "}}", with: "")
                    result.append(TextComponent(text: fullToken, displayText: keyword, isPlaceholder: true, isVariable: true))
                    remainingText.removeFirst(tokenLength)
                    continue
                }
            }

            // Check if text starts with a placeholder token
            var foundToken = false
            for token in PlaceholderToken.allCases {
                if remainingText.hasPrefix(token.storageText) {
                    result.append(TextComponent(text: token.storageText, displayText: token.rawValue, isPlaceholder: true))
                    remainingText.removeFirst(token.storageText.count)
                    foundToken = true
                    break
                }
            }

            if !foundToken {
                // Find the next placeholder or take rest of string
                var nextTokenIndex = remainingText.count

                // Check for single fill-in token
                if let range = remainingText.range(of: "{{fillin_single|") {
                    let index = remainingText.distance(from: remainingText.startIndex, to: range.lowerBound)
                    nextTokenIndex = min(nextTokenIndex, index)
                }

                // Check for multi fill-in token
                if let range = remainingText.range(of: "{{fillin_multi|") {
                    let index = remainingText.distance(from: remainingText.startIndex, to: range.lowerBound)
                    nextTokenIndex = min(nextTokenIndex, index)
                }

                // Check for select fill-in token
                if let range = remainingText.range(of: "{{fillin_select|") {
                    let index = remainingText.distance(from: remainingText.startIndex, to: range.lowerBound)
                    nextTokenIndex = min(nextTokenIndex, index)
                }

                // Check for date token
                if let range = remainingText.range(of: "{{date|") {
                    let index = remainingText.distance(from: remainingText.startIndex, to: range.lowerBound)
                    nextTokenIndex = min(nextTokenIndex, index)
                }

                // Check for time token
                if let range = remainingText.range(of: "{{time|") {
                    let index = remainingText.distance(from: remainingText.startIndex, to: range.lowerBound)
                    nextTokenIndex = min(nextTokenIndex, index)
                }

                // Check for variable token
                if let range = remainingText.range(of: "{{variable|") {
                    let index = remainingText.distance(from: remainingText.startIndex, to: range.lowerBound)
                    nextTokenIndex = min(nextTokenIndex, index)
                }

                // Check for placeholder tokens
                for token in PlaceholderToken.allCases {
                    if let range = remainingText.range(of: token.storageText) {
                        let index = remainingText.distance(from: remainingText.startIndex, to: range.lowerBound)
                        nextTokenIndex = min(nextTokenIndex, index)
                    }
                }

                let plainText = String(remainingText.prefix(nextTokenIndex))
                if !plainText.isEmpty {
                    result.append(TextComponent(text: plainText, displayText: plainText, isPlaceholder: false))
                }
                remainingText.removeFirst(nextTokenIndex)
            }
        }

        return result
    }

    private struct TextComponent {
        let text: String
        let displayText: String
        let isPlaceholder: Bool
        var isVariable: Bool = false
    }
}
