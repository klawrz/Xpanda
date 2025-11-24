import Foundation
import Combine

class XPProgress: ObservableObject, Codable {
    @Published var level: Int
    @Published var currentExperience: Int
    @Published var totalExpansions: Int

    init(level: Int = 1, currentExperience: Int = 0, totalExpansions: Int = 0) {
        self.level = level
        self.currentExperience = currentExperience
        self.totalExpansions = totalExpansions
    }

    // Experience needed for current level
    var experienceNeeded: Int {
        calculateExperienceNeeded(for: level)
    }

    // Experience points gained per expansion at current level
    var experiencePerExpansion: Int {
        calculateExperiencePerExpansion(for: level)
    }

    // Progress percentage (0.0 to 1.0)
    var progress: Double {
        Double(currentExperience) / Double(experienceNeeded)
    }

    // Calculate XP needed for a given level
    private func calculateExperienceNeeded(for level: Int) -> Int {
        // Base: 35 XP for level 1
        // Formula: 35 + (level - 1) * 20
        // Level 1: 35, Level 2: 55, Level 3: 75, Level 4: 95, etc.
        return 35 + (level - 1) * 20
    }

    // Calculate XP gained per expansion at a given level
    private func calculateExperiencePerExpansion(for level: Int) -> Int {
        // Base: 5 XP at level 1
        // Increases by 1 every 3 levels
        // Level 1-3: 5 XP, Level 4-6: 6 XP, Level 7-9: 7 XP, etc.
        return 5 + (level - 1) / 3
    }

    // Add experience and check for level up
    func addExperience() -> Bool {
        let xpGained = experiencePerExpansion
        currentExperience += xpGained
        totalExpansions += 1

        // Check if leveled up
        if currentExperience >= experienceNeeded {
            levelUp()
            return true
        }
        return false
    }

    // Level up and carry over excess XP
    private func levelUp() {
        let excess = currentExperience - experienceNeeded
        level += 1
        currentExperience = excess

        // Check if we level up again (rare but possible with excess XP)
        if currentExperience >= experienceNeeded {
            levelUp()
        }
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case level
        case currentExperience
        case totalExpansions
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        level = try container.decode(Int.self, forKey: .level)
        currentExperience = try container.decode(Int.self, forKey: .currentExperience)
        totalExpansions = try container.decode(Int.self, forKey: .totalExpansions)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(level, forKey: .level)
        try container.encode(currentExperience, forKey: .currentExperience)
        try container.encode(totalExpansions, forKey: .totalExpansions)
    }
}
