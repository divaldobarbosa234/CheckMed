#if DEBUG
import Foundation
import SwiftData

/// Client protocol contracts use synthetic SwiftData only and never contact Supabase.
enum SyncProtocolContractChecks {
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
                doseTimes: ["09:00"],
                reason: "Synthetic reason",
                doctorName: "Synthetic clinician",
                hospitalName: "Synthetic clinic",
                doctorNotes: "Synthetic note"
            )
        }

        let disabled = SyncProtocolCapabilities(
            protocolVersion: 1,
            mutationRPCAvailable: true,
            directWritesEnforced: false,
            outboxConsumptionEnabled: false
        )
        let enforcedOnly = SyncProtocolCapabilities(
            protocolVersion: 1,
            mutationRPCAvailable: true,
            directWritesEnforced: true,
            outboxConsumptionEnabled: false
        )
        let serverReady = SyncProtocolCapabilities(
            protocolVersion: 1,
            mutationRPCAvailable: true,
            directWritesEnforced: true,
            outboxConsumptionEnabled: true
        )
        expect(disabled.mode == .legacy, "protocol: expansion alone cannot activate consumption")
        expect(enforcedOnly.mode == .legacy, "protocol: write enforcement alone cannot activate consumption")
        expect(
            serverReady.serverAllowsVersioned
                && !SyncProtocolActivation.outboxConsumptionAuthorized
                && serverReady.mode == .legacy,
            "protocol: this build keeps consumption unauthorized until explicit activation"
        )
        expect(
            (try? SyncProtocolDecision.resolve(
                capabilities: serverReady,
                clientAuthorized: false,
                wasProtected: false
            )) == .legacy,
            "protocol: unauthorized client stays legacy even when the server is ready"
        )
        expect(
            {
                do {
                    _ = try SyncProtocolDecision.resolve(
                        capabilities: enforcedOnly,
                        clientAuthorized: true,
                        wasProtected: true
                    )
                    return false
                } catch SyncProtocolDecision.Failure.unsafeRollback {
                    return true
                } catch {
                    return false
                }
            }(),
            "protocol: protected clients cannot fall back to legacy writes"
        )
        #if DEBUG
        expect(
            !SyncProtocolTestActivation.authorizes(
                url: URL(string: "https://CheckMed_Project.supabase.co")!,
                anonKey: SyncProtocolTestActivation.localDemoAnonKey
            ),
            "protocol: test activation rejects production hosts"
        )
        expect(
            SyncProtocolTestActivation.authorizes(
                url: SyncProtocolTestActivation.disposableURL,
                anonKey: SyncProtocolTestActivation.localDemoAnonKey
            ),
            "protocol: test activation accepts only the disposable local host"
        )
        #endif

        let owner = UUID()
        let subject = UUID()
        let store = CheckMedStore(isolatedInMemoryForContracts: true)
        store.debugContractBind(ownerId: owner, profileId: subject)
        guard let treatmentId = store.addFromDrafts(
            [draft("Protocol medicine")],
            ownerId: owner,
            profileId: subject,
            maximumActiveMedicines: Int.max
        ) else {
            return ["protocol: synthetic plan failed"]
        }
        guard let medicine = store.medicineSnapshots().first else {
            return ["protocol: synthetic medicine missing"]
        }
        let medicinePayload = SyncMutationPayload(medicine)
        expect(
            medicinePayload.reason == "Synthetic reason"
                && medicinePayload.doctorName == "Synthetic clinician"
                && medicinePayload.hospitalName == "Synthetic clinic"
                && medicinePayload.doctorNotes == "Synthetic note",
            "protocol: complete medicine fields enter the immutable payload"
        )
        expect(
            store.debugPendingSyncMutations(ownerId: owner).allSatisfy(\.hasPayload),
            "protocol: every new canonical intent has a durable payload"
        )

        store.debugSetPendingSyncMutationBaseVersion(
            ownerId: owner,
            entityType: .treatment,
            entityId: treatmentId,
            baseVersion: 0
        )
        guard let treatmentWork = try? store.prepareNextSyncMutation(ownerId: owner) else {
            return ["protocol: versioned treatment work was not prepared"]
        }
        var treatmentSnapshot = store.treatmentSnapshots().first { $0.id == treatmentId }!
        treatmentSnapshot.syncVersion = 1
        let treatmentResponse = response(
            for: treatmentWork,
            outcome: .applied,
            canonicalId: treatmentId,
            committedVersion: 1
        )
        expect(
            SyncProtocolValidation.responseMatches(treatmentResponse, work: treatmentWork),
            "protocol: exact acknowledgement is accepted"
        )
        var wrongMutation = treatmentResponse
        wrongMutation.mutationId = UUID()
        expect(
            !SyncProtocolValidation.responseMatches(wrongMutation, work: treatmentWork),
            "protocol: mismatched mutation acknowledgement is rejected"
        )
        expect(
            store.acknowledgeSyncMutation(
                treatmentWork,
                response: treatmentResponse,
                canonical: .treatment(treatmentSnapshot)
            ),
            "protocol: exact treatment acknowledgement commits locally"
        )

        store.debugSetPendingSyncMutationBaseVersion(
            ownerId: owner,
            entityType: .medicine,
            entityId: medicine.id,
            baseVersion: 0
        )
        guard let medicineWork = try? store.prepareNextSyncMutation(ownerId: owner) else {
            return failures + ["protocol: medicine work was not prepared"]
        }
        var acknowledgedMedicine = medicine
        acknowledgedMedicine.syncVersion = 1
        store.updateMedicineDetails(id: medicine.id, name: "Edit during flight")
        let medicineResponse = response(
            for: medicineWork,
            outcome: .applied,
            canonicalId: medicine.id,
            committedVersion: 1
        )
        expect(
            store.acknowledgeSyncMutation(
                medicineWork,
                response: medicineResponse,
                canonical: .medicine(acknowledgedMedicine)
            ),
            "protocol: first in-flight edit is acknowledged"
        )
        expect(
            store.debugMedicineName(medicine.id) == "Edit during flight",
            "protocol: acknowledgement does not overwrite a later local edit"
        )
        let remainingMedicine = store.debugPendingSyncMutations(ownerId: owner).first {
            $0.entityType == SyncMutationEntity.medicine.rawValue
                && $0.entityId == medicine.id
        }
        expect(
            remainingMedicine?.baseVersion == 1,
            "protocol: later edit advances to the acknowledged server version"
        )

        let doseStore = CheckMedStore(isolatedInMemoryForContracts: true)
        doseStore.debugContractBind(ownerId: owner, profileId: subject)
        let logId = UUID()
        _ = doseStore.debugInsertPlan(
            title: "Dose identity",
            status: "active",
            startDate: Date().addingTimeInterval(-86_400),
            endDate: Date().addingTimeInterval(86_400),
            medicineName: "Dose identity medicine",
            ownerId: owner,
            profileId: subject,
            logStatus: DoseLogStatus.pending.rawValue,
            logScheduledAt: Date().addingTimeInterval(-300),
            logId: logId
        )
        doseStore.debugPersistDoseAction(id: logId, action: .confirmTaken)
        // Notification semantics are covered by SyncOutboxContractChecks.
        // Isolate the alias assertion from stock mutations here.
        doseStore.debugStageDoseLogMutation(id: logId)
        doseStore.debugSetPendingSyncMutationBaseVersion(
            ownerId: owner,
            entityType: .doseLog,
            entityId: logId,
            baseVersion: 0
        )
        guard let doseWork = try? doseStore.prepareNextSyncMutation(ownerId: owner),
              var doseSnapshot = doseStore.logSnapshots().first(where: { $0.id == logId })
        else {
            return failures + ["protocol: DoseLog work was not prepared"]
        }
        let canonicalId = UUID()
        doseSnapshot.id = canonicalId
        doseSnapshot.syncVersion = 1
        let doseResponse = response(
            for: doseWork,
            outcome: .alreadyApplied,
            canonicalId: canonicalId,
            committedVersion: 1
        )
        expect(
            doseStore.acknowledgeSyncMutation(
                doseWork,
                response: doseResponse,
                canonical: .doseLog(doseSnapshot)
            ),
            "protocol: same-slot DoseLog acknowledgement commits"
        )
        expect(
            doseStore.debugDoseLogAlias(localId: logId) == canonicalId,
            "protocol: historical DoseLog UUID retains a canonical server alias"
        )
        expect(
            doseStore.debugDoseStatus(logId) == DoseLogStatus.taken.rawValue,
            "protocol: aliasing does not rekey or lose local DoseLog history"
        )

        expect(SyncMutationOutcome.applied.isAcknowledgement, "protocol: applied is acknowledgement")
        expect(SyncMutationOutcome.alreadyApplied.isAcknowledgement, "protocol: already_applied is acknowledgement")
        expect(SyncMutationOutcome.alreadyDeleted.isAcknowledgement, "protocol: already_deleted is acknowledgement")
        expect(!SyncMutationOutcome.conflict.isAcknowledgement, "protocol: conflict is not success")
        expect(!SyncMutationOutcome.parentDeleted.isAcknowledgement, "protocol: parent_deleted is not success")
        expect(!SyncMutationOutcome.invalid.isAcknowledgement, "protocol: invalid is not success")

        let subjectStore = CheckMedStore(isolatedInMemoryForContracts: true)
        subjectStore.debugContractBind(ownerId: owner, profileId: subject)
        guard let subjectTreatmentId = subjectStore.addFromDrafts(
            [draft("Missing subject medicine")],
            ownerId: owner,
            profileId: subject,
            maximumActiveMedicines: Int.max
        ) else {
            return failures + ["protocol: missing-subject fixture failed"]
        }
        subjectStore.debugSetPendingSyncMutationBaseVersion(
            ownerId: owner,
            entityType: .treatment,
            entityId: subjectTreatmentId,
            baseVersion: 0
        )
        subjectStore.debugClearPendingSyncMutationSubject(
            ownerId: owner,
            entityType: .treatment,
            entityId: subjectTreatmentId
        )
        let missingSubject = try? subjectStore.prepareNextSyncMutation(ownerId: owner)
        expect(missingSubject == nil, "protocol: missing subject cannot be uploaded")
        expect(
            subjectStore.debugPendingSyncMutations(ownerId: owner).contains {
                $0.entityType == SyncMutationEntity.treatment.rawValue
                    && $0.entityId == subjectTreatmentId
                    && $0.state == SyncMutationState.conflict.rawValue
                    && $0.conflictReason == "missing_subject"
            },
            "protocol: missing subject is retained as a conflict"
        )

        let reconcileOwner = UUID()
        let reconcileSubject = UUID()
        let reconcileStore = CheckMedStore(isolatedInMemoryForContracts: true)
        reconcileStore.debugContractBind(ownerId: reconcileOwner, profileId: reconcileSubject)
        guard let reconcileTreatmentId = reconcileStore.addFromDrafts(
            [draft("Reconcile medicine")],
            ownerId: reconcileOwner,
            profileId: reconcileSubject,
            maximumActiveMedicines: Int.max
        ), let reconcileTreatment = reconcileStore.treatmentSnapshots().first(where: {
            $0.id == reconcileTreatmentId
        }) else {
            return failures + ["protocol: reconcile fixture missing"]
        }
        var matchingRemote = reconcileTreatment
        matchingRemote.syncVersion = 4
        await reconcileStore.applyRemoteReplica(
            treatments: [matchingRemote],
            medicines: reconcileStore.medicineSnapshots().map { row in
                var copy = row
                copy.syncVersion = 4
                return copy
            },
            schedules: reconcileStore.scheduleSnapshots().map { row in
                var copy = row
                copy.syncVersion = 4
                return copy
            },
            logs: reconcileStore.logSnapshots().map { row in
                var copy = row
                copy.syncVersion = 4
                return copy
            },
            preservingLocalMutations: true
        )
        expect(
            reconcileStore.saveAfterVersionedSync(),
            "protocol: versioned replica save stays transactional"
        )
        expect(
            reconcileStore.debugPendingSyncMutations(ownerId: reconcileOwner).isEmpty,
            "protocol: identical unversioned pending intent is reconciled without a write"
        )

        let conflictStore = CheckMedStore(isolatedInMemoryForContracts: true)
        conflictStore.debugContractBind(ownerId: reconcileOwner, profileId: reconcileSubject)
        guard let conflictTreatmentId = conflictStore.addFromDrafts(
            [draft("Conflict medicine")],
            ownerId: reconcileOwner,
            profileId: reconcileSubject,
            maximumActiveMedicines: Int.max
        ), var conflictRemote = conflictStore.treatmentSnapshots().first(where: {
            $0.id == conflictTreatmentId
        }) else {
            return failures + ["protocol: conflict fixture missing"]
        }
        conflictRemote.title = "Server title"
        conflictRemote.syncVersion = 7
        await conflictStore.applyRemoteReplica(
            treatments: [conflictRemote],
            medicines: [],
            schedules: [],
            logs: [],
            preservingLocalMutations: true
        )
        expect(
            conflictStore.debugPendingSyncMutations(ownerId: reconcileOwner).contains {
                $0.entityType == SyncMutationEntity.treatment.rawValue
                    && $0.entityId == conflictTreatmentId
                    && $0.state == SyncMutationState.conflict.rawValue
                    && $0.conflictReason == "legacy_base_unknown"
            },
            "protocol: unversioned local/server divergence stays unresolved"
        )
        expect(
            conflictStore.debugTreatmentTitle(conflictTreatmentId) != "Server title",
            "protocol: unresolved local treatment is not overwritten by the replica"
        )

        let createStore = CheckMedStore(isolatedInMemoryForContracts: true)
        createStore.debugContractBind(ownerId: reconcileOwner, profileId: reconcileSubject)
        let localOnly = createStore.debugInsertPlan(
            title: "Local only",
            status: "active",
            startDate: Date(),
            endDate: nil,
            medicineName: "Local only medicine",
            ownerId: reconcileOwner,
            profileId: reconcileSubject
        )
        await createStore.applyRemoteReplica(
            treatments: [],
            medicines: [],
            schedules: [],
            logs: [],
            preservingLocalMutations: true
        )
        let created = createStore.debugPendingSyncMutations(ownerId: reconcileOwner)
        expect(
            created.contains {
                $0.entityType == SyncMutationEntity.treatment.rawValue
                    && $0.entityId == localOnly.treatmentId
                    && $0.state == SyncMutationState.pending.rawValue
                    && $0.baseVersion == 0
            },
            "protocol: local-only rows become expected-version-0 creates"
        )

        let mergeStore = CheckMedStore(isolatedInMemoryForContracts: true)
        mergeStore.debugContractBind(ownerId: reconcileOwner, profileId: reconcileSubject)
        await mergeStore.applyRemoteReplica(
            treatments: [
                TreatmentSnapshot(
                    id: UUID(),
                    ownerId: reconcileOwner,
                    profileId: reconcileSubject,
                    title: "Remote merge",
                    status: "active",
                    startDate: Date(),
                    endDate: nil,
                    updatedAt: Date(),
                    deletedAt: nil,
                    syncVersion: 3
                )
            ],
            medicines: [],
            schedules: [],
            logs: [],
            preservingLocalMutations: true
        )
        mergeStore.saveAfterSync()
        expect(
            mergeStore.debugPendingSyncMutations(ownerId: reconcileOwner).isEmpty,
            "protocol: remote merges do not generate outgoing mutations"
        )

        let historyStore = CheckMedStore(isolatedInMemoryForContracts: true)
        historyStore.debugContractBind(ownerId: reconcileOwner, profileId: reconcileSubject)
        let oldPendingId = UUID()
        let oldTakenId = UUID()
        let oldPendingAt = Date().addingTimeInterval(-5 * 86_400)
        let oldTakenAt = Date().addingTimeInterval(-4 * 86_400)
        _ = historyStore.debugInsertPlan(
            title: "History",
            status: "active",
            startDate: Date().addingTimeInterval(-10 * 86_400),
            endDate: Date().addingTimeInterval(86_400),
            medicineName: "History medicine",
            ownerId: reconcileOwner,
            profileId: reconcileSubject
        )
        guard let historyScheduleId = historyStore.scheduleSnapshots().first?.id else {
            return failures + ["protocol: history schedule missing"]
        }
        await historyStore.applyRemoteReplica(
            treatments: historyStore.treatmentSnapshots(),
            medicines: historyStore.medicineSnapshots(),
            schedules: historyStore.scheduleSnapshots(),
            logs: [
                DoseLogSnapshot(
                    id: oldPendingId,
                    scheduleId: historyScheduleId,
                    ownerId: reconcileOwner,
                    profileId: reconcileSubject,
                    scheduledAt: oldPendingAt,
                    status: DoseLogStatus.pending.rawValue,
                    loggedAt: nil,
                    updatedAt: oldPendingAt,
                    deletedAt: nil,
                    syncVersion: 1
                ),
                DoseLogSnapshot(
                    id: oldTakenId,
                    scheduleId: historyScheduleId,
                    ownerId: reconcileOwner,
                    profileId: reconcileSubject,
                    scheduledAt: oldTakenAt,
                    status: DoseLogStatus.taken.rawValue,
                    loggedAt: oldTakenAt,
                    updatedAt: oldTakenAt,
                    deletedAt: nil,
                    syncVersion: 1
                )
            ],
            preservingLocalMutations: true
        )
        expect(
            historyStore.debugDoseStatus(oldPendingId) == DoseLogStatus.pending.rawValue
                && historyStore.debugDoseStatus(oldTakenId) == DoseLogStatus.taken.rawValue,
            "protocol: versioned restoration keeps paginated historical DoseLogs"
        )

        let upgradeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("checkmed-protocol-upgrade-\(UUID().uuidString)", isDirectory: true)
        let upgradeURL = upgradeDirectory.appendingPathComponent("store.sqlite")
        do {
            try FileManager.default.createDirectory(
                at: upgradeDirectory,
                withIntermediateDirectories: true
            )
            let legacyTreatmentId = UUID()
            let legacySchema = Schema([
                TreatmentRecord.self,
                MedicineRecord.self,
                DoseScheduleRecord.self,
                DoseLogRecord.self,
                SyncMutationRecord.self,
                FeelingRecord.self,
                RewardGrant.self,
                CommunityCommentRecord.self,
            ])
            let legacyConfiguration = ModelConfiguration(
                "CheckMedOutboxContracts",
                schema: legacySchema,
                url: upgradeURL,
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
                    ownerId: reconcileOwner,
                    profileId: reconcileSubject,
                    title: "Pre-protocol treatment"
                )
            )
            try legacyContext.save()
            let upgraded = try CheckMedStore(contractStoreURL: upgradeURL)
            upgraded.debugContractBind(ownerId: reconcileOwner, profileId: reconcileSubject)
            expect(
                upgraded.debugActiveTreatmentIds().contains(legacyTreatmentId),
                "protocol: existing-store upgrade preserves canonical rows"
            )
            expect(
                upgraded.debugPendingSyncMutations(ownerId: reconcileOwner).isEmpty,
                "protocol: existing-store upgrade invents no outgoing mutations"
            )
        } catch {
            failures.append("protocol: existing-store upgrade failed")
        }
        try? FileManager.default.removeItem(at: upgradeDirectory)

        let staleStore = CheckMedStore(isolatedInMemoryForContracts: true)
        staleStore.debugContractBind(ownerId: owner, profileId: subject)
        guard let staleTreatmentId = staleStore.addFromDrafts(
            [draft("Stale version medicine")],
            ownerId: owner,
            profileId: subject,
            maximumActiveMedicines: Int.max
        ) else {
            return failures + ["protocol: stale-version fixture failed"]
        }
        staleStore.debugSetPendingSyncMutationBaseVersion(
            ownerId: owner,
            entityType: .treatment,
            entityId: staleTreatmentId,
            baseVersion: 1
        )
        guard let staleWork = try? staleStore.prepareNextSyncMutation(ownerId: owner) else {
            return failures + ["protocol: stale-version work was not prepared"]
        }
        let conflictResponse = response(
            for: staleWork,
            outcome: .conflict,
            canonicalId: staleWork.transportEntityId,
            committedVersion: 9,
            reason: "stale_version"
        )
        expect(
            !SyncProtocolValidation.responseMatches(conflictResponse, work: staleWork),
            "protocol: stale-version responses cannot acknowledge"
        )
        expect(
            staleStore.retainSyncConflict(staleWork, response: conflictResponse),
            "protocol: stale-version responses persist as conflicts"
        )

        return failures
    }

    private static func response(
        for work: SyncMutationWorkItem,
        outcome: SyncMutationOutcome,
        canonicalId: UUID,
        committedVersion: Int64?,
        reason: String? = nil
    ) -> SyncMutationRPCResponse {
        SyncMutationRPCResponse(
            protocolVersion: 1,
            mutationId: work.mutationId,
            outcome: outcome,
            entityType: work.entityType.rawValue,
            requestedEntityId: work.transportEntityId,
            canonicalEntityId: canonicalId,
            ownerId: work.ownerId,
            subjectProfileId: work.subjectProfileId,
            committedVersion: committedVersion,
            serverUpdatedAt: nil,
            canonicalRow: nil,
            affectedDescendants: [],
            reason: reason
        )
    }
}
#endif
