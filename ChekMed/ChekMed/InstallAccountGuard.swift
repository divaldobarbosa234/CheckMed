import Foundation

/// v1.0 single-install owner gate. Not multi-account. Does not migrate SwiftData.
enum InstallAccountGuard {
    static let defaultsKey = "checkmed.installBoundOwnerId"

    enum Decision: Equatable {
        /// Incoming auth user already owns this installation.
        case allow
        /// First authorized owner for this installation (or legacy claim).
        case claim
        /// A different auth user tried to bind this installation.
        case reject
    }

    /// Pure decision. Never writes UserDefaults, Keychain, SwiftData, or reminders.
    static func evaluate(
        incoming: UUID,
        persistedBound: UUID?,
        localOwner: UUID,
        existingOwners: Set<UUID>
    ) -> Decision {
        if let persistedBound {
            return persistedBound == incoming ? .allow : .reject
        }
        let foreign = existingOwners.filter { $0 != localOwner }
        if foreign.count > 1 {
            return .reject
        }
        if foreign.isEmpty {
            return .claim
        }
        return foreign.contains(incoming) ? .claim : .reject
    }

    static func boundOwnerId(defaults: UserDefaults = .standard) -> UUID? {
        guard let raw = defaults.string(forKey: defaultsKey) else { return nil }
        return UUID(uuidString: raw)
    }

    /// Persist only on `.claim`. Idempotent. Survives sign-out. Cleared on app delete
    /// (UserDefaults) or explicit account deletion.
    static func claim(_ ownerId: UUID, defaults: UserDefaults = .standard) {
        if boundOwnerId(defaults: defaults) == ownerId { return }
        defaults.set(ownerId.uuidString, forKey: defaultsKey)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }
}

#if DEBUG
enum InstallAccountGuardContractChecks {
    static func failures() -> [String] {
        var failures: [String] = []
        func expect(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }
        let local = UUID()
        let original = UUID()
        let other = UUID()

        expect(
            InstallAccountGuard.evaluate(
                incoming: original,
                persistedBound: original,
                localOwner: local,
                existingOwners: [original]
            ) == .allow,
            "GUARD: same bound owner is allowed"
        )
        expect(
            InstallAccountGuard.evaluate(
                incoming: other,
                persistedBound: original,
                localOwner: local,
                existingOwners: [original]
            ) == .reject,
            "GUARD: different auth user is rejected when bound"
        )
        expect(
            InstallAccountGuard.evaluate(
                incoming: original,
                persistedBound: nil,
                localOwner: local,
                existingOwners: []
            ) == .claim,
            "GUARD: empty install claims first auth user"
        )
        expect(
            InstallAccountGuard.evaluate(
                incoming: original,
                persistedBound: nil,
                localOwner: local,
                existingOwners: [local]
            ) == .claim,
            "GUARD: leftover local-only rows still claim first auth user"
        )
        expect(
            InstallAccountGuard.evaluate(
                incoming: original,
                persistedBound: nil,
                localOwner: local,
                existingOwners: [original]
            ) == .claim,
            "GUARD: legacy store with original owner claims that owner"
        )
        expect(
            InstallAccountGuard.evaluate(
                incoming: other,
                persistedBound: nil,
                localOwner: local,
                existingOwners: [original]
            ) == .reject,
            "GUARD: legacy store rejects a different auth user"
        )
        expect(
            InstallAccountGuard.evaluate(
                incoming: original,
                persistedBound: nil,
                localOwner: local,
                existingOwners: [original, other]
            ) == .reject,
            "GUARD: two auth owners and no stamp fail closed"
        )
        expect(
            InstallAccountGuard.evaluate(
                incoming: other,
                persistedBound: nil,
                localOwner: local,
                existingOwners: [original, other]
            ) == .reject,
            "GUARD: two auth owners do not claim the other signer"
        )
        expect(
            InstallAccountGuard.evaluate(
                incoming: original,
                persistedBound: original,
                localOwner: local,
                existingOwners: [original, other]
            ) == .allow,
            "GUARD: stamp still allows the bound owner if leftover mixed rows exist"
        )
        return failures
    }
}
#endif
