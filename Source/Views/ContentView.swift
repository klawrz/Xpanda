import SwiftUI

struct ContentView: View {
    @EnvironmentObject var xpManager: XPManager
    @State private var selectedXP: XP?
    @State private var showingAddSheet = false
    @State private var showingEditSheet = false
    @State private var showingConflicts = false
    @State private var showingImportExport = false
    @State private var showingAbout = false

    var body: some View {
        NavigationSplitView {
            // Sidebar
            VStack(spacing: 0) {
                // Search bar
                SearchBar(text: $xpManager.searchText)
                    .padding()

                // Filter section
                if !xpManager.allTags.isEmpty || !xpManager.allFolders.isEmpty {
                    FilterSidebar()
                        .padding(.horizontal)
                }

                Divider()

                // XP List
                List(selection: $selectedXP) {
                    ForEach(xpManager.filteredXPs) { xp in
                        XPListRow(xp: xp, hasConflict: xpManager.conflictingKeywords[xp.keyword.lowercased()]?.count ?? 0 > 1)
                            .tag(xp)
                            .contextMenu {
                                Button("Edit") {
                                    selectedXP = xp
                                    showingEditSheet = true
                                }
                                Button("Delete", role: .destructive) {
                                    xpManager.delete(xp)
                                }
                            }
                    }
                }
                .listStyle(.sidebar)
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

                        Button(action: { showingAddSheet = true }) {
                            Label("Add XP", systemImage: "plus")
                        }
                    }
                }

                ToolbarItem(placement: .navigation) {
                    HStack {
                        Menu {
                            Button("Import XPs...") {
                                showingImportExport = true
                            }
                            Button("Export XPs...") {
                                exportXPs()
                            }
                        } label: {
                            Label("More", systemImage: "ellipsis.circle")
                        }

                        Button(action: { showingAbout = true }) {
                            Image("PandaLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .help("About Xpanda")
                    }
                }
            }
        } detail: {
            // Detail view
            if let xp = selectedXP {
                XPDetailView(xp: xp, onEdit: {
                    showingEditSheet = true
                })
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
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddEditXPView(mode: .add)
                .environmentObject(xpManager)
        }
        .sheet(isPresented: $showingEditSheet) {
            if let xp = selectedXP {
                AddEditXPView(mode: .edit(xp))
                    .environmentObject(xpManager)
            }
        }
        .sheet(isPresented: $showingConflicts) {
            ConflictView()
                .environmentObject(xpManager)
        }
        .sheet(isPresented: $showingImportExport) {
            ImportView()
                .environmentObject(xpManager)
        }
        .popover(isPresented: $showingAbout) {
            AboutView()
                .environmentObject(xpManager)
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
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct XPListRow: View {
    let xp: XP
    let hasConflict: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(xp.keyword)
                        .font(.headline)
                    if hasConflict {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                }

                Text(xp.expansion)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

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
