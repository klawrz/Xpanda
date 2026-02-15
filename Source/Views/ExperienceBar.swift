import SwiftUI

struct ExperienceBar: View {
    @ObservedObject var progress: XPProgress

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Level \(progress.level)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary)

                Spacer()

                Text("\(progress.currentExperience) / \(progress.experienceNeeded) exp")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background bar
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 8)

                    // Progress bar
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.green, Color.blue]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progress.progress, height: 8)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: progress.progress)
                }
            }
            .frame(height: 8)

            HStack {
                Text("\(progress.totalExpansions) total expansions")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Spacer()

                Text("+\(progress.experiencePerExpansion) exp per use")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.clear)
    }
}
