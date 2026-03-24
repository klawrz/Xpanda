import SwiftUI
import RevenueCat

struct PaywallView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var offerings: Offerings? = nil
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Spacer()
                Button("Dismiss") { dismiss() }
                    .padding()
            }

            ScrollView {
                VStack(spacing: 28) {
                    // Icon + title
                    VStack(spacing: 12) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 64, height: 64)
                            .cornerRadius(14)

                        Text("Unlock AI Rephrasing")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Automatically rephrase your expansions so they never sound repetitive.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 320)
                    }

                    // Features list
                    VStack(alignment: .leading, spacing: 10) {
                        FeatureRow(icon: "sparkles", text: "AI-powered rephrasing on every expansion")
                        FeatureRow(icon: "wand.and.stars", text: "Custom instructions per expansion")
                        FeatureRow(icon: "arrow.clockwise", text: "Never sounds repetitive")
                    }

                    // Packages
                    if let offerings {
                        VStack(spacing: 10) {
                            ForEach(offerings.current?.availablePackages ?? [], id: \.identifier) { package in
                                PackageButton(
                                    package: package,
                                    isPurchasing: isPurchasing
                                ) {
                                    purchase(package: package)
                                }
                            }
                        }
                    } else {
                        ProgressView()
                            .padding()
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }

                    // Restore
                    Button(isRestoring ? "Restoring..." : "Restore Purchases") {
                        Task { await restore() }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .disabled(isRestoring || isPurchasing)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
        .frame(width: 420, height: 560)
        .task { await loadOfferings() }
    }

    private func loadOfferings() async {
        do {
            offerings = try await Purchases.shared.offerings()
        } catch {
            errorMessage = "Could not load offerings: \(error.localizedDescription)"
        }
    }

    private func purchase(package: Package) {
        isPurchasing = true
        errorMessage = nil
        Task {
            do {
                let result = try await Purchases.shared.purchase(package: package)
                if !result.userCancelled {
                    let active = result.customerInfo.entitlements["support_safari_pro"]?.isActive == true
                    await MainActor.run {
                        authManager.hasAIAccess  = active
                        authManager.isSubscribed = active
                        if active { dismiss() }
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isPurchasing = false
        }
    }

    private func restore() async {
        isRestoring = true
        await authManager.restorePurchases()
        isRestoring = false
        if authManager.isSubscribed { dismiss() }
    }
}

private struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.orange)
                .frame(width: 20)
            Text(text)
                .font(.body)
            Spacer()
        }
    }
}

private struct PackageButton: View {
    let package: Package
    let isPurchasing: Bool
    let action: () -> Void

    var priceString: String {
        package.storeProduct.localizedPriceString
    }

    var periodString: String {
        switch package.packageType {
        case .monthly: return "/ month"
        case .annual:  return "/ year"
        default:       return ""
        }
    }

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(package.storeProduct.localizedTitle)
                        .font(.body)
                        .fontWeight(.medium)
                    if let intro = package.storeProduct.introductoryDiscount {
                        Text("\(intro.localizedPriceString) free trial")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                Spacer()
                Text("\(priceString) \(periodString)")
                    .font(.body)
                    .fontWeight(.semibold)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.orange.opacity(0.5), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isPurchasing)
    }
}
