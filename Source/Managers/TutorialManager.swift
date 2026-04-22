import SwiftUI

enum TutorialStep: Int, CaseIterable {
    // Phase 1 — main screen
    case welcome
    case xpsTab
    case variablesTab
    case autocorrectTab
    case searchBar
    // Phase 2 — XP editor (triggered on first XP open)
    case keyword
    case expansion
    case toolbar
    case tagsFolder

    var title: String {
        switch self {
        case .welcome:       return "Welcome to Xpanda!"
        case .xpsTab:        return "XPs"
        case .variablesTab:  return "Variables"
        case .autocorrectTab:return "Autocorrect"
        case .searchBar:     return "Search"
        case .keyword:       return "Keyword"
        case .expansion:     return "Expansion"
        case .toolbar:       return "Toolbar"
        case .tagsFolder:    return "Tags & Folder"
        }
    }

    var description: String {
        switch self {
        case .welcome:
            return "Type short keywords anywhere on your Mac and they instantly expand into full messages. Let's take a quick tour."
        case .xpsTab:
            return "The XPs tab stores your text expansions. Each XP has a keyword you type and a message it expands into."
        case .variablesTab:
            return "Variables are reusable snippets. Use the Variable tool in the XP editor toolbar to insert one — update the variable once and every XP that uses it updates too."
        case .autocorrectTab:
            return "Your own personal autocorrect. Add the typos and misspellings you know you make, and they'll be fixed automatically as you type. Unlike system autocorrect, this list is fully yours to define."
        case .searchBar:
            return "Use the search bar to find any XP, Variable, or Autocorrect instantly by keyword or content."
        case .keyword:
            return "This is the keyword. Type it anywhere on your Mac — in any app — and Xpanda replaces it with your expansion."
        case .expansion:
            return "This is the expansion — the full text that gets inserted when you type the keyword. Supports rich text, fill-in fields, and more."
        case .toolbar:
            return "The toolbar lets you format text, insert fill-in fields, dates, variables, clipboard content, and AI rephrasing."
        case .tagsFolder:
            return "Use tags and folders to organise your XPs and filter them quickly in the sidebar. You're all set!"
        }
    }

    var isPhaseTwo: Bool {
        return self.rawValue >= TutorialStep.keyword.rawValue
    }
}

@MainActor
class TutorialManager: ObservableObject {
    static let shared = TutorialManager()

    @Published var currentStep: TutorialStep = .welcome
    @Published var isShowingPhaseOne: Bool = false
    @Published var isShowingPhaseTwo: Bool = false

    private let phaseOneDoneKey = "tutorial.phaseOneDone"
    private let phaseTwoDoneKey = "tutorial.phaseTwoDone"

    var isShowing: Bool { isShowingPhaseOne || isShowingPhaseTwo }

    var phaseOneSteps: [TutorialStep] {
        TutorialStep.allCases.filter { !$0.isPhaseTwo }
    }

    var phaseTwoSteps: [TutorialStep] {
        TutorialStep.allCases.filter { $0.isPhaseTwo }
    }

    var currentSteps: [TutorialStep] {
        isShowingPhaseOne ? phaseOneSteps : phaseTwoSteps
    }

    var currentIndex: Int {
        currentSteps.firstIndex(of: currentStep) ?? 0
    }

    var isFirst: Bool { currentIndex == 0 }
    var isLast: Bool  { currentIndex == currentSteps.count - 1 }

    private init() {}

    func startPhaseOneIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: phaseOneDoneKey) else { return }
        currentStep = .welcome
        isShowingPhaseOne = true
    }

    func startPhaseTwoIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: phaseTwoDoneKey),
              !isShowingPhaseOne else { return }
        currentStep = .keyword
        isShowingPhaseTwo = true
    }

    func next() {
        if isLast {
            finish()
        } else {
            let steps = currentSteps
            let nextIndex = currentIndex + 1
            if nextIndex < steps.count {
                currentStep = steps[nextIndex]
            }
        }
    }

    func back() {
        guard !isFirst else { return }
        let steps = currentSteps
        let prevIndex = currentIndex - 1
        if prevIndex >= 0 {
            currentStep = steps[prevIndex]
        }
    }

    func goTo(index: Int) {
        let steps = currentSteps
        guard index >= 0, index < steps.count else { return }
        currentStep = steps[index]
    }

    func skip() { finish() }

    private func finish() {
        if isShowingPhaseOne {
            UserDefaults.standard.set(true, forKey: phaseOneDoneKey)
            isShowingPhaseOne = false
        } else {
            UserDefaults.standard.set(true, forKey: phaseTwoDoneKey)
            isShowingPhaseTwo = false
        }
    }
}
