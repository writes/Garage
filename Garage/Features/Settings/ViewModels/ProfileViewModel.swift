import Foundation
import Observation

@MainActor
@Observable
final class ProfileViewModel {
    private let store: any ProfileStore
    private let userID: () -> String?
    private let analytics: any AnalyticsTracking
#if DEBUG
    private let isDemoMode: Bool
#endif
    var name = ""
    var address = ""
    var phone = ""
    var insuranceCompany = ""
    var policyNumber = ""
    var analyticsOptOut = true
    private(set) var themeID: String?
    private(set) var userProfile: UserProfile?
    private(set) var error: AppError?
    private(set) var hasSuccessfullyLoadedProfile = false
#if DEBUG
    init(
        store: (any ProfileStore)? = nil,
        userID: @escaping () -> String? = { AuthService.shared.uid },
        analytics: any AnalyticsTracking = AnalyticsService.shared,
        isDemoMode: Bool = AppRuntime.isLocalDemoMode,
        demoStore: DemoSessionStore = .shared,
        automaticallyLoad: Bool = true
    ) {
        self.userID = userID
        self.analytics = analytics
        self.isDemoMode = isDemoMode
        self.store = isDemoMode ? DemoProfileStore(demoStore: demoStore) : (store ?? FirestoreProfileStore())
        if automaticallyLoad {
            Task { [weak self] in
                await self?.load()
            }
        }
    }
#else
    init(
        store: (any ProfileStore)? = nil,
        userID: @escaping () -> String? = { AuthService.shared.uid },
        analytics: any AnalyticsTracking = AnalyticsService.shared
    ) {
        self.userID = userID
        self.analytics = analytics
        self.store = store ?? ProfileStoreFactory.makeDefault()
        Task { [weak self] in
            await self?.load()
        }
    }
#endif
    func load() async {
        hasSuccessfullyLoadedProfile = false
        guard let uid = resolvedUserID() else {
            error = .auth("Not authenticated")
            userProfile = nil
            analytics.setEnabled(false)
            return
        }
        do {
            let profile = try await Self.loadProfile(uid: uid, store: store)
            guard resolvedUserID() == uid else {
                userProfile = nil
                analytics.setEnabled(false)
                return
            }
            apply(profile)
            userProfile = profile
            analytics.setEnabled(!profile.analyticsOptOut)
            hasSuccessfullyLoadedProfile = true
            error = nil
        } catch {
            userProfile = nil
            analytics.setEnabled(false)
            self.error = AppError(from: error)
        }
    }
    @discardableResult
    func save() async -> Bool {
        // Never write before a successful load: on a failed/offline/in-flight load the VM still
        // holds empty defaults, and save() writes every form-owned field BY VALUE, which would
        // wipe the user's name/address/insurance on the server.
        guard hasSuccessfullyLoadedProfile else { return false }
        guard let uid = resolvedUserID() else {
            error = .auth("Not authenticated")
            return false
        }
        do {
            let profile = makeProfile(uid: uid)
            // formOwnedFields, NOT profileFields: the store merges, so fields other surfaces own
            // (themeID, aiConsent) are preserved by OMISSION — cached copies here can be stale.
            try await store.saveProfile(profile.formOwnedFields, uid: uid)
            guard resolvedUserID() == uid else {
                userProfile = nil
                analytics.setEnabled(false)
                return false
            }
            userProfile = profile
            error = nil
            return true
        } catch {
            self.error = AppError(from: error)
            return false
        }
    }
    /// Writes only consent before enabling collection, preserving untouched profile fields.
    @discardableResult
    func setAnalyticsSharingEnabled(_ enabled: Bool) async -> Bool {
        guard hasSuccessfullyLoadedProfile, let expectedUserID = resolvedUserID() else {
            analytics.setEnabled(false)
            return false
        }

        let previousOptOut = analyticsOptOut
        let previousProfile = userProfile
        analyticsOptOut = !enabled
        if !enabled {
            analytics.setEnabled(false)
        }

        do {
            try await store.saveProfileFields(
                ["analyticsOptOut": .boolean(analyticsOptOut)],
                uid: expectedUserID
            )
            guard resolvedUserID() == expectedUserID else {
                return failAnalyticsSharingChange(
                    enabled: enabled,
                    previousOptOut: previousOptOut,
                    previousProfile: previousProfile,
                    clearLoadedProfile: true
                )
            }

            if var profile = userProfile {
                profile.analyticsOptOut = analyticsOptOut
                userProfile = profile
            }
            error = nil
            analytics.setEnabled(enabled)
            return true
        } catch {
            return failAnalyticsSharingChange(
                enabled: enabled,
                previousOptOut: previousOptOut,
                previousProfile: previousProfile,
                error: error
            )
        }
    }

    private func failAnalyticsSharingChange(
        enabled: Bool,
        previousOptOut: Bool,
        previousProfile: UserProfile?,
        error: Error? = nil,
        clearLoadedProfile: Bool = false
    ) -> Bool {
        analyticsOptOut = previousOptOut
        userProfile = clearLoadedProfile ? nil : previousProfile
        hasSuccessfullyLoadedProfile = !clearLoadedProfile
        if let error {
            self.error = AppError(from: error)
        }
        if enabled {
            analytics.setEnabled(false)
        } else {
            analytics.suppressCollectionForCurrentSession()
        }
        return false
    }

    static func loadProfile(uid: String, store: any ProfileStore) async throws -> UserProfile {
        let fields = try await store.loadProfile(uid: uid) ?? [:]
        return UserProfile(id: uid, profileFields: fields)
    }
    private func makeProfile(uid: String) -> UserProfile {
        // themeID/aiConsentGrantedAt ride the LOCAL cache only; save() writes formOwnedFields,
        // which excludes them, so these cached copies never clobber the surfaces that own them.
        UserProfile(
            id: uid, email: nil, name: name, address: address, phone: phone,
            insuranceCompany: insuranceCompany, policyNumber: policyNumber,
            analyticsOptOut: analyticsOptOut, themeID: themeID,
            aiConsentGrantedAt: userProfile?.aiConsentGrantedAt, createdAt: nil, updatedAt: nil
        )
    }
    private func apply(_ profile: UserProfile) {
        name = profile.name ?? ""
        address = profile.address ?? ""
        phone = profile.phone ?? ""
        insuranceCompany = profile.insuranceCompany ?? ""
        policyNumber = profile.policyNumber ?? ""
        analyticsOptOut = profile.analyticsOptOut
        themeID = profile.themeID
    }

    private func resolvedUserID() -> String? {
#if DEBUG
        if isDemoMode {
            return AppRuntime.demoUserId
        }
#endif
        return userID()
    }
}

extension ProfileViewModel {
    /// Writes only the accent-theme id (a partial field write) so untouched profile fields are
    /// preserved. Optimistically applies the new accent, then rolls back both the id and the live
    /// scheme on any failure or account mismatch. Mirrors setAnalyticsSharingEnabled.
    @discardableResult
    func setThemeID(_ id: String) async -> Bool {
        guard hasSuccessfullyLoadedProfile, let expectedUserID = resolvedUserID() else {
            return false
        }
        let previousThemeID = themeID
        let previousScheme = AccentStore.shared.scheme
        themeID = id
        AccentStore.shared.apply(themeID: id)

        do {
            try await store.saveProfileFields(["themeID": .string(id)], uid: expectedUserID)
            guard resolvedUserID() == expectedUserID else {
                return rollBackTheme(previousThemeID, previousScheme)
            }
            if var profile = userProfile {
                profile.themeID = id
                userProfile = profile
            }
            // Only a PERSISTED theme change counts as theming usage — an optimistic apply that
            // rolled back never happened from the user's point of view.
            analytics.track(.featureUsed(feature: .theming))
            error = nil
            return true
        } catch {
            self.error = AppError(from: error)
            return rollBackTheme(previousThemeID, previousScheme)
        }
    }

    private func rollBackTheme(_ previousThemeID: String?, _ previousScheme: AccentScheme) -> Bool {
        themeID = previousThemeID
        AccentStore.shared.scheme = previousScheme
        return false
    }
}
