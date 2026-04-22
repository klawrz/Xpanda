import SwiftUI

// MARK: - Optional Tutorial Environment Key

private struct TutorialManagerKey: EnvironmentKey {
    static let defaultValue: TutorialManager? = nil
}

extension EnvironmentValues {
    var optionalTutorialManager: TutorialManager? {
        get { self[TutorialManagerKey.self] }
        set { self[TutorialManagerKey.self] = newValue }
    }
}

// MARK: - Tutorial Highlight Modifier

extension View {
    func tutorialHighlight(for step: TutorialStep, with tutorial: TutorialManager, inset: CGFloat = 0) -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: 8 + inset)
                .stroke(
                    (tutorial.isShowing && tutorial.currentStep == step)
                        ? Color.yellow : Color.clear,
                    lineWidth: 3
                )
                .padding(-inset)
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.6), value: tutorial.currentStep)
        )
    }
}

// MARK: - Tutorial Card

struct TutorialCard: View {
    @ObservedObject var tutorial: TutorialManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title + Skip
            HStack(alignment: .top) {
                Text(tutorial.currentStep.title)
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button("Skip") { tutorial.skip() }
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .buttonStyle(.plain)
            }

            // Description
            // ZStack renders all descriptions invisibly so the container height
            // is always equal to the tallest one — no arbitrary constant needed.
            ZStack(alignment: .topLeading) {
                ForEach(TutorialStep.allCases, id: \.self) { step in
                    Text(step.description)
                        .font(.subheadline)
                        .opacity(0)
                }
                Text(tutorial.currentStep.description)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            // Progress dots + navigation
            HStack {
                // Dots
                HStack(spacing: 5) {
                    ForEach(0..<tutorial.currentSteps.count, id: \.self) { index in
                        Circle()
                            .fill(index == tutorial.currentIndex
                                  ? Color.yellow
                                  : Color.white.opacity(0.35))
                            .frame(width: 6, height: 6)
                            .onTapGesture { tutorial.goTo(index: index) }
                    }
                }

                Spacer()

                // Back / Next
                HStack(spacing: 8) {
                    if !tutorial.isFirst {
                        Button(action: { tutorial.back() }) {
                            Text("Back")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.15))
                                .cornerRadius(8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: { tutorial.next() }) {
                        Text(tutorial.isLast ? "Done" : "Next")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(Color(red: 0.25, green: 0.08, blue: 0.45))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.yellow)
                            .cornerRadius(8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.28, green: 0.1, blue: 0.48))
                .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 6)
        )
        .frame(width: 340)
        .padding(.bottom, 20)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
