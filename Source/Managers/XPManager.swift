import Foundation
import Combine

class XPManager: ObservableObject {
    static let shared = XPManager()

    enum ViewFilter {
        case all
        case xpsOnly
        case variablesOnly
    }

    @Published var xps: [XP] = []
    @Published var searchText: String = ""
    @Published var selectedTags: Set<String> = []
    @Published var selectedFolder: String? = nil
    @Published var viewFilter: ViewFilter = .xpsOnly
    @Published var progress: XPProgress = XPProgress()

    private let storageURL: URL
    private let progressStorageURL: URL
    private let fileName = "xpanda_data.json"
    private let progressFileName = "xpanda_progress.json"

    var filteredXPs: [XP] {
        xps.filter { xp in
            let matchesSearch = searchText.isEmpty ||
                xp.keyword.localizedCaseInsensitiveContains(searchText) ||
                xp.expansion.localizedCaseInsensitiveContains(searchText) ||
                xp.tags.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })

            let matchesTags = selectedTags.isEmpty ||
                !selectedTags.isDisjoint(with: Set(xp.tags))

            let matchesFolder = selectedFolder == nil ||
                xp.folder == selectedFolder

            let matchesViewFilter: Bool = {
                switch viewFilter {
                case .all:
                    return true
                case .xpsOnly:
                    return !xp.isVariable
                case .variablesOnly:
                    return xp.isVariable
                }
            }()

            return matchesSearch && matchesTags && matchesFolder && matchesViewFilter
        }
    }

    var allTags: [String] {
        let tagSet = Set(xps.flatMap { $0.tags })
        return Array(tagSet).sorted()
    }

    var allFolders: [String] {
        let folderSet = Set(xps.compactMap { $0.folder })
        return Array(folderSet).sorted()
    }

    // MARK: - Variables

    /// All XPs that are variables (keyword starts with %)
    var allVariables: [XP] {
        xps.filter { $0.isVariable }
    }

    /// All XPs that are regular XPs (not variables)
    var allRegularXPs: [XP] {
        xps.filter { !$0.isVariable }
    }

    /// Find a variable by its keyword (including % prefix)
    func findVariable(byKeyword keyword: String) -> XP? {
        allVariables.first { $0.keyword.lowercased() == keyword.lowercased() }
    }

    /// Find all XPs that reference a given variable
    func findReferences(toVariable variable: XP) -> [XP] {
        guard variable.isVariable else { return [] }
        let variableKeyword = variable.keyword

        return xps.filter { xp in
            // Don't include the variable itself
            guard xp.id != variable.id else { return false }

            // Check if expansion contains the variable keyword
            return xp.expansion.contains(variableKeyword)
        }
    }

    var conflictingKeywords: [String: [XP]] {
        var conflicts: [String: [XP]] = [:]

        // Filter out XPs with empty keywords
        let validXPs = xps.filter { !$0.keyword.isEmpty }
        let groupedByKeyword = Dictionary(grouping: validXPs) { $0.keyword.lowercased() }

        // Check for exact duplicates
        for (keyword, xpList) in groupedByKeyword {
            if xpList.count > 1 {
                conflicts[keyword] = xpList
            }
        }

        // Check for prefix conflicts (e.g., "xrich" conflicts with "xrichtext")
        let sortedKeywords = validXPs.map { $0.keyword.lowercased() }.sorted()
        for i in 0..<sortedKeywords.count {
            for j in (i+1)..<sortedKeywords.count {
                let shorter = sortedKeywords[i]
                let longer = sortedKeywords[j]

                // Skip empty keywords
                guard !shorter.isEmpty, !longer.isEmpty else { continue }

                // If shorter is a prefix of longer, they conflict
                if longer.hasPrefix(shorter) {
                    // Mark both keywords as conflicting
                    conflicts[shorter] = validXPs.filter { $0.keyword.lowercased() == shorter }
                    conflicts[longer] = validXPs.filter { $0.keyword.lowercased() == longer }
                }
            }
        }

        return conflicts
    }

    var hasConflicts: Bool {
        !conflictingKeywords.isEmpty
    }

    // Get list of keywords that conflict with the given keyword
    func getConflictingKeywords(for keyword: String) -> [String] {
        let lowercaseKeyword = keyword.lowercased()

        // Skip empty keywords
        guard !lowercaseKeyword.isEmpty else { return [] }

        var conflicts: [String] = []

        for xp in xps {
            let otherKeyword = xp.keyword.lowercased()

            // Skip empty keywords
            guard !otherKeyword.isEmpty else { continue }

            // Skip if it's the same keyword
            if otherKeyword == lowercaseKeyword {
                continue
            }

            // Check if one is a prefix of the other
            if lowercaseKeyword.hasPrefix(otherKeyword) || otherKeyword.hasPrefix(lowercaseKeyword) {
                conflicts.append(xp.keyword)
            }
        }

        return conflicts
    }

    init() {
        // Set up storage location
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = appSupport.appendingPathComponent("Xpanda", isDirectory: true)

        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: appDirectory.path) {
            try? fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        }

        storageURL = appDirectory.appendingPathComponent(fileName)
        progressStorageURL = appDirectory.appendingPathComponent(progressFileName)

        // Load existing data
        load()
        loadProgress()
    }

    // MARK: - CRUD Operations

    func add(_ xp: XP) {
        xps.insert(xp, at: 0) // Add to the top of the list
        save()
    }

    func update(_ xp: XP) {
        if let index = xps.firstIndex(where: { $0.id == xp.id }) {
            var updatedXP = xp
            updatedXP.dateModified = Date()
            xps[index] = updatedXP
            save()
        }
    }

    func delete(_ xp: XP) {
        xps.removeAll { $0.id == xp.id }
        pruneStaleFilters()
        save()
    }

    func delete(at offsets: IndexSet) {
        let xpsToDelete = offsets.map { filteredXPs[$0] }
        xps.removeAll { xp in xpsToDelete.contains(xp) }
        pruneStaleFilters()
        save()
    }

    /// Remove any active tag/folder filters that no longer match any XP.
    private func pruneStaleFilters() {
        let remainingTags = Set(xps.flatMap { $0.tags })
        selectedTags = selectedTags.intersection(remainingTags)

        if let folder = selectedFolder, !xps.contains(where: { $0.folder == folder }) {
            selectedFolder = nil
        }
    }

    // MARK: - Storage

    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(xps)
            try data.write(to: storageURL)
        } catch {
            print("Error saving XPs: \(error)")
        }
    }

    func load() {
        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            xps = try decoder.decode([XP].self, from: data)
        } catch {
            print("Error loading XPs: \(error)")
            // Start with sample data if no saved data exists
            xps = XP.samples
            save()
        }
    }

    // MARK: - Import/Export

    func exportXPs(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(xps)
        try data.write(to: url)
    }

    func importXPs(from url: URL, merge: Bool = false) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let importedXPs = try decoder.decode([XP].self, from: data)

        if merge {
            // Merge imported XPs with existing ones
            let existingIDs = Set(xps.map { $0.id })
            let newXPs = importedXPs.filter { !existingIDs.contains($0.id) }
            xps.append(contentsOf: newXPs)
        } else {
            // Replace all XPs
            xps = importedXPs
        }

        save()
    }

    // MARK: - Keyword Lookup

    func findXP(forKeyword keyword: String) -> XP? {
        xps.first { $0.keyword.lowercased() == keyword.lowercased() }
    }

    // MARK: - Progress Management

    func addExperienceForExpansion() -> Bool {
        let leveledUp = progress.addExperience()
        saveProgress()
        return leveledUp
    }

    func saveProgress() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(progress)
            try data.write(to: progressStorageURL)
        } catch {
            print("Error saving progress: \(error)")
        }
    }

    func loadProgress() {
        do {
            let data = try Data(contentsOf: progressStorageURL)
            let decoder = JSONDecoder()
            progress = try decoder.decode(XPProgress.self, from: data)
        } catch {
            // Start with new progress if no saved data exists
            progress = XPProgress()
            saveProgress()
        }
    }
}
