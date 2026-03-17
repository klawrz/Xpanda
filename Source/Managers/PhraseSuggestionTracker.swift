import Foundation
import UserNotifications

struct TrackedPhrase: Codable {
    let normalizedText: String
    var originalText: String
    var count: Int
    var lastSeen: Date
    var notified: Bool
}

class PhraseSuggestionTracker {
    static let shared = PhraseSuggestionTracker()

    // MARK: - Configuration (UserDefaults)

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "phraseSuggestionsEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "phraseSuggestionsEnabled") }
    }

    var suggestionThreshold: Int {
        get { UserDefaults.standard.object(forKey: "phraseSuggestionThreshold") as? Int ?? 3 }
        set { UserDefaults.standard.set(newValue, forKey: "phraseSuggestionThreshold") }
    }

    // MARK: - Constants

    private let minPhraseLength = 20
    private let minWordCount = 4
    private let maxTrackedPhrases = 500
    private let phraseExpirationDays = 30

    // MARK: - Storage

    private let storageURL: URL
    private var phrases: [String: TrackedPhrase] = [:]
    private var saveWorkItem: DispatchWorkItem?

    // MARK: - Init

    private init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = appSupport.appendingPathComponent("Xpanda", isDirectory: true)

        if !fileManager.fileExists(atPath: appDirectory.path) {
            try? fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        }

        storageURL = appDirectory.appendingPathComponent("phrase_suggestions.json")
        load()
    }

    // MARK: - Normalization

    func normalize(_ phrase: String) -> String {
        var result = phrase.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip trailing punctuation
        while let last = result.last, ".!?,;:".contains(last) {
            result.removeLast()
        }

        // Collapse internal whitespace to single spaces
        let components = result.split(separator: " ", omittingEmptySubsequences: true)
        result = components.joined(separator: " ")

        return result.lowercased()
    }

    // MARK: - Record Phrase

    func recordPhrase(_ rawPhrase: String) {
        guard isEnabled else { return }

        let trimmed = rawPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minPhraseLength else { return }

        let words = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        guard words.count >= minWordCount else { return }

        guard !phraseAlreadyCoveredByXP(trimmed) else { return }

        let normalized = normalize(trimmed)
        guard !normalized.isEmpty else { return }

        if var existing = phrases[normalized] {
            existing.count += 1
            existing.lastSeen = Date()
            existing.originalText = trimmed
            phrases[normalized] = existing

            if existing.count >= suggestionThreshold && !existing.notified {
                showSuggestionNotification(for: existing)
                phrases[normalized]?.notified = true
            }
        } else {
            let newPhrase = TrackedPhrase(
                normalizedText: normalized,
                originalText: trimmed,
                count: 1,
                lastSeen: Date(),
                notified: false
            )
            phrases[normalized] = newPhrase
        }

        evictStaleEntries()
        debouncedSave()
    }

    // MARK: - XP Coverage Check

    func phraseAlreadyCoveredByXP(_ phrase: String) -> Bool {
        let normalizedPhrase = normalize(phrase)
        let manager = XPManager.shared
        return manager.xps.contains { normalize($0.expansion) == normalizedPhrase }
    }

    // MARK: - Clear All

    func clearAll() {
        phrases.removeAll()
        save()
    }

    // MARK: - Persistence

    func save() {
        saveWorkItem?.cancel()
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(Array(phrases.values))
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("Error saving phrase suggestions: \(error)")
        }
    }

    func load() {
        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let loaded = try decoder.decode([TrackedPhrase].self, from: data)
            phrases = Dictionary(uniqueKeysWithValues: loaded.map { ($0.normalizedText, $0) })
        } catch {
            phrases = [:]
        }
    }

    // MARK: - Private Helpers

    private func evictStaleEntries() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -phraseExpirationDays, to: Date()) ?? Date()

        // Remove expired entries
        phrases = phrases.filter { $0.value.lastSeen > cutoff }

        // If still over cap, remove oldest entries
        if phrases.count > maxTrackedPhrases {
            let sorted = phrases.sorted { $0.value.lastSeen < $1.value.lastSeen }
            let toRemove = phrases.count - maxTrackedPhrases
            for (key, _) in sorted.prefix(toRemove) {
                phrases.removeValue(forKey: key)
            }
        }
    }

    private func debouncedSave() {
        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.save()
        }
        saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: workItem)
    }

    private func showSuggestionNotification(for phrase: TrackedPhrase) {
        let content = UNMutableNotificationContent()
        content.title = "Xpanda Suggestion"

        let preview = phrase.originalText.count > 60
            ? String(phrase.originalText.prefix(57)) + "..."
            : phrase.originalText
        content.body = "You've typed \"\(preview)\" \(phrase.count) times. Create an XP?"
        content.categoryIdentifier = "PHRASE_SUGGESTION"
        content.userInfo = ["suggestedPhrase": phrase.originalText]
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "phrase-suggestion-\(phrase.normalizedText.hashValue)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error showing phrase suggestion notification: \(error)")
            }
        }
    }
}
