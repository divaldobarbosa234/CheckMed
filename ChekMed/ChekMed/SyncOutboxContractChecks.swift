#if DEBUG
import Foundation
import SwiftData

/// Durable outbox contracts. Uses synthetic data and never contacts Supabase.
enum SyncOutboxContractChecks {
    @MainActor
    static func failures() async -> [String] {
        var failures: [String] = []
        func expect(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }
        func draft(_ name: String) -> OnboardingPrescriptionDraft {
            OnboardingPrescriptionDraft(
                medicine: name,
                dose: "1 tablet",
                frequency: "1x",
                duration: "30 days",
                timesPerDay: "1",
                doseTimes: ["09:00"]
            )
        }

        let owner = UUID()
        let profile = UUID()
        let store = CheckMedStore(isolatedInMemoryForContracts: true)
        store.debugContractBind(ownerId: owner, profileId: profile)
        let treatmentId = store.addFromDrafts(
            [draft("Outbox One")],
            ownerId: owner,
            profileId: profile,
            maximumActiveMedicines: SuperLimits.freePrescriptions
        )
        expect(treatmentId != nil, "outbox: synthetic medicine persists")

        let initial = store.debugPendingSyncMutations(ownerId: owner)
        expect(!initial.isEmpty, "outbox: canonical mutation creates durable intent")
        expect(
            initial.allSatisfy { $0.ownerId == owner && $0.subjectProfileId == profile },
            "outbox: owner and subject profile remain distinct fields"
        )
        expect(
            initial.contains { $0.entityType == SyncMutationEntity.treatment.rawValue }
                && initial.contains { $0.entityType == SyncMutationEntity.medicine.rawValue }
                && initial.contains { $0.entityType == SyncMutationEntity.schedule.rawValue },
            "outbox: treatment, medicine and schedule creation are captured"
        )

        guard let medicineId = store.medicineSummaries().first?.id else {
            failures.append("outbox: missing synthetic medicine")
            return failures
        }
        guard let firstMedicineMutation = initial.first(where: {
            $0.entityType == SyncMutationEntity.medicine.rawValue && $0.entityId == medicineId
        }) else {
            failures.append("outbox: missing initial medicine mutation")
            return failures
        }
        store.debugSetPendingSyncMutationBaseVersion(
            ownerId: owner,
            entityType: .medicine,
            entityId: medicineId,
            baseVersion: 42
        )
        guard let basedMedicineMutation = store.debugPendingSyncMutations(ownerId: owner).first(where: {
            $0.entityType == SyncMutationEntity.medicine.rawValue && $0.entityId == medicineId
        }) else {
            failures.append("outbox: missing based medicine mutation")
            return failures
        }

        store.updateMedicineDetails(id: medicineId, name: "Outbox Two")
        store.updateMedicineDetails(id: medicineId, name: "Outbox Three")
        let editedMedicineMutations = store.debugPendingSyncMutations(ownerId: owner).filter {
            $0.entityType == SyncMutationEntity.medicine.rawValue && $0.entityId == medicineId
        }
        expect(editedMedicineMutations.count == 1, "outbox: repeated edits coalesce exactly once")
        expect(
            editedMedicineMutations.first?.id == firstMedicineMutation.id
                && firstMedicineMutation.id == basedMedicineMutation.id,
            "outbox: repeated edits preserve original mutation identity"
        )
        expect(
            editedMedicineMutations.first?.baseVersion == 42,
            "outbox: repeated edits preserve original base version"
        )

        let otherOwner = UUID()
        expect(
            store.debugPendingSyncMutations(ownerId: otherOwner).isEmpty,
            "outbox: another account cannot inspect pending owner intent"
        )
        expect(
            !store.debugPendingSyncMutations(ownerId: owner).isEmpty,
            "outbox: sign-out semantics retain owner-scoped pending intent"
        )

        let adoptedOwner = UUID()
        let adoptionStore = CheckMedStore(isolatedInMemoryForContracts: true)
        adoptionStore.debugContractBind(ownerId: owner, profileId: profile)
        _ = adoptionStore.addFromDrafts(
            [draft("Owner Adoption")],
            ownerId: owner,
            profileId: profile,
            maximumActiveMedicines: SuperLimits.freePrescriptions
        )
        let beforeAdoption = adoptionStore.debugPendingSyncMutations(ownerId: owner)
        let unrelatedOwner = UUID()
        adoptionStore.debugContractBind(ownerId: unrelatedOwner, profileId: profile)
        _ = adoptionStore.addFromDrafts(
            [draft("Unrelated Owner")],
            ownerId: unrelatedOwner,
            profileId: profile,
            maximumActiveMedicines: Int.max
        )
        let unrelatedBeforeAdoption = Set(
            adoptionStore.debugPendingSyncMutations(ownerId: unrelatedOwner).map(\.id)
        )
        adoptionStore.adoptOwner(from: owner, to: adoptedOwner, profileId: profile)
        let afterAdoption = adoptionStore.debugPendingSyncMutations(ownerId: adoptedOwner)
        expect(
            adoptionStore.debugPendingSyncMutations(ownerId: owner).isEmpty,
            "outbox: owner adoption leaves no stale prior-owner intent"
        )
        expect(
            Set(afterAdoption.map(\.id)) == Set(beforeAdoption.map(\.id)),
            "outbox: owner adoption preserves mutation identity"
        )
        expect(
            Set(adoptionStore.debugPendingSyncMutations(ownerId: unrelatedOwner).map(\.id))
                == unrelatedBeforeAdoption,
            "outbox: owner adoption does not transfer another owner's intent"
        )

        let beforeLegacy = Set(store.debugPendingSyncMutations(ownerId: owner).map(\.id))
        do {
            try await SyncTransportCycle.run(pull: { true }, push: { _ in })
        } catch {
            failures.append("outbox: synthetic legacy cycle unexpectedly failed")
        }
        let afterLegacy = Set(store.debugPendingSyncMutations(ownerId: owner).map(\.id))
        expect(!SyncMutationOutbox.legacyUploaderMayAcknowledge, "outbox: legacy acknowledgement is disabled")
        expect(beforeLegacy == afterLegacy, "outbox: legacy upload cannot acknowledge durable intent")

        store.deleteMedicine(id: medicineId)
        let deletion = store.debugPendingSyncMutations(ownerId: owner).first {
            $0.entityType == SyncMutationEntity.medicine.rawValue && $0.entityId == medicineId
        }
        expect(
            deletion?.operation == SyncMutationOperation.delete.rawValue,
            "outbox: deletion preserves tombstone intent"
        )
        expect(
            store.medicineSummaries().allSatisfy { $0.id != medicineId },
            "outbox: create-edit-delete cannot resurrect the medicine"
        )

        let notificationStore = CheckMedStore(isolatedInMemoryForContracts: true)
        notificationStore.debugContractBind(ownerId: owner, profileId: profile)
        let notificationLogId = UUID()
        _ = notificationStore.debugInsertPlan(
            title: "Notification",
            status: "active",
            startDate: Date().addingTimeInterval(-86_400),
            endDate: Date().addingTimeInterval(86_400),
            medicineName: "Notification medicine",
            ownerId: owner,
            profileId: profile,
            logStatus: DoseLogStatus.pending.rawValue,
            logScheduledAt: Date().addingTimeInterval(-300),
            logId: notificationLogId
        )
        notificationStore.debugPersistDoseAction(
            id: notificationLogId,
            action: .confirmTaken
        )
        let notificationMutations = notificationStore.debugPendingSyncMutations(ownerId: owner)
        notificationStore.debugPersistDoseAction(
            id: notificationLogId,
            action: .confirmTaken
        )
        let repeatedNotificationMutations = notificationStore.debugPendingSyncMutations(ownerId: owner)
        expect(
            notificationMutations.contains {
                $0.entityType == SyncMutationEntity.doseLog.rawValue
                    && $0.entityId == notificationLogId
                    && $0.operation == SyncMutationOperation.upsert.rawValue
            },
            "outbox: notification-originated dose action creates durable intent"
        )
        expect(
            repeatedNotificationMutations.filter {
                $0.entityType == SyncMutationEntity.doseLog.rawValue
                    && $0.entityId == notificationLogId
            }.count == 1,
            "outbox: repeated dose confirmation creates one logical obligation"
        )

        let generatedLogStore = CheckMedStore(isolatedInMemoryForContracts: true)
        generatedLogStore.debugContractBind(ownerId: owner, profileId: profile)
        _ = generatedLogStore.addFromDrafts(
            [draft("Generated Logs")],
            ownerId: owner,
            profileId: profile,
            maximumActiveMedicines: SuperLimits.freePrescriptions
        )
        let generatedBefore = generatedLogStore.debugPendingSyncMutations(ownerId: owner).filter {
            $0.entityType == SyncMutationEntity.doseLog.rawValue
        }.count
        generatedLogStore.refreshDoseLogsForDisplay()
        generatedLogStore.refreshDoseLogsForDisplay()
        let generatedAfter = generatedLogStore.debugPendingSyncMutations(ownerId: owner).filter {
            $0.entityType == SyncMutationEntity.doseLog.rawValue
        }.count
        expect(
            generatedAfter == generatedBefore,
            "outbox: repeated derived DoseLog generation stays bounded"
        )

        let remoteStore = CheckMedStore(isolatedInMemoryForContracts: true)
        remoteStore.debugContractBind(ownerId: owner, profileId: profile)
        await remoteStore.applyRemoteReplica(
            treatments: [
                TreatmentSnapshot(
                    id: UUID(),
                    ownerId: owner,
                    profileId: profile,
                    title: "Remote",
                    status: "active",
                    startDate: Date(),
                    endDate: nil,
                    updatedAt: Date(),
                    deletedAt: nil
                )
            ],
            medicines: [],
            schedules: [],
            logs: []
        )
        remoteStore.saveAfterSync()
        expect(
            remoteStore.debugPendingSyncMutations(ownerId: owner).isEmpty,
            "outbox: remote merge creates no outgoing mutation"
        )

        let persistentDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("checkmed-outbox-\(UUID().uuidString)", isDirectory: true)
        let persistentURL = persistentDirectory.appendingPathComponent("store.sqlite")
        do {
            try FileManager.default.createDirectory(
                at: persistentDirectory,
                withIntermediateDirectories: true
            )
            var persistedMutationIDs = Set<UUID>()
            do {
                let persistentStore = try CheckMedStore(contractStoreURL: persistentURL)
                persistentStore.debugContractBind(ownerId: owner, profileId: profile)
                _ = persistentStore.addFromDrafts(
                    [draft("Persistent")],
                    ownerId: owner,
                    profileId: profile,
                    maximumActiveMedicines: SuperLimits.freePrescriptions
                )
                persistedMutationIDs = Set(
                    persistentStore.debugPendingSyncMutations(ownerId: owner).map(\.id)
                )
                expect(!persistedMutationIDs.isEmpty, "outbox: persistent fixture commits intent")
            }
            do {
                let reopened = try CheckMedStore(contractStoreURL: persistentURL)
                reopened.debugContractBind(ownerId: owner, profileId: profile)
                let reopenedIDs = Set(reopened.debugPendingSyncMutations(ownerId: owner).map(\.id))
                expect(reopenedIDs == persistedMutationIDs, "outbox: pending intent survives reopening")
                expect(reopened.storedMedicineCount == 1, "outbox: canonical row survives with intent")
            }
        } catch {
            failures.append("outbox: persistent reopening failed")
        }
        try? FileManager.default.removeItem(at: persistentDirectory)

        let migrationDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("checkmed-outbox-migration-\(UUID().uuidString)", isDirectory: true)
        let migrationURL = migrationDirectory.appendingPathComponent("store.sqlite")
        do {
            try FileManager.default.createDirectory(
                at: migrationDirectory,
                withIntermediateDirectories: true
            )
            let legacyTreatmentId = UUID()
            do {
                let legacySchema = Schema([
                    TreatmentRecord.self,
                    MedicineRecord.self,
                    DoseScheduleRecord.self,
                    DoseLogRecord.self,
                    FeelingRecord.self,
                    RewardGrant.self,
                    CommunityCommentRecord.self,
                ])
                let legacyConfiguration = ModelConfiguration(
                    "CheckMedOutboxContracts",
                    schema: legacySchema,
                    url: migrationURL,
                    cloudKitDatabase: .none
                )
                let legacyContainer = try ModelContainer(
                    for: legacySchema,
                    configurations: [legacyConfiguration]
                )
                let legacyContext = ModelContext(legacyContainer)
                legacyContext.insert(
                    TreatmentRecord(
                        id: legacyTreatmentId,
                        ownerId: owner,
                        profileId: profile,
                        title: "Pre-outbox treatment"
                    )
                )
                try legacyContext.save()
            }
            let migratedStore = try CheckMedStore(contractStoreURL: migrationURL)
            migratedStore.debugContractBind(ownerId: owner, profileId: profile)
            expect(
                migratedStore.debugActiveTreatmentIds().contains(legacyTreatmentId),
                "outbox: adding the local model preserves pre-outbox canonical rows"
            )
            expect(
                migratedStore.debugPendingSyncMutations(ownerId: owner).isEmpty,
                "outbox: local schema migration invents no pending intent"
            )
        } catch {
            failures.append("outbox: pre-outbox local store migration failed")
        }
        try? FileManager.default.removeItem(at: migrationDirectory)

        let readOnlyDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("checkmed-outbox-readonly-\(UUID().uuidString)", isDirectory: true)
        let readOnlyURL = readOnlyDirectory.appendingPathComponent("store.sqlite")
        do {
            try FileManager.default.createDirectory(
                at: readOnlyDirectory,
                withIntermediateDirectories: true
            )
            do {
                _ = try CheckMedStore(contractStoreURL: readOnlyURL)
            }
            do {
                let readOnlyStore = try CheckMedStore(contractStoreURL: readOnlyURL, allowsSave: false)
                readOnlyStore.debugContractBind(ownerId: owner, profileId: profile)
                let result = readOnlyStore.addFromDrafts(
                    [draft("Must Roll Back")],
                    ownerId: owner,
                    profileId: profile,
                    maximumActiveMedicines: SuperLimits.freePrescriptions
                )
                expect(result == nil, "outbox: failed persistence rejects canonical mutation")
            }
            let afterRejectedSave = try CheckMedStore(contractStoreURL: readOnlyURL)
            afterRejectedSave.debugContractBind(ownerId: owner, profileId: profile)
            expect(
                afterRejectedSave.debugPendingSyncMutations(ownerId: owner).isEmpty,
                "outbox: failed persistence commits no durable pending intent"
            )
            expect(
                afterRejectedSave.debugLiveRecordCounts().medicines == 0,
                "outbox: failed persistence commits no canonical rows"
            )
        } catch {
            failures.append("outbox: read-only failure fixture could not be created")
        }
        try? FileManager.default.removeItem(at: readOnlyDirectory)

        notificationStore.eraseOwnedLocalData(ownerId: owner)
        expect(
            notificationStore.debugPendingSyncMutations(ownerId: owner).isEmpty,
            "outbox: account deletion removes pending replay intent"
        )

        return failures
    }
}
#endif
