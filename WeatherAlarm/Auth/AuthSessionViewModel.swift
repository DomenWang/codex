import Foundation

@MainActor
final class AuthSessionViewModel: ObservableObject {
    enum State: Equatable {
        case signedOut
        case restoring
        case authenticating
        case signedIn(AuthUser)
    }

    @Published private(set) var state: State = .signedOut
    @Published var email = ""
    @Published var password = ""
    @Published var displayName = ""
    @Published var isRegistering = false
    @Published var message: String?

    private let authService: AuthService
    private let tokenStore: KeychainTokenStore
    private let entitlementSnapshotStore: PurchaseEntitlementSnapshotStore
    private var tokens: AuthTokens?

    init(
        authService: AuthService = AuthService(),
        tokenStore: KeychainTokenStore = KeychainTokenStore(),
        entitlementSnapshotStore: PurchaseEntitlementSnapshotStore = PurchaseEntitlementSnapshotStore()
    ) {
        self.authService = authService
        self.tokenStore = tokenStore
        self.entitlementSnapshotStore = entitlementSnapshotStore
    }

    var isSignedIn: Bool {
        if case .signedIn = state {
            return true
        }

        return false
    }

    func restoreSession() async {
        guard case .signedOut = state else {
            return
        }

        state = .restoring

        do {
            guard let storedTokens = try tokenStore.load() else {
                state = .signedOut
                return
            }

            do {
                let user = try await authService.currentUser(accessToken: storedTokens.accessToken)
                tokens = storedTokens
                state = .signedIn(user)
                await syncLocalEntitlementsIfPossible()
            } catch {
                let refreshedSession = try await authService.refresh(refreshToken: storedTokens.refreshToken)
                try tokenStore.save(refreshedSession.tokens)
                tokens = refreshedSession.tokens
                state = .signedIn(refreshedSession.user)
                await syncLocalEntitlementsIfPossible()
            }
            message = nil
        } catch {
            tokenStore.clear()
            tokens = nil
            state = .signedOut
            message = nil
        }
    }

    func submit() async {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedEmail.isEmpty, !password.isEmpty else {
            message = "请输入邮箱和密码"
            return
        }

        state = .authenticating
        message = nil

        do {
            let session: AuthSession
            if isRegistering {
                session = try await authService.signUp(
                    email: normalizedEmail,
                    password: password,
                    displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                )
            } else {
                session = try await authService.signIn(email: normalizedEmail, password: password)
            }

            try tokenStore.save(session.tokens)
            tokens = session.tokens
            password = ""
            state = .signedIn(session.user)
            await syncLocalEntitlementsIfPossible()
        } catch {
            state = .signedOut
            message = error.localizedDescription
        }
    }

    func signOut() async {
        let currentTokens = tokens ?? (try? tokenStore.load())
        tokenStore.clear()
        tokens = nil
        state = .signedOut

        if let refreshToken = currentTokens?.refreshToken {
            try? await authService.logout(refreshToken: refreshToken)
        }
    }

    func syncLocalEntitlementsIfPossible() async {
        guard case .signedIn(let user) = state,
              let accessToken = tokens?.accessToken ?? (try? tokenStore.load())?.accessToken else {
            return
        }

        let snapshot = entitlementSnapshotStore.databaseSyncSnapshot
        guard snapshot.hasAnyEntitlement else {
            return
        }

        do {
            _ = try await authService.syncEntitlements(
                userID: user.id,
                accessToken: accessToken,
                snapshot: snapshot
            )
            entitlementSnapshotStore.markDatabaseSyncComplete()
        } catch {
            message = nil
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
