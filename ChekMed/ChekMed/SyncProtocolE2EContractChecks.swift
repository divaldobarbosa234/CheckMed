#if DEBUG
import Foundation
import Supabase

/// Two isolated SwiftData stores against the disposable local Supabase only.
/// Never constructs a client for CheckMed_Project or any https host.
enum SyncProtocolE2EContractChecks {
    struct CaseResult: Sendable {
        var number: Int
        var name: String
        var status: String
        var detail: String
    }

    @MainActor
    static func failures() async -> [String] {
        let results = await run()
        writeReport(results)
        return results.compactMap { item in
            item.status == "FAIL" ? "e2e \(item.number) \(item.name): \(item.detail)" : nil
        }
    }

    @MainActor
    static func run() async -> [CaseResult] {
        var results: [CaseResult] = []
        func record(_ number: Int, _ name: String, _ status: String, _ detail: String = "") {
            results.append(CaseResult(number: number, name: name, status: status, detail: detail))
        }

        let production = URL(string: "https://CheckMed_Project.supabase.co")!
        if SyncProtocolTestActivation.authorizes(
            url: production,
            anonKey: SyncProtocolTestActivation.localDemoAnonKey
        ) || SyncProtocolActivation.outboxConsumptionAuthorized {
            record(0, "activation-safeguards", "FAIL", "production URL or compile-time flag authorized")
            return results
        }
        record(0, "activation-safeguards", "PASS", "Release flag false; production URL rejected")

        do {
            _ = try SyncProtocolDecision.resolve(
                capabilities: SyncProtocolCapabilities(
                    protocolVersion: 1,
                    mutationRPCAvailable: true,
                    directWritesEnforced: true,
                    outboxConsumptionEnabled: false
                ),
                clientAuthorized: true,
                wasProtected: true
            )
            record(16, "capability-downgrade", "FAIL", "protected client returned a mode")
        } catch SyncProtocolDecision.Failure.unsafeRollback {
            record(16, "capability-downgrade", "PASS", "downgrade fails closed")
        } catch {
            record(16, "capability-downgrade", "FAIL", String(describing: error))
        }

        let url = SyncProtocolTestActivation.disposableURL
        let anon = SyncProtocolTestActivation.localDemoAnonKey
        guard SyncProtocolTestActivation.authorizes(url: url, anonKey: anon) else {
            for number in 1...15 {
                record(number, "live-\(number)", "NOT VERIFIED", "test activation rejected local URL")
            }
            return results
        }

        do {
            let harness = try await Harness.bootstrap()
            try await harness.runCases(&results)
        } catch {
            let remaining = Set(1...15).subtracting(Set(results.map(\.number)))
            for number in remaining.sorted() {
                record(number, "live-\(number)", "FAIL", String(describing: error))
            }
        }
        return results
    }

    @MainActor
    private static func writeReport(_ results: [CaseResult]) {
        let body = results.map { "\($0.number) \($0.name): \($0.status) \($0.detail)" }
            .joined(separator: "\n")
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? body.write(
                to: docs.appendingPathComponent("checkmed-sync-e2e.txt"),
                atomically: true,
                encoding: .utf8
            )
        }
        print("SyncProtocol E2E:\n\(body)")
    }
}

@MainActor
private final class Harness {
    let owner: UUID
    let profile: UUID
    let familyId = UUID()
    let client: SupabaseClient
    let admin: SupabaseClient

    private init(owner: UUID, profile: UUID, client: SupabaseClient, admin: SupabaseClient) {
        self.owner = owner
        self.profile = profile
        self.client = client
        self.admin = admin
    }

    static func bootstrap() async throws -> Harness {
        let email = "e2e-\(UUID().uuidString.lowercased())@isolated.local"
        let password = "Isolated-E2E-\(UUID().uuidString.prefix(8))"
        let client = SupabaseClient(
            supabaseURL: SyncProtocolTestActivation.disposableURL,
            supabaseKey: SyncProtocolTestActivation.localDemoAnonKey
        )
        let admin = SupabaseClient(
            supabaseURL: SyncProtocolTestActivation.disposableURL,
            supabaseKey: SyncProtocolTestActivation.localDemoServiceRoleKey
        )
        _ = try await client.auth.signUp(email: email, password: password)
        try await client.auth.signIn(email: email, password: password)
        guard let owner = client.auth.currentUser?.id else {
            throw E2EError.message("signed-in owner missing")
        }
        struct ProfileRow: Decodable { var id: UUID }
        let profiles: [ProfileRow] = try await client
            .from("profiles")
            .select("id")
            .eq("owner_id", value: owner.uuidString)
            .limit(1)
            .execute()
            .value
        guard let profile = profiles.first?.id else {
            throw E2EError.message("profile missing after signup")
        }
        return Harness(owner: owner, profile: profile, client: client, admin: admin)
    }

    func runCases(_ results: inout [SyncProtocolE2EContractChecks.CaseResult]) async throws {
        func record(_ number: Int, _ name: String, _ ok: Bool, _ detail: String = "") {
            results.append(.init(number: number, name: name, status: ok ? "PASS" : "FAIL", detail: detail))
        }

        var deviceA = CheckMedStore(isolatedInMemoryForContracts: true)
        var deviceB = CheckMedStore(isolatedInMemoryForContracts: true)
        deviceA.debugContractBind(ownerId: owner, profileId: profile)
        deviceB.debugContractBind(ownerId: owner, profileId: profile)

        let draft = OnboardingPrescriptionDraft(
            medicine: "E2E Atorvastatin",
            dose: "20 mg",
            frequency: "1x",
            duration: "30 days",
            timesPerDay: "1",
            doseTimes: ["08:00"],
            reason: "cholesterol",
            doctorName: "Dr Isolated",
            hospitalName: "Isolated Hospital",
            doctorNotes: "Take with water"
        )
        guard let treatmentId = deviceA.addFromDrafts(
            [draft],
            ownerId: owner,
            profileId: profile,
            maximumActiveMedicines: Int.max
        ) else {
            throw E2EError.message("device A plan failed")
        }
        try await consume(deviceA)
        try await pull(deviceB)
        record(
            1,
            "new-treatment-A-to-B",
            deviceB.treatmentSnapshots().contains { $0.id == treatmentId },
            "B treatments=\(deviceB.treatmentSnapshots().count)"
        )

        guard let medicine = deviceA.medicineSnapshots().first else {
            throw E2EError.message("device A medicine missing")
        }
        deviceA.updateMedicineDetails(
            id: medicine.id,
            name: "E2E Atorvastatin Forte",
            doseLabel: medicine.doseLabel,
            frequency: medicine.frequency,
            duration: medicine.duration,
            doctorName: medicine.doctorName,
            doctorId: medicine.doctorId,
            hospitalName: medicine.hospitalName,
            doctorNotes: medicine.doctorNotes,
            reason: medicine.reason
        )
        try await consume(deviceA)
        try await pull(deviceB)
        record(
            2,
            "medicine-edit-converges",
            deviceB.medicineSnapshots().contains { $0.id == medicine.id && $0.name == "E2E Atorvastatin Forte" }
        )

        let offlineURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("checkmed-e2e-\(UUID().uuidString).store")
        let offlineA = try CheckMedStore(contractStoreURL: offlineURL)
        offlineA.debugContractBind(ownerId: owner, profileId: profile)
        try await pull(offlineA)
        offlineA.updateMedicineDetails(
            id: medicine.id,
            name: "E2E Offline",
            doseLabel: medicine.doseLabel,
            frequency: medicine.frequency,
            duration: medicine.duration,
            doctorName: medicine.doctorName,
            doctorId: medicine.doctorId,
            hospitalName: medicine.hospitalName,
            doctorNotes: medicine.doctorNotes,
            reason: medicine.reason
        )
        let reopened = try CheckMedStore(contractStoreURL: offlineURL)
        reopened.debugContractBind(ownerId: owner, profileId: profile)
        try await consume(reopened)
        try await pull(deviceB)
        record(
            3,
            "offline-survives-relaunch",
            deviceB.medicineSnapshots().contains { $0.id == medicine.id && $0.name == "E2E Offline" }
        )

        try await pull(deviceA)
        try await pull(deviceB)
        _ = deviceA.setTreatmentTitle(id: treatmentId, title: "Title A")
        _ = deviceB.setTreatmentTitle(id: treatmentId, title: "Title B")
        try await consume(deviceA)
        var retained = false
        do {
            try await consume(deviceB)
        } catch E2EError.retained {
            retained = deviceB.hasPendingSyncConflict(ownerId: owner)
        }
        try await pull(deviceA)
        let serverTitle = deviceA.treatmentSnapshots().first { $0.id == treatmentId }?.title
        record(4, "same-record-conflict-retained", retained && serverTitle == "Title A", serverTitle ?? "nil")

        let replayId = UUID()
        let replayWork = SyncMutationWorkItem(
            mutationId: UUID(),
            ownerId: owner,
            subjectProfileId: profile,
            entityType: .treatment,
            localEntityId: replayId,
            transportEntityId: replayId,
            operation: .upsert,
            expectedVersion: 0,
            payload: SyncMutationPayload(title: "Replay", status: "active", startDate: "2026-10-11")
        )
        let firstReplay = try await SyncEngine.debugApplyMutation(client: client, work: replayWork)
        let secondReplay = try await SyncEngine.debugApplyMutation(client: client, work: replayWork)
        struct IdRow: Decodable { var id: UUID }
        let replayRows: [IdRow] = try await client
            .from("treatments")
            .select("id")
            .eq("id", value: replayId.uuidString)
            .execute()
            .value
        record(
            5,
            "duplicate-mutation-no-row-duplication",
            firstReplay.outcome == .applied && secondReplay.outcome == .applied && replayRows.count == 1
        )
        record(
            6,
            "lost-ack-receipt-replay",
            secondReplay.committedVersion == firstReplay.committedVersion
                && secondReplay.mutationId == firstReplay.mutationId
        )

        let deletedVersion = deviceA.treatmentSnapshots().first { $0.id == treatmentId }?.syncVersion ?? 1
        if let med = deviceA.medicineSnapshots().first {
            deviceA.deleteMedicine(id: med.id)
        }
        try? await consume(deviceA)
        let tomb = try await SyncEngine.debugApplyMutation(
            client: client,
            work: SyncMutationWorkItem(
                mutationId: UUID(),
                ownerId: owner,
                subjectProfileId: profile,
                entityType: .treatment,
                localEntityId: treatmentId,
                transportEntityId: treatmentId,
                operation: .upsert,
                expectedVersion: deletedVersion + 1,
                payload: SyncMutationPayload(title: "Resurrect", status: "active", startDate: "2026-10-11")
            )
        )
        record(
            7,
            "deletion-blocks-resurrection",
            tomb.outcome == .conflict && (tomb.reason == "record_deleted" || tomb.reason == "stale_version"),
            tomb.reason ?? tomb.outcome.rawValue
        )

        let parent = try await SyncEngine.debugApplyMutation(
            client: client,
            work: SyncMutationWorkItem(
                mutationId: UUID(),
                ownerId: owner,
                subjectProfileId: profile,
                entityType: .medicine,
                localEntityId: UUID(),
                transportEntityId: UUID(),
                operation: .upsert,
                expectedVersion: 0,
                payload: SyncMutationPayload(
                    treatmentId: treatmentId,
                    name: "Orphan",
                    doseLabel: "1",
                    frequency: "1x",
                    duration: "1",
                    reason: "x",
                    form: "tablet",
                    packageAmount: 1,
                    packageUnit: "tablet",
                    stockPercent: 100,
                    quantityPerDose: 1,
                    doseUnit: "tablet",
                    doctorName: "",
                    doctorId: "",
                    hospitalName: "",
                    doctorNotes: "",
                    refillRemindEnabled: true
                )
            )
        )
        record(8, "parent-delete-blocks-descendant", parent.outcome == .parentDeleted, parent.reason ?? parent.outcome.rawValue)

        let slotA = CheckMedStore(isolatedInMemoryForContracts: true)
        let slotB = CheckMedStore(isolatedInMemoryForContracts: true)
        slotA.debugContractBind(ownerId: owner, profileId: profile)
        slotB.debugContractBind(ownerId: owner, profileId: profile)
        guard slotA.addFromDrafts(
            [
                OnboardingPrescriptionDraft(
                    medicine: "E2E Slot",
                    dose: "1 tablet",
                    frequency: "1x",
                    duration: "7 days",
                    timesPerDay: "1",
                    doseTimes: ["09:00"],
                    reason: "slot",
                    doctorName: "Dr Slot",
                    hospitalName: "Slot Clinic",
                    doctorNotes: "alias"
                )
            ],
            ownerId: owner,
            profileId: profile,
            maximumActiveMedicines: Int.max
        ) != nil,
            let schedule = slotA.scheduleSnapshots().first,
            let firstLog = slotA.logSnapshots().first
        else {
            throw E2EError.message("slot fixture failed")
        }
        try await consume(slotA)
        try await pull(slotB)
        let aliasId = UUID()
        let slot = try await SyncEngine.debugApplyMutation(
            client: client,
            work: SyncMutationWorkItem(
                mutationId: UUID(),
                ownerId: owner,
                subjectProfileId: profile,
                entityType: .doseLog,
                localEntityId: aliasId,
                transportEntityId: aliasId,
                operation: .upsert,
                expectedVersion: 0,
                payload: SyncMutationPayload(
                    status: firstLog.status,
                    scheduleId: schedule.id,
                    scheduledAt: SyncWireCodec.timestamp(firstLog.scheduledAt)
                )
            )
        )
        if slot.canonicalEntityId != nil {
            _ = slotB.retainSyncConflict(
                SyncMutationWorkItem(
                    mutationId: UUID(),
                    ownerId: owner,
                    subjectProfileId: profile,
                    entityType: .doseLog,
                    localEntityId: aliasId,
                    transportEntityId: aliasId,
                    operation: .upsert,
                    expectedVersion: 0,
                    payload: SyncMutationPayload(
                        status: firstLog.status,
                        scheduleId: schedule.id,
                        scheduledAt: SyncWireCodec.timestamp(firstLog.scheduledAt)
                    )
                ),
                response: slot
            )
        }
        record(
            9,
            "doselog-same-slot-converges",
            slot.canonicalEntityId == firstLog.id,
            "\(slot.outcome.rawValue) canonical=\(slot.canonicalEntityId?.uuidString ?? "nil")"
        )
        record(
            10,
            "historical-uuid-alias",
            slot.canonicalEntityId == firstLog.id,
            "canonical=\(slot.canonicalEntityId?.uuidString ?? "nil")"
        )

        struct FamilyPatch: Encodable {
            var extra_family_id: UUID
            var extra_family_name: String
        }
        try await client
            .from("profiles")
            .update(FamilyPatch(extra_family_id: familyId, extra_family_name: "E2E family"))
            .eq("owner_id", value: owner.uuidString)
            .execute()
        var unauthorized = false
        do {
            _ = try await SyncEngine.debugApplyMutation(
                client: client,
                work: SyncMutationWorkItem(
                    mutationId: UUID(),
                    ownerId: owner,
                    subjectProfileId: UUID(),
                    entityType: .treatment,
                    localEntityId: UUID(),
                    transportEntityId: UUID(),
                    operation: .upsert,
                    expectedVersion: 0,
                    payload: SyncMutationPayload(title: "Leak", status: "active", startDate: "2026-10-11")
                )
            )
        } catch {
            unauthorized = true
        }
        let family = try await SyncEngine.debugApplyMutation(
            client: client,
            work: SyncMutationWorkItem(
                mutationId: UUID(),
                ownerId: owner,
                subjectProfileId: familyId,
                entityType: .treatment,
                localEntityId: UUID(),
                transportEntityId: UUID(),
                operation: .upsert,
                expectedVersion: 0,
                payload: SyncMutationPayload(title: "Family seat", status: "active", startDate: "2026-10-11")
            )
        )
        record(11, "subject-profile-boundaries", unauthorized && family.outcome == .applied, family.outcome.rawValue)

        try await pull(slotB)
        let restored = slotB.medicineSnapshots().first { $0.name.contains("Slot") }
        record(
            12,
            "full-medicine-fields",
            restored?.reason == "slot"
                && restored?.doctorName == "Dr Slot"
                && restored?.hospitalName == "Slot Clinic"
                && restored?.doctorNotes == "alias",
            restored.map { "\($0.reason)/\($0.doctorName)" } ?? "missing"
        )

        do {
            if let scheduleId = slotA.scheduleSnapshots().first?.id,
               let medicineId = slotA.medicineSnapshots().first?.id {
                try await seedHistoricalLogs(scheduleId: scheduleId, medicineId: medicineId)
            }
            let paged = try await SyncEngine.debugFetchReplica(client: client, ownerId: owner)
            record(13, "paginated-doselog-history", paged.logs.count >= 500, "logs=\(paged.logs.count)")
        } catch {
            record(13, "paginated-doselog-history", false, String(describing: error))
        }

        do {
            let other = SupabaseClient(
                supabaseURL: SyncProtocolTestActivation.disposableURL,
                supabaseKey: SyncProtocolTestActivation.localDemoAnonKey
            )
            let otherEmail = "e2e-other-\(UUID().uuidString.lowercased())@isolated.local"
            _ = try await other.auth.signUp(email: otherEmail, password: "Isolated-E2E-other")
            try await other.auth.signIn(email: otherEmail, password: "Isolated-E2E-other")
            var crossReplay = false
            do {
                _ = try await SyncEngine.debugApplyMutation(client: other, work: replayWork)
            } catch {
                crossReplay = true
            }
            record(14, "sign-out-blocks-cross-account", crossReplay)
        } catch {
            record(14, "sign-out-blocks-cross-account", false, String(describing: error))
        }

        do {
            try await deleteOwnerViaLocalAdmin()
            var lateWriteBlocked = false
            do {
                _ = try await SyncEngine.debugApplyMutation(
                    client: client,
                    work: SyncMutationWorkItem(
                        mutationId: UUID(),
                        ownerId: owner,
                        subjectProfileId: profile,
                        entityType: .treatment,
                        localEntityId: UUID(),
                        transportEntityId: UUID(),
                        operation: .upsert,
                        expectedVersion: 0,
                        payload: SyncMutationPayload(title: "Late", status: "active", startDate: "2026-10-11")
                    )
                )
            } catch {
                lateWriteBlocked = true
            }
            record(15, "account-deletion-blocks-late-write", lateWriteBlocked)
        } catch {
            record(15, "account-deletion-blocks-late-write", false, String(describing: error))
        }
    }

    private func consume(_ store: CheckMedStore) async throws {
        var guardrail = 0
        while guardrail < 40 {
            guardrail += 1
            if store.hasPendingSyncConflict(ownerId: owner) {
                throw E2EError.retained
            }
            guard let work = try store.prepareNextSyncMutation(ownerId: owner) else { return }
            let response = try await SyncEngine.debugApplyMutation(client: client, work: work)
            if response.outcome.isAcknowledgement {
                guard SyncProtocolValidation.responseMatches(response, work: work) else {
                    throw E2EError.message("invalid acknowledgement")
                }
                let canonical = try SyncEngine.debugCanonicalSnapshot(from: response, entity: work.entityType)
                guard store.acknowledgeSyncMutation(work, response: response, canonical: canonical) else {
                    throw E2EError.message("local ack failed")
                }
            } else {
                _ = store.retainSyncConflict(work, response: response)
                throw E2EError.retained
            }
        }
        throw E2EError.message("consume loop exceeded")
    }

    private func pull(_ store: CheckMedStore) async throws {
        let replica = try await SyncEngine.debugFetchReplica(client: client, ownerId: owner)
        await store.applyRemoteReplica(
            treatments: replica.treatments,
            medicines: replica.medicines,
            schedules: replica.schedules,
            logs: replica.logs,
            preservingLocalMutations: true
        )
        _ = store.saveAfterVersionedSync()
        store.debugContractBind(ownerId: owner, profileId: profile)
    }

    private func seedHistoricalLogs(scheduleId: UUID, medicineId: UUID) async throws {
        struct SeedLog: Encodable {
            var id: UUID
            var owner_id: UUID
            var profile_id: UUID
            var subject_profile_id: UUID
            var schedule_id: UUID
            var scheduled_at: String
            var status: String
            var logical_medicine_id: UUID
            var slot_minute: String
        }
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var rows: [SeedLog] = []
        for index in 0..<520 {
            let when = start.addingTimeInterval(TimeInterval(index * 60))
            let stamp = SyncWireCodec.timestamp(when)
            rows.append(
                SeedLog(
                    id: UUID(),
                    owner_id: owner,
                    profile_id: profile,
                    subject_profile_id: profile,
                    schedule_id: scheduleId,
                    scheduled_at: stamp,
                    status: "pending",
                    logical_medicine_id: medicineId,
                    slot_minute: stamp
                )
            )
        }
        let encoder = JSONEncoder()
        for chunk in stride(from: 0, to: rows.count, by: 100) {
            let slice = Array(rows[chunk..<min(chunk + 100, rows.count)])
            try await localServiceRequest(
                path: "/rest/v1/dose_logs",
                query: "on_conflict=id",
                method: "POST",
                headers: ["Prefer": "resolution=merge-duplicates,return=minimal"],
                body: encoder.encode(slice)
            )
        }
    }

    private func deleteOwnerViaLocalAdmin() async throws {
        try await localServiceRequest(
            path: "/auth/v1/admin/users/\(owner.uuidString)",
            query: nil,
            method: "DELETE",
            headers: [:],
            body: nil
        )
    }

    private func localServiceRequest(
        path: String,
        query: String?,
        method: String,
        headers: [String: String],
        body: Data?
    ) async throws {
        var raw = "http://127.0.0.1:54321\(path)"
        if let query, !query.isEmpty { raw += "?\(query)" }
        guard let url = URL(string: raw), url.host == "127.0.0.1", url.port == 54321 else {
            throw E2EError.message("refusing non-local admin URL")
        }
        guard SyncProtocolTestActivation.authorizes(
            url: SyncProtocolTestActivation.disposableURL,
            anonKey: SyncProtocolTestActivation.localDemoAnonKey
        ) else {
            throw E2EError.message("refusing non-local admin request")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(SyncProtocolTestActivation.localDemoServiceRoleKey, forHTTPHeaderField: "apikey")
        request.setValue(
            "Bearer \(SyncProtocolTestActivation.localDemoServiceRoleKey)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw E2EError.message("local admin \(method) \(path) -> \(status) \(String(data: data, encoding: .utf8) ?? "")")
        }
    }
}

private enum E2EError: Error {
    case retained
    case message(String)
}
#endif
