import Foundation
import AuthenticationServices
import Supabase
import RevenueCat

@MainActor
class AuthManager: NSObject, ObservableObject {
    static let shared = AuthManager()

    @Published var isSignedIn: Bool = false
    @Published var userID: String? = nil
    @Published var displayName: String? = nil
    @Published var email: String? = nil
    @Published var hasAIAccess: Bool = false {
        didSet { AuthManager.cachedHasAIAccess = hasAIAccess }
    }
    @Published var isSubscribed: Bool = false

    // Nonisolated cache so nonisolated callers (e.g. LLMRephraseService, ExpansionEngine)
    // can read subscription state without hopping to MainActor.
    nonisolated(unsafe) static var cachedHasAIAccess: Bool = false

    private let displayNameKey = "baeside.auth.displayName"

    override private init() {
        super.init()
        listenToAuthChanges()
    }

    // MARK: - Auth State Listener

    private func listenToAuthChanges() {
        Task {
            for await (event, session) in supabase.auth.authStateChanges {
                switch event {
                case .initialSession, .signedIn, .tokenRefreshed:
                    if let session {
                        apply(session: session)
                        resizeWindowForMainApp()
                        await loginRevenueCat(userID: session.user.id.uuidString)
                        await checkEntitlement()
                    } else {
                        await logoutRevenueCat()
                        clearLocal()
                    }
                case .signedOut, .userDeleted:
                    await logoutRevenueCat()
                    clearLocal()
                default:
                    break
                }
            }
        }
    }

    private func apply(session: Session) {
        userID      = session.user.id.uuidString
        email       = session.user.email
        displayName = UserDefaults.standard.string(forKey: displayNameKey)
        isSignedIn  = true
    }

    // MARK: - RevenueCat

    private func loginRevenueCat(userID: String) async {
        do {
            let (_, _) = try await Purchases.shared.logIn(userID)
            await checkEntitlement()
        } catch {
            print("RevenueCat login error: \(error)")
        }
    }

    private func logoutRevenueCat() async {
        // Only log out if RC has a non-anonymous user logged in
        guard !Purchases.shared.isAnonymous else { return }
        do {
            _ = try await Purchases.shared.logOut()
        } catch {
            print("RevenueCat logout error: \(error)")
        }
    }

    // MARK: - Sign In with Apple

    func handleSignInWithApple(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData  = credential.identityToken,
                  let idToken    = String(data: tokenData, encoding: .utf8) else { return }

            let nameParts = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }
            if !nameParts.isEmpty {
                let name = nameParts.joined(separator: " ")
                UserDefaults.standard.set(name, forKey: displayNameKey)
                displayName = name
            }

            Task {
                do {
                    try await supabase.auth.signInWithIdToken(
                        credentials: .init(provider: .apple, idToken: idToken)
                    )
                } catch {
                    print("Supabase sign in failed: \(error)")
                }
            }

        case .failure(let error):
            print("Sign in with Apple failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Skip Sign In (dev / pre-activation bypass)

    func skipSignIn() {
        isSignedIn = true
        hasAIAccess = false
        isSubscribed = false
        resizeWindowForMainApp()
    }

    func resizeWindowForMainApp() {
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return }
            let screen = window.screen ?? NSScreen.main
            let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
            let width: CGFloat = min(1100, screenFrame.width - 100)
            let height: CGFloat = min(750, screenFrame.height - 100)
            let x = screenFrame.midX - width / 2
            let y = screenFrame.midY - height / 2
            window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true, animate: true)
        }
    }

    // MARK: - Sign Out

    func signOut() {
        Task {
            try? await supabase.auth.signOut()
        }
    }

    // MARK: - Entitlement Check

    func checkEntitlement() async {
        guard isSignedIn else {
            hasAIAccess = false
            isSubscribed = false
            return
        }

        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            let active = customerInfo.entitlements["support_safari_pro"]?.isActive == true
            hasAIAccess  = active
            isSubscribed = active
        } catch {
            // Fall back to Supabase table if RevenueCat is unavailable
            await checkEntitlementViaSupabase()
        }
    }

    private func checkEntitlementViaSupabase() async {
        guard isSignedIn, let uid = userID else {
            hasAIAccess = false
            return
        }

        struct Row: Decodable { let status: String }

        do {
            let rows: [Row] = try await supabase
                .from("user_entitlements")
                .select("status")
                .eq("user_id", value: uid)
                .eq("entitlement_id", value: "support_safari_pro")
                .eq("status", value: "active")
                .execute()
                .value
            let active = !rows.isEmpty
            hasAIAccess  = active
            isSubscribed = active
        } catch {
            hasAIAccess  = false
            isSubscribed = false
        }
    }

    // MARK: - Restore Purchases

    func restorePurchases() async {
        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            let active = customerInfo.entitlements["support_safari_pro"]?.isActive == true
            hasAIAccess  = active
            isSubscribed = active
        } catch {
            print("Restore purchases failed: \(error)")
        }
    }

    // MARK: - Private

    private func clearLocal() {
        isSignedIn   = false
        userID       = nil
        email        = nil
        displayName  = nil
        hasAIAccess  = false
        isSubscribed = false
    }
}
