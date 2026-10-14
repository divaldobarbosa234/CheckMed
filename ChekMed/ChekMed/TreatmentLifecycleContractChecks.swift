#if DEBUG
import Foundation

/// Lifecycle consistency: classification vs stored status. Does not write production data.
enum TreatmentLifecycleContractChecks {
    @MainActor
    static func failures() -> [String] {
        var failures: [String] = []
        func expect(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let lastWeek = calendar.date(byAdding: .day, value: -10, to: today)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let nextMonth = calendar.date(byAdding: .day, value: 30, to: today)!
        let midday: (Date) -> Date = { day in
            calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        }
        let todayNoon = midday(today)
        let yesterdayNoon = midday(yesterday)
        let tomorrowNoon = midday(tomorrow)

        expect(
            TreatmentJourneyClassification.classify(
                deletedAt: nil,
                status: "active",
                startDate: lastWeek,
                endDate: yesterday,
                now: now,
                calendar: calendar
            ) == .past,
            "A: date-expired stored-active classifies PAST"
        )
        expect(
            TreatmentJourneyClassification.classify(
                deletedAt: nil,
                status: "active",
                startDate: lastWeek,
                endDate: today,
                now: now,
                calendar: calendar
            ) == .current,
            "B: date-valid stored-active classifies CURRENT"
        )
        expect(
            TreatmentJourneyClassification.classify(
                deletedAt: nil,
                status: "active",
                startDate: tomorrow,
                endDate: nextMonth,
                now: now,
                calendar: calendar
            ) == .future,
            "C: future start classifies FUTURE"
        )

        let store = CheckMedStore(isolatedInMemoryForContracts: true)
        let owner = UUID()
        let profile = UUID()
        store.debugContractBind(ownerId: owner, profileId: profile)

        let past = store.debugInsertPlan(
            title: "Past course",
            status: "active",
            startDate: lastWeek,
            endDate: yesterday,
            medicineName: "ExpiredMed",
            ownerId: owner,
            profileId: profile,
            logStatus: DoseLogStatus.missed.rawValue,
            logScheduledAt: yesterdayNoon
        )
        _ = store.debugInsertPlan(
            title: "Past pending",
            status: "active",
            startDate: lastWeek,
            endDate: yesterday,
            medicineName: "PastPending",
            ownerId: owner,
            profileId: profile,
            logStatus: DoseLogStatus.pending.rawValue,
            logScheduledAt: tomorrowNoon
        )
        expect(store.debugLifecycleKind(treatmentId: past.treatmentId) == .past, "A: store lifecycle PAST")
        expect(store.debugActiveTreatmentIds().contains(past.treatmentId), "A: activeTreatments still contains expired")
        expect(!store.debugCurrentTreatmentIds().contains(past.treatmentId), "A: currentTreatments excludes expired")
        expect(store.debugTreatmentStatus(past.treatmentId) == "active", "A: stored status remains active")
        expect(store.debugTreatmentCompleteGrantCount() == 0, "A: no completion RewardGrant from expiry")
        expect(store.medicineSummaries().allSatisfy { $0.treatmentId != past.treatmentId }, "A: live summaries exclude PAST")
        expect(store.storedMedicineCount == 0, "A: PAST medicines do not occupy slots")
        expect(store.todayNodes().isEmpty, "A: todayNodes exclude PAST")
        expect(store.reminderDrafts(now: now).isEmpty, "K: PAST has no live reminder drafts")
        expect(store.reportCurrentMedicines().isEmpty, "L: current medicines exclude PAST")
        expect(!store.unresolvedDosesForSummary(now: now).isEmpty, "H: final-day missed remains recoverable")

        let adherencePast = store.adherence()
        expect(adherencePast.treatmentCount == 2, "J: adherence still counts stored-active PAST treatments")

        let current = store.debugInsertPlan(
            title: "Current course",
            status: "active",
            startDate: lastWeek,
            endDate: nextMonth,
            medicineName: "CurrentMed",
            ownerId: owner,
            profileId: profile,
            logStatus: DoseLogStatus.pending.rawValue,
            logScheduledAt: todayNoon
        )
        expect(store.debugLifecycleKind(treatmentId: current.treatmentId) == .current, "B: store lifecycle CURRENT")
        expect(store.debugCurrentTreatmentIds() == [current.treatmentId], "F: CURRENT readers select only current")
        expect(store.debugActiveTreatmentIds().contains(past.treatmentId), "F: stored-active still includes PAST")
        expect(store.debugActiveTreatmentIds().contains(current.treatmentId), "F: stored-active includes CURRENT")
        expect(store.medicineSummaries().map(\.treatmentId) == [current.treatmentId], "B: live summaries are CURRENT")
        expect(store.todayNodes().contains(where: { $0.medicine == "CurrentMed" }), "B: todayNodes include CURRENT")
        expect(!store.todayNodes().contains(where: { $0.medicine == "ExpiredMed" }), "F: todayNodes ignore PAST sibling")
        expect(store.hasCurrentTreatment, "B: hasCurrentTreatment true")
        expect(
            LaterAddPersist.target(intent: .addToCurrent, hasCurrentTreatment: store.hasCurrentTreatment) == .addToActive,
            "E: persist target add-to-current when CURRENT exists"
        )

        let future = store.debugInsertPlan(
            title: "Future course",
            status: "active",
            startDate: tomorrow,
            endDate: nextMonth,
            medicineName: "FutureMed",
            ownerId: owner,
            profileId: profile
        )
        expect(store.debugLifecycleKind(treatmentId: future.treatmentId) == .future, "C: store lifecycle FUTURE")
        expect(!store.debugCurrentTreatmentIds().contains(future.treatmentId), "C: FUTURE is not CURRENT")
        expect(!store.todayNodes().contains(where: { $0.medicine == "FutureMed" }), "C: no today dose presentation for FUTURE")
        expect(store.storedMedicineCount == 2, "G: slots count CURRENT + FUTURE, exclude PAST")
        expect(SuperLimits.freePrescriptions == 3, "G: Free numeric limit unchanged")

        let grantsBeforeAppend = store.debugRewardGrantCount()
        let newId = store.addFromDrafts(
            [
                OnboardingPrescriptionDraft(
                    medicine: "NewMed",
                    dose: "1 tablet",
                    frequency: "1x",
                    duration: "5 days",
                    timesPerDay: "1",
                    doseTimes: ["09:00"]
                )
            ],
            ownerId: owner,
            profileId: profile,
            maximumActiveMedicines: SuperLimits.superPrescriptions
        )
        expect(newId == current.treatmentId, "E/F: append targets CURRENT id, not stored-active .first")
        expect(store.debugTreatmentStatus(past.treatmentId) == "active", "D/E: expired status unchanged by append")
        expect(store.debugRewardGrantCount() == grantsBeforeAppend, "E: append does not grant completion XP")

        let pastOnly = CheckMedStore(isolatedInMemoryForContracts: true)
        pastOnly.debugContractBind(ownerId: owner, profileId: profile)
        let expiredOnly = pastOnly.debugInsertPlan(
            title: "Expired only",
            status: "active",
            startDate: lastWeek,
            endDate: yesterday,
            medicineName: "OldOnly",
            ownerId: owner,
            profileId: profile
        )
        expect(!pastOnly.hasCurrentTreatment, "D: PAST-only is not current")
        expect(
            LaterAddPersist.target(intent: .addToCurrent, hasCurrentTreatment: pastOnly.hasCurrentTreatment) == .seed,
            "D: PAST-only persist target is seed"
        )
        let grantsBeforeSeed = pastOnly.debugRewardGrantCount()
        let seededId = pastOnly.addFromDrafts(
            [
                OnboardingPrescriptionDraft(
                    medicine: "FreshMed",
                    dose: "1 tablet",
                    frequency: "1x",
                    duration: "5 days",
                    timesPerDay: "1",
                    doseTimes: ["09:00"]
                )
            ],
            ownerId: owner,
            profileId: profile,
            maximumActiveMedicines: SuperLimits.superPrescriptions
        )
        expect(seededId != nil && seededId != expiredOnly.treatmentId, "D: PAST-only add seeds a NEW treatment")
        expect(pastOnly.debugTreatmentStatus(expiredOnly.treatmentId) == "active", "D: expired treatment unchanged")
        expect(pastOnly.debugRewardGrantCount() == grantsBeforeSeed, "D: seed does not grant completion XP")
        expect(pastOnly.debugTreatmentCompleteGrantCount() == 0, "D: no treatmentComplete grant")

        let completeStore = CheckMedStore(isolatedInMemoryForContracts: true)
        completeStore.debugContractBind(ownerId: owner, profileId: profile)
        let toComplete = completeStore.debugInsertPlan(
            title: "Finish me",
            status: "active",
            startDate: lastWeek,
            endDate: nextMonth,
            medicineName: "FinishMed",
            ownerId: owner,
            profileId: profile
        )
        completeStore.completeTreatment(id: toComplete.treatmentId)
        expect(completeStore.debugTreatmentStatus(toComplete.treatmentId) == "completed", "I: explicit complete writes status")
        expect(completeStore.debugTreatmentCompleteGrantCount() == 1, "I: explicit complete still grants XP")
        expect(completeStore.debugLifecycleKind(treatmentId: toComplete.treatmentId) == .past, "I: completed classifies PAST")

        let futureOnly = CheckMedStore(isolatedInMemoryForContracts: true)
        futureOnly.debugContractBind(ownerId: owner, profileId: profile)
        let futurePlan = futureOnly.debugInsertPlan(
            title: "Starts later",
            status: "active",
            startDate: tomorrow,
            endDate: nextMonth,
            medicineName: "LaterMed",
            ownerId: owner,
            profileId: profile
        )
        expect(
            LaterAddPersist.target(intent: .addToCurrent, hasCurrentTreatment: futureOnly.hasCurrentTreatment) == .seed,
            "C: FUTURE-only is not generic add-to-current"
        )
        let futureSeed = futureOnly.addFromDrafts(
            [
                OnboardingPrescriptionDraft(
                    medicine: "AlongsideFuture",
                    dose: "1 tablet",
                    frequency: "1x",
                    duration: "5 days",
                    timesPerDay: "1",
                    doseTimes: ["09:00"]
                )
            ],
            ownerId: owner,
            profileId: profile,
            maximumActiveMedicines: SuperLimits.superPrescriptions
        )
        expect(futureSeed != nil && futureSeed != futurePlan.treatmentId, "C: FUTURE-only add seeds a new treatment")
        expect(futureOnly.debugTreatmentStatus(futurePlan.treatmentId) == "active", "C: FUTURE treatment unchanged")

        let reminderCurrent = CheckMedStore(isolatedInMemoryForContracts: true)
        reminderCurrent.debugContractBind(ownerId: owner, profileId: profile)
        _ = reminderCurrent.debugInsertPlan(
            title: "Remind",
            status: "active",
            startDate: lastWeek,
            endDate: nextMonth,
            medicineName: "RemindMed",
            ownerId: owner,
            profileId: profile,
            logStatus: DoseLogStatus.pending.rawValue,
            logScheduledAt: tomorrowNoon
        )
        expect(
            reminderCurrent.reminderDrafts(now: now).contains(where: { $0.medicine == "RemindMed" && $0.kind == .dose }),
            "K: CURRENT pending log still produces reminder drafts"
        )

        failures.append(contentsOf: TreatmentPreservationContractChecks.failures())
        return failures
    }
}

enum MedicationCapacitySafetyContractChecks {
    @MainActor
    static func failures() -> [String] {
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
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let now = Date()
        let start = calendar.date(byAdding: .day, value: -1, to: now)!
        let end = calendar.date(byAdding: .day, value: 30, to: now)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        let free = CheckMedStore(isolatedInMemoryForContracts: true)
        free.debugContractBind(ownerId: owner, profileId: profile)

        let firstThree = free.addFromDrafts(
            [draft("Free One"), draft("Free Two"), draft("Free Three")],
            ownerId: owner,
            profileId: profile,
            maximumActiveMedicines: SuperLimits.freePrescriptions
        )
        expect(firstThree != nil, "capacity: Free persists medicines 1-3")
        expect(free.storedMedicineCount == 3, "capacity: Free stores exactly three active medicines")

        let beforeFourth = free.debugLiveRecordCounts()
        let fourth = free.addFromDrafts(
            [draft("Free Four")],
            ownerId: owner,
            profileId: profile,
            maximumActiveMedicines: SuperLimits.freePrescriptions
        )
        let afterFourth = free.debugLiveRecordCounts()
        expect(fourth == nil, "capacity: Free fourth medicine is rejected at persistence boundary")
        expect(afterFourth.medicines == beforeFourth.medicines, "capacity: rejected fourth inserts no medicine")
        expect(afterFourth.schedules == beforeFourth.schedules, "capacity: rejected fourth inserts no schedule")
        expect(afterFourth.logs == beforeFourth.logs, "capacity: rejected fourth inserts no DoseLog")

        expect(
            MedicineCapacityDecision.resolve(isSuper: false, existingCount: 2, maximumActiveMedicines: SuperLimits.freePrescriptions) == .allowed,
            "capacity: Free with 2 live medicines is allowed"
        )
        expect(
            MedicineCapacityDecision.resolve(isSuper: false, existingCount: 3, maximumActiveMedicines: SuperLimits.freePrescriptions) == .freePaywall,
            "capacity: Free at 3 is paywall, not Super ceiling"
        )
        expect(
            MedicineCapacityDecision.resolve(isSuper: true, existingCount: 11, maximumActiveMedicines: SuperLimits.superPrescriptions) == .allowed,
            "capacity: Super with 11 live medicines is allowed"
        )
        expect(
            MedicineCapacityDecision.resolve(isSuper: true, existingCount: 12, maximumActiveMedicines: SuperLimits.superPrescriptions) == .superCeiling,
            "capacity: Super at 12 is ceiling, not paywall"
        )

        let split = CheckMedStore(isolatedInMemoryForContracts: true)
        split.debugContractBind(ownerId: owner, profileId: profile)
        let currentA = split.debugInsertPlan(
            title: "Current A",
            status: "active",
            startDate: start,
            endDate: end,
            medicineName: "SplitMedA1",
            ownerId: owner,
            profileId: profile
        )
        _ = split.debugInsertMedicine(
            treatmentId: currentA.treatmentId,
            name: "SplitMedA2",
            ownerId: owner,
            profileId: profile
        )
        _ = split.debugInsertPlan(
            title: "Current B",
            status: "active",
            startDate: start,
            endDate: end,
            medicineName: "SplitMedB",
            ownerId: owner,
            profileId: profile
        )
        expect(split.storedMedicineCount == 3, "capacity: 2+1 medicines across two current treatments occupy Free cap")
        let splitFourth = split.addFromDrafts(
            [draft("Split Four")],
            ownerId: owner,
            profileId: profile,
            maximumActiveMedicines: SuperLimits.freePrescriptions
        )
        expect(splitFourth == nil, "capacity: fourth Free medicine refused across two treatments")
        expect(split.storedMedicineCount == 3, "capacity: refused split add does not increase occupancy")

        let mixed = CheckMedStore(isolatedInMemoryForContracts: true)
        mixed.debugContractBind(ownerId: owner, profileId: profile)
        let liveNow = mixed.debugInsertPlan(
            title: "Live now",
            status: "active",
            startDate: start,
            endDate: end,
            medicineName: "NowMed1",
            ownerId: owner,
            profileId: profile
        )
        _ = mixed.debugInsertMedicine(
            treatmentId: liveNow.treatmentId,
            name: "NowMed2",
            ownerId: owner,
            profileId: profile
        )
        _ = mixed.debugInsertPlan(
            title: "Upcoming winter",
            status: "active",
            startDate: tomorrow,
            endDate: end,
            medicineName: "FutureMed",
            ownerId: owner,
            profileId: profile
        )
        expect(mixed.debugLifecycleKind(treatmentId: liveNow.treatmentId) == .current, "capacity: live now is current")
        expect(
            mixed.storedMedicineCount == 3,
            "capacity: current + upcoming medicines share Free occupancy"
        )
        let mixedFourth = mixed.addFromDrafts(
            [draft("Mixed Four")],
            ownerId: owner,
            profileId: profile,
            maximumActiveMedicines: SuperLimits.freePrescriptions
        )
        expect(mixedFourth == nil, "capacity: fourth medicine refused when upcoming occupies a slot")

        let finishSlots = CheckMedStore(isolatedInMemoryForContracts: true)
        finishSlots.debugContractBind(ownerId: owner, profileId: profile)
        let finishPlan = finishSlots.debugInsertPlan(
            title: "Finish for slots",
            status: "active",
            startDate: start,
            endDate: end,
            medicineName: "FinishMed",
            ownerId: owner,
            profileId: profile,
            scheduleTime: "08:00",
            logStatus: DoseLogStatus.pending.rawValue,
            logScheduledAt: tomorrow
        )
        _ = finishSlots.debugInsertMedicine(
            treatmentId: finishPlan.treatmentId,
            name: "FinishMed2",
            ownerId: owner,
            profileId: profile
        )
        _ = finishSlots.debugInsertPlan(
            title: "Stay current",
            status: "active",
            startDate: start,
            endDate: end,
            medicineName: "StayMed",
            ownerId: owner,
            profileId: profile,
            scheduleTime: "20:00",
            logStatus: DoseLogStatus.pending.rawValue,
            logScheduledAt: tomorrow
        )
        expect(finishSlots.storedMedicineCount == 3, "capacity: finish fixture occupies three live slots")
        let pendingStay = finishPlan.logId
        _ = finishSlots.completeTreatment(id: finishPlan.treatmentId)
        expect(finishSlots.debugTreatmentStatus(finishPlan.treatmentId) == "completed", "capacity: completed treatment stays in history")
        expect(finishSlots.storedMedicineCount == 1, "capacity: completing a treatment frees its medicine slots")
        expect(
            finishSlots.reportMedicineSummaries().contains(where: { $0.name == "FinishMed" }),
            "capacity: completed treatment medicines remain in history"
        )
        expect(
            pendingStay.flatMap { finishSlots.debugDoseStatus($0) } == DoseLogStatus.pending.rawValue,
            "capacity: completing a treatment does not delete DoseLogs"
        )
        let afterFinishAdd = finishSlots.addFromDrafts(
            [draft("PostFinish")],
            ownerId: owner,
            profileId: profile,
            maximumActiveMedicines: SuperLimits.freePrescriptions
        )
        expect(afterFinishAdd != nil, "capacity: freed slot accepts a new medicine")
        expect(finishSlots.storedMedicineCount == 2, "capacity: new medicine occupies one freed slot")
        let stayPendingId = finishSlots.debugInsertPlan(
            title: "Dose confirm holder",
            status: "active",
            startDate: start,
            endDate: end,
            medicineName: "ConfirmStay",
            ownerId: owner,
            profileId: profile,
            scheduleTime: "09:00",
            logStatus: DoseLogStatus.pending.rawValue,
            logScheduledAt: now.addingTimeInterval(-60)
        ).logId
        if let stayPendingId {
            finishSlots.applyDoseAction(id: stayPendingId, action: .confirmTaken, now: now)
            expect(
                finishSlots.debugDoseStatus(stayPendingId) == DoseLogStatus.taken.rawValue
                    || finishSlots.debugDoseStatus(stayPendingId) == DoseLogStatus.takenLate.rawValue,
                "capacity: existing dose confirmation remains available at cap"
            )
        } else {
            failures.append("capacity: missing pending log for dose confirmation")
        }

        let superStore = CheckMedStore(isolatedInMemoryForContracts: true)
        superStore.debugContractBind(ownerId: owner, profileId: profile)
        let superThree = superStore.addFromDrafts(
            [draft("Super One"), draft("Super Two"), draft("Super Three")],
            ownerId: owner,
            profileId: profile,
            maximumActiveMedicines: SuperLimits.superPrescriptions
        )
        expect(superThree != nil, "capacity: Super persists the first three medicines")
        let superFourth = superStore.addFromDrafts(
            [draft("Super Four")],
            ownerId: owner,
            profileId: profile,
            maximumActiveMedicines: SuperLimits.superPrescriptions
        )
        expect(superFourth != nil, "capacity: Super allows a fourth medicine")
        expect(superStore.storedMedicineCount == 4, "capacity: Super occupancy is 4 after the extra add")
        for index in 5...SuperLimits.superPrescriptions {
            _ = superStore.addFromDrafts(
                [draft("Super \(index)")],
                ownerId: owner,
                profileId: profile,
                maximumActiveMedicines: SuperLimits.superPrescriptions
            )
        }
        expect(superStore.storedMedicineCount == SuperLimits.superPrescriptions, "capacity: Super fills to 12")
        let superThirteenth = superStore.addFromDrafts(
            [draft("Super Thirteen")],
            ownerId: owner,
            profileId: profile,
            maximumActiveMedicines: SuperLimits.superPrescriptions
        )
        expect(superThirteenth == nil, "capacity: Super 13th medicine is refused")
        expect(superStore.storedMedicineCount == SuperLimits.superPrescriptions, "capacity: refused 13th does not increase occupancy")

        let startNewCap = CheckMedStore(isolatedInMemoryForContracts: true)
        startNewCap.debugContractBind(ownerId: owner, profileId: profile)
        _ = startNewCap.debugInsertPlan(
            title: "Live now",
            status: "active",
            startDate: start,
            endDate: end,
            medicineName: "LiveNow",
            ownerId: owner,
            profileId: profile
        )
        _ = startNewCap.debugInsertPlan(
            title: "Soon A",
            status: "active",
            startDate: tomorrow,
            endDate: end,
            medicineName: "SoonA",
            ownerId: owner,
            profileId: profile
        )
        _ = startNewCap.debugInsertPlan(
            title: "Soon B",
            status: "active",
            startDate: tomorrow,
            endDate: end,
            medicineName: "SoonB",
            ownerId: owner,
            profileId: profile
        )
        expect(startNewCap.storedMedicineCount == 3, "capacity: Start New fixture is at Free cap")
        expect(startNewCap.intakeOpeningMedicineCount == 2, "capacity: opening intake uses FUTURE occupancy when CURRENT exists")
        expect(
            MedicineCapacityDecision.resolve(
                isSuper: false,
                existingCount: startNewCap.intakeOpeningMedicineCount,
                maximumActiveMedicines: SuperLimits.freePrescriptions
            ) == .allowed,
            "capacity: Start New can open at cap because CURRENT slots will free"
        )
        let startNewIds = startNewCap.startNewTreatmentFromDrafts(
            [draft("NewOne"), draft("NewTwo")],
            ownerId: owner,
            profileId: profile,
            maximumActiveMedicines: SuperLimits.freePrescriptions
        )
        expect(startNewIds != nil, "capacity: Start New persists one replacement when one slot remains")
        expect(startNewCap.storedMedicineCount == 3, "capacity: Start New plus preserved FUTURE stays at Free 3")

        if let first = free.medicineSummaries().first {
            free.updateMedicineDetails(id: first.id, name: "Free One Edited")
            expect(free.storedMedicineCount == 3, "capacity: editing does not consume a slot")
            expect(free.debugMedicineName(first.id) == "Free One Edited", "capacity: existing medicine edit persists")
            free.deleteMedicine(id: first.id)
            expect(free.storedMedicineCount == 2, "capacity: explicit deletion releases one slot")
        } else {
            failures.append("capacity: missing fixture medicine for edit/delete")
        }

        let replacement = free.addFromDrafts(
            [draft("Free Replacement")],
            ownerId: owner,
            profileId: profile,
            maximumActiveMedicines: SuperLimits.freePrescriptions
        )
        expect(replacement != nil, "capacity: deletion makes a new slot available")
        expect(free.storedMedicineCount == 3, "capacity: replacement returns Free to three")
        expect(
            free.debugLiveMedicationRowsMatch(ownerId: owner, profileId: profile),
            "capacity: Free enforcement preserves owner/profile boundaries"
        )

        let retained = CheckMedStore(isolatedInMemoryForContracts: true)
        retained.debugContractBind(ownerId: owner, profileId: profile)
        for index in 1...SuperLimits.superPrescriptions {
            _ = retained.debugInsertPlan(
                title: "Super \(index)",
                status: "active",
                startDate: start,
                endDate: end,
                medicineName: "Super Medicine \(index)",
                ownerId: owner,
                profileId: profile,
                scheduleTime: String(format: "%02d:00", (index % 12) + 8),
                logStatus: DoseLogStatus.pending.rawValue,
                logScheduledAt: tomorrow
            )
        }
        let retainedBefore = retained.debugLiveRecordCounts()
        let remindersBefore = retained.reminderDrafts(now: now).count
        retained.removeDuplicateMedicinesIfNeeded()
        let retainedAfter = retained.debugLiveRecordCounts()
        expect(retained.storedMedicineCount == SuperLimits.superPrescriptions, "capacity: twelve valid medicines survive cleanup")
        expect(retainedAfter.treatments == retainedBefore.treatments, "capacity: downgrade-safe cleanup keeps treatments")
        expect(retainedAfter.medicines == retainedBefore.medicines, "capacity: downgrade-safe cleanup keeps medicines")
        expect(retainedAfter.schedules == retainedBefore.schedules, "capacity: downgrade-safe cleanup keeps schedules")
        expect(retainedAfter.logs == retainedBefore.logs, "capacity: downgrade-safe cleanup keeps DoseLogs")
        expect(retained.reminderDrafts(now: now).count == remindersBefore, "capacity: retained schedules keep reminder drafts")

        let overFreeAttempt = retained.addFromDrafts(
            [draft("Blocked While Free")],
            ownerId: owner,
            profileId: profile,
            maximumActiveMedicines: SuperLimits.freePrescriptions
        )
        expect(overFreeAttempt == nil, "capacity: downgraded over-limit user cannot add another medicine")
        expect(retained.storedMedicineCount == SuperLimits.superPrescriptions, "capacity: rejected add does not prune retained medicines")
        expect(
            retained.debugLiveMedicationRowsMatch(ownerId: owner, profileId: profile),
            "capacity: retention preserves owner/profile boundaries"
        )

        let duplicates = CheckMedStore(isolatedInMemoryForContracts: true)
        duplicates.debugContractBind(ownerId: owner, profileId: profile)
        _ = duplicates.debugInsertPlan(
            title: "Duplicate A",
            status: "active",
            startDate: start,
            endDate: end,
            medicineName: "DuplicateMed",
            ownerId: owner,
            profileId: profile
        )
        _ = duplicates.debugInsertPlan(
            title: "Duplicate B",
            status: "active",
            startDate: start,
            endDate: end,
            medicineName: "DuplicateMed",
            ownerId: owner,
            profileId: profile
        )
        duplicates.removeDuplicateMedicinesIfNeeded()
        expect(duplicates.storedMedicineCount == 1, "capacity: legitimate duplicate cleanup remains active")

        return failures
    }
}

enum TreatmentTitleContractChecks {
    @MainActor
    static func failures() -> [String] {
        var failures: [String] = []
        func expect(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let now = Date()
        let start = calendar.date(byAdding: .day, value: -3, to: now)!
        let end = calendar.date(byAdding: .day, value: 20, to: now)
        let owner = UUID()
        let profile = UUID()
        let store = CheckMedStore(isolatedInMemoryForContracts: true)
        store.debugContractBind(ownerId: owner, profileId: profile)

        let plan = store.debugInsertPlan(
            title: "Amoxicilina 500mg",
            status: "active",
            startDate: start,
            endDate: end,
            medicineName: "Amoxicilina 500mg",
            ownerId: owner,
            profileId: profile
        )
        expect(store.debugTreatmentTitle(plan.treatmentId) == "Amoxicilina 500mg", "title: insert keeps seed title")
        expect(store.setTreatmentTitle(id: plan.treatmentId, title: "   ") == false, "title: empty rename rejected")
        expect(store.debugTreatmentTitle(plan.treatmentId) == "Amoxicilina 500mg", "title: empty rename does not write")
        expect(store.setTreatmentTitle(id: plan.treatmentId, title: "  Curso inverno  "), "title: trimmed rename succeeds")
        expect(store.debugTreatmentTitle(plan.treatmentId) == "Curso inverno", "title: canonical value trimmed")

        _ = store.addFromDrafts(
            [
                OnboardingPrescriptionDraft(
                    medicine: "Paracetamol 1000mg",
                    dose: "1 tablet",
                    frequency: "1x",
                    duration: "5 days",
                    timesPerDay: "1",
                    doseTimes: ["09:00"]
                )
            ],
            ownerId: owner,
            profileId: profile,
            maximumActiveMedicines: SuperLimits.superPrescriptions
        )
        expect(store.debugTreatmentTitle(plan.treatmentId) == "Curso inverno", "title: later add does not overwrite")
        expect(
            store.journeyTreeSnapshot(now: now).current.contains(where: { $0.id == plan.treatmentId && $0.title == "Curso inverno" }),
            "title: current tree uses canonical name"
        )

        _ = store.seedFromDrafts(
            [
                OnboardingPrescriptionDraft(
                    medicine: "Ibuprofeno",
                    dose: "1 tablet",
                    frequency: "1x",
                    duration: "5 days",
                    timesPerDay: "1",
                    doseTimes: ["09:00"]
                )
            ],
            ownerId: owner,
            profileId: profile,
            maximumActiveMedicines: SuperLimits.superPrescriptions
        )
        expect(store.debugTreatmentTitle(plan.treatmentId) == "Curso inverno", "title: replace-plan seed does not overwrite user title")
        expect(
            store.journeyReport(treatmentId: plan.treatmentId)?.title == "Curso inverno",
            "title: report uses canonical name"
        )

        let history = CheckMedStore(isolatedInMemoryForContracts: true)
        history.debugContractBind(ownerId: owner, profileId: profile)
        let past = history.debugInsertPlan(
            title: "Old course",
            status: "completed",
            startDate: calendar.date(byAdding: .day, value: -20, to: now)!,
            endDate: calendar.date(byAdding: .day, value: -5, to: now),
            medicineName: "OldMed",
            ownerId: owner,
            profileId: profile
        )
        expect(history.setTreatmentTitle(id: past.treatmentId, title: "Arquivo 2025"), "title: historical rename succeeds")
        expect(
            history.journeyTreeSnapshot(now: now).past.contains(where: { $0.id == past.treatmentId && $0.title == "Arquivo 2025" }),
            "title: history tree uses renamed title"
        )

        // MARK: Detail Finish scoped completion (TreatmentDetailFinishCommand)
        let finishOwner = UUID()
        let finishProfile = UUID()
        let finishNow = Date()
        let finishStart = calendar.date(byAdding: .day, value: -10, to: calendar.startOfDay(for: finishNow))!
        let finishEnd = calendar.date(byAdding: .day, value: 30, to: calendar.startOfDay(for: finishNow))!
        let dueSoon = finishNow.addingTimeInterval(3600)

        let scoped = CheckMedStore(isolatedInMemoryForContracts: true)
        scoped.debugContractBind(ownerId: finishOwner, profileId: finishProfile)
        let treatmentA = scoped.debugInsertPlan(
            title: "Finish A",
            status: "active",
            startDate: finishStart,
            endDate: finishEnd,
            medicineName: "FinishMedA",
            ownerId: finishOwner,
            profileId: finishProfile,
            scheduleTime: "08:00",
            logStatus: DoseLogStatus.pending.rawValue,
            logScheduledAt: dueSoon
        )
        let treatmentB = scoped.debugInsertPlan(
            title: "Finish B",
            status: "active",
            startDate: finishStart,
            endDate: finishEnd,
            medicineName: "FinishMedB",
            ownerId: finishOwner,
            profileId: finishProfile,
            scheduleTime: "20:00",
            logStatus: DoseLogStatus.pending.rawValue,
            logScheduledAt: dueSoon
        )
        expect(scoped.debugLifecycleKind(treatmentId: treatmentA.treatmentId) == .current, "finish A: A is current")
        expect(scoped.debugLifecycleKind(treatmentId: treatmentB.treatmentId) == .current, "finish A: B is current")
        expect(
            scoped.incompleteMedicineNames(forTreatmentId: treatmentA.treatmentId).contains("FinishMedA"),
            "finish B: selected incomplete names include A"
        )
        expect(
            !scoped.incompleteMedicineNames(forTreatmentId: treatmentA.treatmentId).contains("FinishMedB"),
            "finish B: selected incomplete names exclude sibling B"
        )
        expect(
            scoped.incompleteMedicineNamesForActivePlan().contains("FinishMedA")
                && scoped.incompleteMedicineNamesForActivePlan().contains("FinishMedB"),
            "finish B: global helper still lists both active-plan medicines"
        )
        let statusALog = treatmentA.logId.flatMap { scoped.debugDoseStatus($0) }
        let capturedId = treatmentA.treatmentId
        let confirmed = TreatmentDetailFinishCommand.apply(
            .confirm,
            store: scoped,
            treatmentId: capturedId
        )
        expect(confirmed == .completed, "finish A: confirm completes displayed UUID")
        let successFollow = TreatmentDetailFinishCommand.followUp(for: confirmed, successRoute: .journeyReport)
        expect(successFollow.rescheduleReminders, "finish cmd: success schedules reminder rebuild")
        expect(successFollow.navigate == .journeyReport, "finish cmd: success navigates")
        expect(!successFollow.showRefusalAlert, "finish cmd: success does not show refusal")
        expect(capturedId == treatmentA.treatmentId, "finish cmd: captured UUID remains stable")
        expect(scoped.debugTreatmentStatus(treatmentA.treatmentId) == "completed", "finish A: A completed")
        expect(scoped.debugTreatmentStatus(treatmentB.treatmentId) == "active", "finish A: B remains active")
        expect(scoped.debugLifecycleKind(treatmentId: treatmentB.treatmentId) == .current, "finish A: B stays current")
        expect(scoped.debugLifecycleKind(treatmentId: treatmentA.treatmentId) == .past, "finish A: A is past")
        expect(statusALog == DoseLogStatus.pending.rawValue, "finish A: DoseLogs not rewritten")
        expect(
            treatmentA.logId.flatMap { scoped.debugDoseStatus($0) } == DoseLogStatus.pending.rawValue,
            "finish A: A log still pending"
        )
        expect(scoped.debugTreatmentCompleteGrantCount() == 1, "finish C: first complete grants once")

        let updatedAtAfterFirst = scoped.debugTreatmentUpdatedAt(treatmentA.treatmentId)
        let grantsAfterFirst = scoped.debugTreatmentCompleteGrantCount()
        let repeatResult = TreatmentDetailFinishCommand.apply(
            .confirm,
            store: scoped,
            treatmentId: treatmentA.treatmentId
        )
        expect(repeatResult == .refused, "finish C: repeat confirm is no-op")
        let repeatFollow = TreatmentDetailFinishCommand.followUp(for: repeatResult, successRoute: .addPrescription)
        expect(!repeatFollow.rescheduleReminders, "finish cmd: refused does not reschedule")
        expect(repeatFollow.navigate == nil, "finish cmd: refused does not navigate")
        expect(repeatFollow.showRefusalAlert, "finish cmd: refused shows alert")
        expect(scoped.debugTreatmentUpdatedAt(treatmentA.treatmentId) == updatedAtAfterFirst, "finish C: updatedAt unchanged")
        expect(scoped.debugTreatmentCompleteGrantCount() == grantsAfterFirst, "finish C: no duplicate XP")

        let drafts = scoped.reminderDrafts(now: finishNow)
        expect(
            drafts.contains(where: { $0.medicine == "FinishMedB" }),
            "finish F: remaining current treatment keeps reminder drafts"
        )
        expect(
            !drafts.contains(where: { $0.medicine == "FinishMedA" }),
            "finish F: completed A excluded from reminder drafts"
        )

        let cancelled = CheckMedStore(isolatedInMemoryForContracts: true)
        cancelled.debugContractBind(ownerId: finishOwner, profileId: finishProfile)
        let cancelPlan = cancelled.debugInsertPlan(
            title: "Cancel me",
            status: "active",
            startDate: finishStart,
            endDate: finishEnd,
            medicineName: "CancelMed",
            ownerId: finishOwner,
            profileId: finishProfile
        )
        let cancelUpdated = cancelled.debugTreatmentUpdatedAt(cancelPlan.treatmentId)
        let cancelApplied = TreatmentDetailFinishCommand.apply(
            .cancel,
            store: cancelled,
            treatmentId: cancelPlan.treatmentId
        )
        expect(cancelApplied == .cancelled, "finish I: cancel returns cancelled")
        let cancelFollow = TreatmentDetailFinishCommand.followUp(for: cancelApplied, successRoute: .journeyReport)
        expect(!cancelFollow.rescheduleReminders && cancelFollow.navigate == nil, "finish cmd: cancel has no effects")
        expect(cancelled.debugTreatmentStatus(cancelPlan.treatmentId) == "active", "finish I: cancel does not complete")
        expect(cancelled.debugTreatmentUpdatedAt(cancelPlan.treatmentId) == cancelUpdated, "finish I: cancel does not write")
        expect(cancelled.debugTreatmentCompleteGrantCount() == 0, "finish I: cancel grants no XP")

        let nilCapture = CheckMedStore(isolatedInMemoryForContracts: true)
        nilCapture.debugContractBind(ownerId: finishOwner, profileId: finishProfile)
        let nilPlan = nilCapture.debugInsertPlan(
            title: "Nil capture",
            status: "active",
            startDate: finishStart,
            endDate: finishEnd,
            medicineName: "NilCaptureMed",
            ownerId: finishOwner,
            profileId: finishProfile
        )
        let nilStatus = nilCapture.debugTreatmentStatus(nilPlan.treatmentId)
        let nilUpdated = nilCapture.debugTreatmentUpdatedAt(nilPlan.treatmentId)
        let nilGrants = nilCapture.debugTreatmentCompleteGrantCount()
        let nilConfirm = TreatmentDetailFinishCommand.apply(
            .confirm,
            store: nilCapture,
            treatmentId: nil
        )
        expect(nilConfirm == .refused, "finish nil: confirm without captured UUID is refused")
        let nilConfirmFollow = TreatmentDetailFinishCommand.followUp(
            for: nilConfirm,
            successRoute: .addPrescription
        )
        expect(!nilConfirmFollow.rescheduleReminders, "finish nil: confirm does not reschedule")
        expect(nilConfirmFollow.navigate == nil, "finish nil: confirm does not navigate")
        expect(nilConfirmFollow.showRefusalAlert, "finish nil: confirm shows refusal")
        expect(nilCapture.debugTreatmentStatus(nilPlan.treatmentId) == nilStatus, "finish nil: confirm does not change status")
        expect(nilCapture.debugTreatmentUpdatedAt(nilPlan.treatmentId) == nilUpdated, "finish nil: confirm does not change updatedAt")
        expect(nilCapture.debugTreatmentCompleteGrantCount() == nilGrants, "finish nil: confirm grants no XP")

        let nilCancel = TreatmentDetailFinishCommand.apply(
            .cancel,
            store: nilCapture,
            treatmentId: nil
        )
        expect(nilCancel == .cancelled, "finish nil: cancel without captured UUID is cancelled")
        let nilCancelFollow = TreatmentDetailFinishCommand.followUp(
            for: nilCancel,
            successRoute: .journeyReport
        )
        expect(!nilCancelFollow.rescheduleReminders && nilCancelFollow.navigate == nil, "finish nil: cancel has no effects")
        expect(!nilCancelFollow.showRefusalAlert, "finish nil: cancel does not refuse")
        expect(nilCapture.debugTreatmentStatus(nilPlan.treatmentId) == "active", "finish nil: cancel does not change status")
        expect(nilCapture.debugTreatmentUpdatedAt(nilPlan.treatmentId) == nilUpdated, "finish nil: cancel does not change updatedAt")
        expect(nilCapture.debugTreatmentCompleteGrantCount() == nilGrants, "finish nil: cancel grants no XP")

        let futureStore = CheckMedStore(isolatedInMemoryForContracts: true)
        futureStore.debugContractBind(ownerId: finishOwner, profileId: finishProfile)
        let currentSibling = futureStore.debugInsertPlan(
            title: "Current sibling",
            status: "active",
            startDate: finishStart,
            endDate: finishEnd,
            medicineName: "CurrentSibling",
            ownerId: finishOwner,
            profileId: finishProfile
        )
        let futureSibling = futureStore.debugInsertPlan(
            title: "Future sibling",
            status: "active",
            startDate: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: finishNow))!,
            endDate: finishEnd,
            medicineName: "FutureSibling",
            ownerId: finishOwner,
            profileId: finishProfile
        )
        _ = TreatmentDetailFinishCommand.apply(
            .confirm,
            store: futureStore,
            treatmentId: currentSibling.treatmentId
        )
        expect(futureStore.debugTreatmentStatus(futureSibling.treatmentId) == "active", "finish D: future stays active")
        expect(futureStore.debugLifecycleKind(treatmentId: futureSibling.treatmentId) == .future, "finish D: future stays future")

        let isolation = CheckMedStore(isolatedInMemoryForContracts: true)
        let otherOwner = UUID()
        let otherProfile = UUID()
        isolation.debugContractBind(ownerId: otherOwner, profileId: otherProfile)
        let foreign = isolation.debugInsertPlan(
            title: "Foreign",
            status: "active",
            startDate: finishStart,
            endDate: finishEnd,
            medicineName: "ForeignMed",
            ownerId: otherOwner,
            profileId: otherProfile
        )
        isolation.debugContractBind(ownerId: finishOwner, profileId: finishProfile)
        let local = isolation.debugInsertPlan(
            title: "Local",
            status: "active",
            startDate: finishStart,
            endDate: finishEnd,
            medicineName: "LocalMed",
            ownerId: finishOwner,
            profileId: finishProfile
        )
        let foreignConfirm = TreatmentDetailFinishCommand.apply(
            .confirm,
            store: isolation,
            treatmentId: foreign.treatmentId
        )
        expect(foreignConfirm == .refused, "finish E: wrong-owner UUID refused")
        let foreignFollow = TreatmentDetailFinishCommand.followUp(for: foreignConfirm, successRoute: .addPrescription)
        expect(!foreignFollow.rescheduleReminders && foreignFollow.navigate == nil, "finish cmd: wrong-owner has no success effects")
        expect(isolation.debugStoredTreatmentStatus(foreign.treatmentId) == "active", "finish E: foreign row stays active")
        expect(isolation.debugTreatmentStatus(local.treatmentId) == "active", "finish E: local row untouched")

        isolation.debugContractBind(ownerId: finishOwner, profileId: otherProfile)
        let otherProfilePlan = isolation.debugInsertPlan(
            title: "Other profile",
            status: "active",
            startDate: finishStart,
            endDate: finishEnd,
            medicineName: "OtherProfileMed",
            ownerId: finishOwner,
            profileId: otherProfile
        )
        isolation.debugContractBind(ownerId: finishOwner, profileId: finishProfile)
        let wrongProfileConfirm = TreatmentDetailFinishCommand.apply(
            .confirm,
            store: isolation,
            treatmentId: otherProfilePlan.treatmentId
        )
        expect(wrongProfileConfirm == .refused, "finish E: wrong-profile UUID refused")
        expect(
            isolation.debugStoredTreatmentStatus(otherProfilePlan.treatmentId) == "active",
            "finish E: other-profile row stays active"
        )

        let bulk = CheckMedStore(isolatedInMemoryForContracts: true)
        bulk.debugContractBind(ownerId: finishOwner, profileId: finishProfile)
        let bulkA = bulk.debugInsertPlan(
            title: "Bulk A",
            status: "active",
            startDate: finishStart,
            endDate: finishEnd,
            medicineName: "BulkMedA",
            ownerId: finishOwner,
            profileId: finishProfile
        )
        let bulkB = bulk.debugInsertPlan(
            title: "Bulk B",
            status: "active",
            startDate: finishStart,
            endDate: finishEnd,
            medicineName: "BulkMedB",
            ownerId: finishOwner,
            profileId: finishProfile
        )
        bulk.completeAllActiveTreatments()
        expect(bulk.debugTreatmentStatus(bulkA.treatmentId) == "completed", "finish G: bulk still completes A")
        expect(bulk.debugTreatmentStatus(bulkB.treatmentId) == "completed", "finish G: bulk still completes B")

        // MARK: TH-2 scoped read-only dose events
        let doseOwner = UUID()
        let doseProfile = UUID()
        let doseStore = CheckMedStore(isolatedInMemoryForContracts: true)
        doseStore.debugContractBind(ownerId: doseOwner, profileId: doseProfile)
        let doseA = doseStore.debugInsertPlan(
            title: "Dose A",
            status: "active",
            startDate: finishStart,
            endDate: finishEnd,
            medicineName: "DoseMedA",
            ownerId: doseOwner,
            profileId: doseProfile,
            scheduleTime: "08:00",
            logStatus: DoseLogStatus.taken.rawValue,
            logScheduledAt: finishNow.addingTimeInterval(-3600)
        )
        let doseB = doseStore.debugInsertPlan(
            title: "Dose B",
            status: "active",
            startDate: finishStart,
            endDate: finishEnd,
            medicineName: "DoseMedB",
            ownerId: doseOwner,
            profileId: doseProfile,
            scheduleTime: "20:00",
            logStatus: DoseLogStatus.pending.rawValue,
            logScheduledAt: finishNow.addingTimeInterval(7200)
        )
        let eventsA = doseStore.doseEvents(forTreatmentId: doseA.treatmentId)
        expect(eventsA.count == 1, "dose A: only A's log")
        expect(eventsA.allSatisfy { $0.treatmentId == doseA.treatmentId }, "dose A: UUID scope")
        expect(eventsA.allSatisfy { $0.medicineName == "DoseMedA" }, "dose A: excludes sibling medicine")
        expect(eventsA.first?.status == .taken, "dose A: preserves taken")
        expect(
            doseStore.doseEvents(forTreatmentId: doseB.treatmentId).allSatisfy { $0.medicineName == "DoseMedB" },
            "dose B: B events stay on B"
        )
        expect(
            doseStore.doseEvents(forTreatmentId: UUID()).isEmpty,
            "dose missing: unknown UUID returns []"
        )
        let beforeStatus = eventsA.first?.statusRaw
        _ = doseStore.treatmentDetailSnapshot(id: doseA.treatmentId)
        expect(
            doseStore.doseEvents(forTreatmentId: doseA.treatmentId).first?.statusRaw == beforeStatus,
            "dose query: snapshot does not mutate logs"
        )
        doseStore.debugContractBind(ownerId: UUID(), profileId: UUID())
        expect(
            doseStore.doseEvents(forTreatmentId: doseA.treatmentId).isEmpty,
            "dose E: wrong-owner/profile sees no events"
        )

        doseStore.debugContractBind(ownerId: doseOwner, profileId: doseProfile)
        let mixed = CheckMedStore(isolatedInMemoryForContracts: true)
        mixed.debugContractBind(ownerId: doseOwner, profileId: doseProfile)
        let mixedPlan = mixed.debugInsertPlan(
            title: "Mixed",
            status: "active",
            startDate: finishStart,
            endDate: finishEnd,
            medicineName: "MixedMed",
            ownerId: doseOwner,
            profileId: doseProfile
        )
        _ = mixed.debugInsertDoseLog(
            treatmentId: mixedPlan.treatmentId,
            medicineName: "MixedMed",
            scheduledAt: finishNow.addingTimeInterval(-7200),
            status: DoseLogStatus.takenLate.rawValue,
            loggedAt: finishNow.addingTimeInterval(-3600),
            ownerId: doseOwner,
            profileId: doseProfile
        )
        _ = mixed.debugInsertDoseLog(
            treatmentId: mixedPlan.treatmentId,
            medicineName: "MixedMed",
            scheduledAt: finishNow.addingTimeInterval(-86400),
            status: DoseLogStatus.missed.rawValue,
            ownerId: doseOwner,
            profileId: doseProfile
        )
        _ = mixed.debugInsertDoseLog(
            treatmentId: mixedPlan.treatmentId,
            medicineName: "MixedMed",
            scheduledAt: finishNow.addingTimeInterval(-172800),
            status: DoseLogStatus.skipped.rawValue,
            ownerId: doseOwner,
            profileId: doseProfile
        )
        let deletedId = mixed.debugInsertDoseLog(
            treatmentId: mixedPlan.treatmentId,
            medicineName: "MixedMed",
            scheduledAt: finishNow.addingTimeInterval(-4000),
            status: DoseLogStatus.taken.rawValue,
            loggedAt: finishNow.addingTimeInterval(-3900),
            deletedAt: finishNow,
            ownerId: doseOwner,
            profileId: doseProfile
        )
        _ = mixed.debugInsertDoseLog(
            treatmentId: mixedPlan.treatmentId,
            medicineName: "MixedMed",
            scheduledAt: finishNow.addingTimeInterval(-3000),
            status: DoseLogStatus.taken.rawValue,
            loggedAt: finishNow.addingTimeInterval(-2900),
            ownerId: UUID(),
            profileId: UUID()
        )
        let mixedEvents = mixed.doseEvents(forTreatmentId: mixedPlan.treatmentId)
        expect(
            mixedEvents.contains { $0.status == .takenLate }
                && mixedEvents.contains { $0.status == .missed }
                && mixedEvents.contains { $0.status == .skipped },
            "dose mix: takenLate/missed/skipped preserved"
        )
        expect(mixedEvents.allSatisfy { $0.id != deletedId }, "dose mix: deleted log excluded")
        expect(
            !mixedEvents.contains(where: { $0.status == .taken && $0.scheduledAt == finishNow.addingTimeInterval(-3000) }),
            "dose mix: wrong-owner log excluded"
        )

        return failures
    }

    /// Isolated DEBUG report. Does not touch live stores, reminders, or the network.
    @MainActor
    static func runtimeEvidence() -> String {
        let failures = failures()
        func status(_ tag: String) -> String {
            failures.contains { $0.contains(tag) } ? "FAIL" : "PASS"
        }
        let finishRows = [
            "A \(status("finish A:")) two current treatments, complete selected UUID only",
            "B \(status("finish B:")) incomplete warning excludes sibling medicines",
            "C \(status("finish C:")) repeat complete is no-op, no duplicate XP",
            "D \(status("finish D:")) future sibling stays future and active",
            "E \(status("finish E:")) wrong-owner/wrong-profile refused",
            "F \(status("finish F:")) reminder drafts keep remaining current treatment",
            "G \(status("finish G:")) bulk completeAll still completes all active",
            "H \(failures.filter { !$0.contains("finish ") && !$0.contains("dose ") }.isEmpty ? "PASS" : "FAIL") existing lifecycle contracts",
            "I \(status("finish I:")) cancel is mutation-free",
            "cmd \(status("finish cmd:")) success/failure follow-up (no false navigate/reschedule)",
            "dose \(status("dose A:")) scoped DoseLog query excludes sibling treatment",
            "dose \(status("dose mix:")) statuses preserved; deleted and foreign excluded",
        ]
        let header = failures.isEmpty
            ? "TreatmentLifecycle allEmpty=true"
            : "TreatmentLifecycle allEmpty=false count=\(failures.count)"
        return ([header] + finishRows + failures.map { "FAIL \($0)" }).joined(separator: "\n")
    }
}

enum MissedDosePresentationContractChecks {
    @MainActor
    static func failures() -> [String] {
        var failures: [String] = []
        func expect(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }

        let owner = UUID()
        let profile = UUID()
        let missedA = UUID()
        let missedB = UUID()
        let now = Date()
        let twoHoursAgo = now.addingTimeInterval(-2 * 3600)
        let start = now.addingTimeInterval(-7 * 24 * 3600)
        let end = now.addingTimeInterval(14 * 24 * 3600)

        let store = CheckMedStore(isolatedInMemoryForContracts: true)
        store.debugContractBind(ownerId: owner, profileId: profile)
        _ = store.debugInsertPlan(
            title: "Missed A",
            status: "active",
            startDate: start,
            endDate: end,
            medicineName: "DoseA",
            ownerId: owner,
            profileId: profile,
            logStatus: DoseLogStatus.missed.rawValue,
            logScheduledAt: twoHoursAgo,
            logId: missedA
        )
        _ = store.debugInsertPlan(
            title: "Missed B",
            status: "active",
            startDate: start,
            endDate: end,
            medicineName: "DoseB",
            ownerId: owner,
            profileId: profile,
            logStatus: DoseLogStatus.missed.rawValue,
            logScheduledAt: twoHoursAgo.addingTimeInterval(-600),
            logId: missedB
        )

        let before = store.adherence()
        let listed = store.unresolvedDosesForSummary(now: now).map(\.id)
        expect(listed.contains(missedA), "missed: fixture A listed")
        expect(listed.contains(missedB), "missed: fixture B listed")

        store.applyDoseAction(id: missedA, action: .didNotTake, now: now)
        MissedDoseAcknowledgement.acknowledge(missedA)
        let afterTap = store.unresolvedDosesForSummary(now: now).map(\.id)
        expect(!afterTap.contains(missedA), "missed: A hidden immediately after Não tomei path")
        expect(afterTap.contains(missedB), "missed: B still listed")
        expect(store.debugDoseStatus(missedA) == DoseLogStatus.missed.rawValue, "missed: A stays canonical missed")
        let after = store.adherence()
        expect(before.percent == after.percent, "missed: adherence percent unchanged")
        expect(before.streakDays == after.streakDays, "missed: streak unchanged")
        expect(before.missedCount == after.missedCount, "missed: missed count unchanged")

        let reopened = store.unresolvedDosesForSummary(now: now).map(\.id)
        expect(!reopened.contains(missedA) && reopened.contains(missedB), "missed: reopen still hides only A")

        let relaunched = CheckMedStore(isolatedInMemoryForContracts: true)
        relaunched.debugContractBind(ownerId: owner, profileId: profile)
        _ = relaunched.debugInsertPlan(
            title: "Missed A",
            status: "active",
            startDate: start,
            endDate: end,
            medicineName: "DoseA",
            ownerId: owner,
            profileId: profile,
            logStatus: DoseLogStatus.missed.rawValue,
            logScheduledAt: twoHoursAgo,
            logId: missedA
        )
        expect(MissedDoseAcknowledgement.contains(missedA), "missed: acknowledgement persists after new isolated store")
        expect(
            !relaunched.unresolvedDosesForSummary(now: now).map(\.id).contains(missedA),
            "missed: relaunched context still hides acknowledged A"
        )
        expect(relaunched.debugDoseStatus(missedA) == DoseLogStatus.missed.rawValue, "missed: relaunched log remains missed")
        return failures
    }
}

enum CompletedSkippedLabelContractChecks {
    static func failures() -> [String] {
        var failures: [String] = []
        func expect(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }
        func formatted(count: Int, locale: AppLocale) -> String {
            count == 1
                ? L10n.string(.journeySkippedOne, locale: locale)
                : L10n.string(.journeySkipped, locale: locale, args: [count])
        }
        for locale in AppLocale.allCases {
            for count in [0, 1, 9] {
                let text = formatted(count: count, locale: locale)
                expect(!text.contains("%"), "skipped \(locale.rawValue) count=\(count) leaked placeholder: \(text)")
                expect(text.contains("\(count)"), "skipped \(locale.rawValue) count=\(count) missing digit: \(text)")
            }
        }
        expect(formatted(count: 0, locale: .english) == "0 skipped", "en zero")
        expect(formatted(count: 1, locale: .english) == "1 skipped", "en singular")
        expect(formatted(count: 9, locale: .english) == "9 skipped", "en plural")
        expect(formatted(count: 0, locale: .portuguese) == "0 puladas", "pt zero")
        expect(formatted(count: 1, locale: .portuguese) == "1 pulada", "pt singular")
        expect(formatted(count: 9, locale: .portuguese) == "9 puladas", "pt plural")
        expect(formatted(count: 1, locale: .spanish) == "1 omitida", "es singular")
        expect(formatted(count: 9, locale: .spanish) == "9 omitidas", "es plural")
        expect(formatted(count: 1, locale: .french) == "1 passée", "fr singular")
        expect(formatted(count: 9, locale: .french) == "9 passées", "fr plural")
        return failures
    }
}

enum TreatmentPreservationContractChecks {
    @MainActor
    static func failures() -> [String] {
        var failures: [String] = []
        func expect(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }
        func draft(_ name: String) -> OnboardingPrescriptionDraft {
            OnboardingPrescriptionDraft(
                medicine: name,
                dose: "1 tablet",
                frequency: "1x",
                duration: "5 days",
                timesPerDay: "1",
                doseTimes: ["09:00"]
            )
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let lastWeek = calendar.date(byAdding: .day, value: -10, to: today)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let nextMonth = calendar.date(byAdding: .day, value: 30, to: today)!
        let tomorrowNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: tomorrow) ?? tomorrow

        let owner = UUID()
        let profile = UUID()
        let extraProfile = UUID()

        let futureOnly = CheckMedStore(isolatedInMemoryForContracts: true)
        futureOnly.debugContractBind(ownerId: owner, profileId: profile)
        let futurePlan = futureOnly.debugInsertPlan(
            title: "Starts later",
            status: "active",
            startDate: tomorrow,
            endDate: nextMonth,
            medicineName: "LaterMed",
            ownerId: owner,
            profileId: profile,
            logStatus: DoseLogStatus.pending.rawValue,
            logScheduledAt: tomorrowNoon
        )
        let futureStart = futureOnly.debugTreatmentStartDate(futurePlan.treatmentId)
        let futureEnd = futureOnly.debugTreatmentEndDate(futurePlan.treatmentId)
        let seeded = futureOnly.seedFromDrafts(
            [draft("AlongsideFuture")],
            ownerId: owner,
            profileId: profile,
            maximumActiveMedicines: SuperLimits.superPrescriptions
        )
        expect(seeded != nil && seeded != futurePlan.treatmentId, "TS-1: FUTURE-only seed inserts a new treatment")
        expect(futureOnly.debugTreatmentStatus(futurePlan.treatmentId) == "active", "TS-1: FUTURE status unchanged by seed")
        expect(futureOnly.debugTreatmentStartDate(futurePlan.treatmentId) == futureStart, "TS-1: FUTURE start unchanged")
        expect(futureOnly.debugTreatmentEndDate(futurePlan.treatmentId) == futureEnd, "TS-1: FUTURE end unchanged")
        expect(futureOnly.debugMedicineName(futurePlan.medicineId) == "LaterMed", "TS-1: FUTURE medicine identity preserved")
        expect(
            futureOnly.debugDoseStatus(futurePlan.logId ?? UUID()) == DoseLogStatus.pending.rawValue,
            "TS-1: FUTURE DoseLog preserved"
        )
        if let logId = futurePlan.logId {
            futureOnly.applyDoseAction(id: logId, action: .confirmTaken, now: tomorrowNoon)
            expect(
                futureOnly.debugDoseStatus(logId) == DoseLogStatus.taken.rawValue,
                "TS-1: Taken still applies on preserved FUTURE log"
            )
        }

        let currentOnly = CheckMedStore(isolatedInMemoryForContracts: true)
        currentOnly.debugContractBind(ownerId: owner, profileId: profile)
        let currentPlan = currentOnly.debugInsertPlan(
            title: "Current only",
            status: "active",
            startDate: lastWeek,
            endDate: nextMonth,
            medicineName: "CurrentMed",
            ownerId: owner,
            profileId: profile,
            logStatus: DoseLogStatus.pending.rawValue,
            logScheduledAt: now
        )
        let replacement = currentOnly.startNewTreatmentFromDrafts(
            [draft("ReplacementMed")],
            ownerId: owner,
            profileId: profile,
            maximumActiveMedicines: SuperLimits.superPrescriptions
        )
        expect(replacement != nil && replacement != currentPlan.treatmentId, "TS-1: CURRENT-only Start New seeds a new id")
        expect(currentOnly.debugTreatmentStatus(currentPlan.treatmentId) == "completed", "TS-1: CURRENT-only Start New completes CURRENT")
        expect(currentOnly.debugMedicineName(currentPlan.medicineId) == "CurrentMed", "TS-1: completed CURRENT medicine UUID kept")
        expect(
            currentOnly.debugDoseStatus(currentPlan.logId ?? UUID()) == DoseLogStatus.pending.rawValue,
            "TS-1: completed CURRENT DoseLog kept"
        )
        expect(currentOnly.debugTreatmentCompleteGrantCount() == 1, "TS-1: Start New still grants completion XP after persist")

        let mixed = CheckMedStore(isolatedInMemoryForContracts: true)
        mixed.debugContractBind(ownerId: owner, profileId: profile)
        let mixedCurrent = mixed.debugInsertPlan(
            title: "Mixed current",
            status: "active",
            startDate: lastWeek,
            endDate: nextMonth,
            medicineName: "NowMed",
            ownerId: owner,
            profileId: profile
        )
        let mixedFuture = mixed.debugInsertPlan(
            title: "Mixed future",
            status: "active",
            startDate: tomorrow,
            endDate: nextMonth,
            medicineName: "SoonMed",
            ownerId: owner,
            profileId: profile
        )
        let mixedStart = mixed.debugTreatmentStartDate(mixedFuture.treatmentId)
        let mixedNew = mixed.startNewTreatmentFromDrafts(
            [draft("BrandNew")],
            ownerId: owner,
            profileId: profile,
            maximumActiveMedicines: SuperLimits.superPrescriptions
        )
        expect(mixedNew != nil && mixedNew != mixedCurrent.treatmentId && mixedNew != mixedFuture.treatmentId, "TS-1: mixed Start New is a third treatment")
        expect(mixed.debugTreatmentStatus(mixedCurrent.treatmentId) == "completed", "TS-1: mixed Start New completes CURRENT")
        expect(mixed.debugTreatmentStatus(mixedFuture.treatmentId) == "active", "TS-1: mixed Start New leaves FUTURE active")
        expect(mixed.debugTreatmentStartDate(mixedFuture.treatmentId) == mixedStart, "TS-1: mixed FUTURE dates unchanged")
        expect(mixed.debugMedicineName(mixedFuture.medicineId) == "SoonMed", "TS-1: mixed FUTURE medicine kept")
        expect(mixed.storedMedicineCount == 2, "TS-1: mixed occupancy is new CURRENT + FUTURE")
        expect(
            !mixed.reminderDrafts(now: now).contains(where: { $0.medicine == "NowMed" }),
            "TS-1: completed CURRENT no longer produces reminder drafts"
        )

        let multiCurrent = CheckMedStore(isolatedInMemoryForContracts: true)
        multiCurrent.debugContractBind(ownerId: owner, profileId: profile)
        let currentA = multiCurrent.debugInsertPlan(
            title: "Current A",
            status: "active",
            startDate: lastWeek,
            endDate: nextMonth,
            medicineName: "MedA",
            ownerId: owner,
            profileId: profile
        )
        let currentB = multiCurrent.debugInsertPlan(
            title: "Current B",
            status: "active",
            startDate: lastWeek,
            endDate: nextMonth,
            medicineName: "MedB",
            ownerId: owner,
            profileId: profile
        )
        let futureKeep = multiCurrent.debugInsertPlan(
            title: "Keep future",
            status: "active",
            startDate: tomorrow,
            endDate: nextMonth,
            medicineName: "MedF",
            ownerId: owner,
            profileId: profile
        )
        _ = multiCurrent.startNewTreatmentFromDrafts(
            [draft("AfterBoth")],
            ownerId: owner,
            profileId: profile,
            maximumActiveMedicines: SuperLimits.superPrescriptions
        )
        expect(multiCurrent.debugTreatmentStatus(currentA.treatmentId) == "completed", "TS-1: all CURRENT A completed")
        expect(multiCurrent.debugTreatmentStatus(currentB.treatmentId) == "completed", "TS-1: all CURRENT B completed")
        expect(multiCurrent.debugTreatmentStatus(futureKeep.treatmentId) == "active", "TS-1: FUTURE survives multiple CURRENT complete")

        let family = CheckMedStore(isolatedInMemoryForContracts: true)
        family.debugContractBind(ownerId: owner, profileId: profile)
        let primaryCurrent = family.debugInsertPlan(
            title: "Primary current",
            status: "active",
            startDate: lastWeek,
            endDate: nextMonth,
            medicineName: "PrimaryMed",
            ownerId: owner,
            profileId: profile
        )
        family.setActiveScope(profileId: extraProfile, includeUnscoped: false)
        let extraFuture = family.debugInsertPlan(
            title: "Extra future",
            status: "active",
            startDate: tomorrow,
            endDate: nextMonth,
            medicineName: "ExtraMed",
            ownerId: owner,
            profileId: extraProfile
        )
        expect(family.hasLivePlanInSelectedProfile, "TS-1: extra profile Plan Resume sees its own FUTURE")
        family.setActiveScope(profileId: profile, includeUnscoped: true)
        expect(family.hasLivePlanInSelectedProfile, "TS-1: primary still has a live plan")
        let emptyExtra = CheckMedStore(isolatedInMemoryForContracts: true)
        emptyExtra.debugContractBind(ownerId: owner, profileId: profile)
        _ = emptyExtra.debugInsertPlan(
            title: "Only primary",
            status: "active",
            startDate: lastWeek,
            endDate: nextMonth,
            medicineName: "OnlyPrimary",
            ownerId: owner,
            profileId: profile
        )
        emptyExtra.setActiveScope(profileId: extraProfile, includeUnscoped: false)
        expect(emptyExtra.hasActivePlan, "TS-1: owner-wide hasActivePlan still sees the other profile")
        expect(!emptyExtra.hasLivePlanInSelectedProfile, "TS-1: extra Plan Resume is not skipped by another profile")
        emptyExtra.setActiveScope(profileId: profile, includeUnscoped: true)
        let familyNew = family.startNewTreatmentFromDrafts(
            [draft("PrimaryReplacement")],
            ownerId: owner,
            profileId: profile,
            maximumActiveMedicines: SuperLimits.superPrescriptions
        )
        expect(familyNew != nil, "TS-1: two-profile Start New persists on the selected profile")
        expect(family.debugTreatmentStatus(primaryCurrent.treatmentId) == "completed", "TS-1: selected profile CURRENT completed")
        expect(
            family.debugStoredTreatmentStatus(extraFuture.treatmentId) == "active",
            "TS-1: other profile FUTURE not mutated"
        )

        let blocked = CheckMedStore(isolatedInMemoryForContracts: true)
        blocked.debugContractBind(ownerId: owner, profileId: profile)
        let blockedCurrent = blocked.debugInsertPlan(
            title: "Cap current",
            status: "active",
            startDate: lastWeek,
            endDate: nextMonth,
            medicineName: "CapNow",
            ownerId: owner,
            profileId: profile
        )
        _ = blocked.debugInsertPlan(
            title: "Cap future A",
            status: "active",
            startDate: tomorrow,
            endDate: nextMonth,
            medicineName: "CapSoonA",
            ownerId: owner,
            profileId: profile
        )
        _ = blocked.debugInsertPlan(
            title: "Cap future B",
            status: "active",
            startDate: tomorrow,
            endDate: nextMonth,
            medicineName: "CapSoonB",
            ownerId: owner,
            profileId: profile
        )
        _ = blocked.debugInsertPlan(
            title: "Cap future C",
            status: "active",
            startDate: tomorrow,
            endDate: nextMonth,
            medicineName: "CapSoonC",
            ownerId: owner,
            profileId: profile
        )
        expect(blocked.storedMedicineCount == 4, "TS-1: retained over-cap fixture is four live medicines")
        expect(blocked.medicineCountIfCurrentTreatmentsCompleted == 3, "TS-1: completing CURRENT still leaves Free at cap")
        expect(
            LaterAddPersist.draftOccupancyBase(
                target: .completeThenSeed,
                liveCount: blocked.storedMedicineCount,
                capturedLiveCount: blocked.storedMedicineCount,
                occupancyIfCurrentCompleted: blocked.medicineCountIfCurrentTreatmentsCompleted
            ) == 3,
            "TS-1: Start New capBase is FUTURE occupancy, not 0"
        )
        let refused = blocked.startNewTreatmentFromDrafts(
            [draft("WouldOverflow")],
            ownerId: owner,
            profileId: profile,
            maximumActiveMedicines: SuperLimits.freePrescriptions
        )
        expect(refused == nil, "TS-1: Start New refuses when FUTURE already fills Free 3")
        expect(blocked.debugTreatmentStatus(blockedCurrent.treatmentId) == "active", "TS-1: refused Start New does not complete CURRENT")

        let onboard = CheckMedStore(isolatedInMemoryForContracts: true)
        onboard.debugContractBind(ownerId: owner, profileId: profile)
        let onboardCurrent = onboard.debugInsertPlan(
            title: "Onboard current",
            status: "active",
            startDate: lastWeek,
            endDate: nextMonth,
            medicineName: "OnboardMed",
            ownerId: owner,
            profileId: profile
        )
        let replaced = onboard.seedFromDrafts(
            [draft("ReplacedOnboard")],
            ownerId: owner,
            profileId: profile,
            maximumActiveMedicines: SuperLimits.superPrescriptions
        )
        expect(replaced == onboardCurrent.treatmentId, "TS-1: onboarding seed still replaces CURRENT in place")
        expect(onboard.debugMedicineName(onboardCurrent.medicineId) == "ReplacedOnboard", "TS-1: CURRENT replacement overwrites first medicine")

        failures.append(contentsOf: TreatmentStartNewAtomicityContractChecks.failures())
        failures.append(contentsOf: UnfinishedPlanSafetyContractChecks.failures())
        return failures
    }
}

enum TreatmentStartNewAtomicityContractChecks {
    @MainActor
    static func failures() -> [String] {
        var failures: [String] = []
        func expect(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }
        func draft(_ name: String) -> OnboardingPrescriptionDraft {
            OnboardingPrescriptionDraft(
                medicine: name,
                dose: "1 tablet",
                frequency: "1x",
                duration: "5 days",
                timesPerDay: "1",
                doseTimes: ["09:00"]
            )
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let lastWeek = calendar.date(byAdding: .day, value: -10, to: today)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let nextMonth = calendar.date(byAdding: .day, value: 30, to: today)!
        let owner = UUID()
        let profile = UUID()
        let extraProfile = UUID()

        let missingOwner = CheckMedStore(isolatedInMemoryForContracts: true)
        missingOwner.debugContractBind(ownerId: owner, profileId: profile)
        let missingCurrent = missingOwner.debugInsertPlan(
            title: "Need owner",
            status: "active",
            startDate: lastWeek,
            endDate: nextMonth,
            medicineName: "NeedOwnerMed",
            ownerId: owner,
            profileId: profile
        )
        let missingXP = missingOwner.debugTreatmentCompleteGrantCount()
        let missingMutations = missingOwner.pendingSyncMutationCount(ownerId: owner)
        let missingResult = missingOwner.startNewTreatmentFromDrafts(
            [draft("NoOwner")],
            ownerId: nil,
            profileId: profile,
            maximumActiveMedicines: SuperLimits.superPrescriptions
        )
        expect(missingResult == nil, "atomic A: missing owner refuses")
        expect(missingOwner.debugTreatmentStatus(missingCurrent.treatmentId) == "active", "atomic A: CURRENT stays active")
        expect(missingOwner.debugTreatmentCompleteGrantCount() == missingXP, "atomic A: no completion XP")
        expect(missingOwner.pendingSyncMutationCount(ownerId: owner) == missingMutations, "atomic A: no extra sync mutation")

        let cap = CheckMedStore(isolatedInMemoryForContracts: true)
        cap.debugContractBind(ownerId: owner, profileId: profile)
        let capCurrent = cap.debugInsertPlan(
            title: "Cap now",
            status: "active",
            startDate: lastWeek,
            endDate: nextMonth,
            medicineName: "CapNow",
            ownerId: owner,
            profileId: profile
        )
        _ = cap.debugInsertPlan(
            title: "Cap future A",
            status: "active",
            startDate: tomorrow,
            endDate: nextMonth,
            medicineName: "CapSoonA",
            ownerId: owner,
            profileId: profile
        )
        _ = cap.debugInsertPlan(
            title: "Cap future B",
            status: "active",
            startDate: tomorrow,
            endDate: nextMonth,
            medicineName: "CapSoonB",
            ownerId: owner,
            profileId: profile
        )
        _ = cap.debugInsertPlan(
            title: "Cap future C",
            status: "active",
            startDate: tomorrow,
            endDate: nextMonth,
            medicineName: "CapSoonC",
            ownerId: owner,
            profileId: profile
        )
        let capXP = cap.debugTreatmentCompleteGrantCount()
        let capMutations = cap.pendingSyncMutationCount(ownerId: owner)
        let capResult = cap.startNewTreatmentFromDrafts(
            [draft("Overflow")],
            ownerId: owner,
            profileId: profile,
            maximumActiveMedicines: SuperLimits.freePrescriptions
        )
        expect(capResult == nil, "atomic B: FUTURE at cap refuses")
        expect(cap.debugTreatmentStatus(capCurrent.treatmentId) == "active", "atomic B: CURRENT not completed before persist")
        expect(cap.debugTreatmentCompleteGrantCount() == capXP, "atomic B: no completion XP")
        expect(cap.pendingSyncMutationCount(ownerId: owner) == capMutations, "atomic B: no extra sync mutation")

        let failSave = CheckMedStore(isolatedInMemoryForContracts: true)
        failSave.debugContractBind(ownerId: owner, profileId: profile)
        let failCurrent = failSave.debugInsertPlan(
            title: "Fail current",
            status: "active",
            startDate: lastWeek,
            endDate: nextMonth,
            medicineName: "FailNow",
            ownerId: owner,
            profileId: profile
        )
        let failFuture = failSave.debugInsertPlan(
            title: "Fail future",
            status: "active",
            startDate: tomorrow,
            endDate: nextMonth,
            medicineName: "FailSoon",
            ownerId: owner,
            profileId: profile
        )
        let failStart = failSave.debugTreatmentStartDate(failFuture.treatmentId)
        let failXP = failSave.debugTreatmentCompleteGrantCount()
        let failMutations = failSave.pendingSyncMutationCount(ownerId: owner)
        failSave.debugFailNextCanonicalSave = true
        let failResult = failSave.startNewTreatmentFromDrafts(
            [draft("ShouldRollBack")],
            ownerId: owner,
            profileId: profile,
            maximumActiveMedicines: SuperLimits.superPrescriptions
        )
        expect(failResult == nil, "atomic C: forced save failure refuses")
        expect(failSave.debugTreatmentStatus(failCurrent.treatmentId) == "active", "atomic C: CURRENT rolled back")
        expect(failSave.debugTreatmentStatus(failFuture.treatmentId) == "active", "atomic C: FUTURE unchanged")
        expect(failSave.debugTreatmentStartDate(failFuture.treatmentId) == failStart, "atomic C: FUTURE dates unchanged")
        expect(failSave.debugMedicineName(failCurrent.medicineId) == "FailNow", "atomic C: no replacement medicine kept")
        expect(failSave.debugTreatmentCompleteGrantCount() == failXP, "atomic D: failed save grants no XP")
        expect(failSave.pendingSyncMutationCount(ownerId: owner) == failMutations, "atomic D: failed save stages no sync mutation")
        expect(failSave.storedMedicineCount == 2, "atomic C: occupancy unchanged after rollback")

        let failMulti = CheckMedStore(isolatedInMemoryForContracts: true)
        failMulti.debugContractBind(ownerId: owner, profileId: profile)
        let failMultiCurrent = failMulti.debugInsertPlan(
            title: "Fail multi current",
            status: "active",
            startDate: lastWeek,
            endDate: nextMonth,
            medicineName: "FailMultiNow",
            ownerId: owner,
            profileId: profile
        )
        let failMultiFuture = failMulti.debugInsertPlan(
            title: "Fail multi future",
            status: "active",
            startDate: tomorrow,
            endDate: nextMonth,
            medicineName: "FailMultiSoon",
            ownerId: owner,
            profileId: profile
        )
        let failMultiStart = failMulti.debugTreatmentStartDate(failMultiFuture.treatmentId)
        let failMultiXP = failMulti.debugTreatmentCompleteGrantCount()
        let failMultiMutations = failMulti.pendingSyncMutationCount(ownerId: owner)
        let failMultiCounts = failMulti.debugLiveRecordCounts()
        failMulti.setSurfacesPlan(false)
        failMulti.debugFailNextCanonicalSave = true
        let failMultiResult = failMulti.startNewTreatmentFromDrafts(
            [draft("RollA"), draft("RollB")],
            ownerId: owner,
            profileId: profile,
            maximumActiveMedicines: SuperLimits.superPrescriptions
        )
        let failMultiTree = failMulti.journeyTreeSnapshot(now: now)
        expect(failMultiResult == nil, "atomic I: multi-medicine save failure refuses")
        expect(failMulti.debugTreatmentStatus(failMultiCurrent.treatmentId) == "active", "atomic I: CURRENT rolled back")
        expect(failMulti.debugTreatmentStatus(failMultiFuture.treatmentId) == "active", "atomic I: FUTURE unchanged")
        expect(failMulti.debugTreatmentStartDate(failMultiFuture.treatmentId) == failMultiStart, "atomic I: FUTURE dates unchanged")
        expect(failMulti.debugMedicineName(failMultiCurrent.medicineId) == "FailMultiNow", "atomic I: original CURRENT medicine kept")
        expect(failMulti.debugMedicineName(failMultiFuture.medicineId) == "FailMultiSoon", "atomic I: original FUTURE medicine kept")
        expect(
            !failMultiTree.current.contains(where: {
                $0.medicineNames.contains("RollA") || $0.medicineNames.contains("RollB")
            }),
            "atomic I: no partial new CURRENT medicines"
        )
        expect(failMulti.debugTreatmentCompleteGrantCount() == failMultiXP, "atomic I: failed multi save grants no XP")
        expect(failMulti.pendingSyncMutationCount(ownerId: owner) == failMultiMutations, "atomic I: failed multi save stages no sync mutation")
        expect(failMulti.storedMedicineCount == 2, "atomic I: occupancy unchanged after rollback")
        expect(failMulti.debugLiveRecordCounts() == failMultiCounts, "atomic I: live row counts unchanged")
        expect(!failMulti.surfacesPlan, "atomic I: presentation does not surface a successful plan")

        let success = CheckMedStore(isolatedInMemoryForContracts: true)
        success.debugContractBind(ownerId: owner, profileId: profile)
        let successCurrent = success.debugInsertPlan(
            title: "Success current",
            status: "active",
            startDate: lastWeek,
            endDate: nextMonth,
            medicineName: "SuccessNow",
            ownerId: owner,
            profileId: profile
        )
        let successFuture = success.debugInsertPlan(
            title: "Success future",
            status: "active",
            startDate: tomorrow,
            endDate: nextMonth,
            medicineName: "SuccessSoon",
            ownerId: owner,
            profileId: profile
        )
        success.setActiveScope(profileId: extraProfile, includeUnscoped: false)
        let other = success.debugInsertPlan(
            title: "Other profile",
            status: "active",
            startDate: lastWeek,
            endDate: nextMonth,
            medicineName: "OtherMed",
            ownerId: owner,
            profileId: extraProfile
        )
        success.setActiveScope(profileId: profile, includeUnscoped: true)
        let successId = success.startNewTreatmentFromDrafts(
            [draft("ReplacementA"), draft("ReplacementB")],
            ownerId: owner,
            profileId: profile,
            maximumActiveMedicines: SuperLimits.superPrescriptions
        )
        expect(successId != nil && successId != successCurrent.treatmentId && successId != successFuture.treatmentId, "atomic E: new CURRENT UUID")
        expect(success.debugTreatmentStatus(successCurrent.treatmentId) == "completed", "atomic E: selected CURRENT completed")
        expect(success.debugTreatmentStatus(successFuture.treatmentId) == "active", "atomic F: FUTURE preserved")
        expect(success.debugStoredTreatmentStatus(other.treatmentId) == "active", "atomic F: other profile unchanged")
        let tree = success.journeyTreeSnapshot(now: now)
        expect(
            tree.current.contains(where: {
                $0.medicineNames.contains("ReplacementA") && $0.medicineNames.contains("ReplacementB")
            }),
            "atomic H: both accepted drafts persist on the new CURRENT"
        )
        expect(tree.future.contains(where: { $0.id == successFuture.treatmentId }), "atomic F: FUTURE remains on the tree")
        expect(success.surfacesPlan, "atomic H: successful save may surface the plan")
        expect(
            success.debugLiveRecordCounts().medicines >= 4,
            "atomic H: accepted medicines persist with preserved CURRENT/FUTURE rows"
        )

        let multi = CheckMedStore(isolatedInMemoryForContracts: true)
        multi.debugContractBind(ownerId: owner, profileId: profile)
        let multiA = multi.debugInsertPlan(
            title: "Multi A",
            status: "active",
            startDate: lastWeek,
            endDate: nextMonth,
            medicineName: "MultiA",
            ownerId: owner,
            profileId: profile
        )
        let multiB = multi.debugInsertPlan(
            title: "Multi B",
            status: "active",
            startDate: lastWeek,
            endDate: nextMonth,
            medicineName: "MultiB",
            ownerId: owner,
            profileId: profile
        )
        let multiNew = multi.startNewTreatmentFromDrafts(
            [draft("AfterMulti")],
            ownerId: owner,
            profileId: profile,
            maximumActiveMedicines: SuperLimits.superPrescriptions
        )
        expect(multiNew != nil, "atomic G: multi CURRENT Start New persists")
        expect(multi.debugTreatmentStatus(multiA.treatmentId) == "completed", "atomic G: CURRENT A completed together")
        expect(multi.debugTreatmentStatus(multiB.treatmentId) == "completed", "atomic G: CURRENT B completed together")

        return failures
    }
}

enum UnfinishedPlanSafetyContractChecks {
    @MainActor
    static func failures() -> [String] {
        var failures: [String] = []
        func expect(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }
        func draft(_ name: String) -> OnboardingPrescriptionDraft {
            OnboardingPrescriptionDraft(
                medicine: name,
                dose: "1 tablet",
                frequency: "1x",
                duration: "5 days",
                timesPerDay: "1",
                doseTimes: ["09:00"]
            )
        }
        func copyImpliesDeletion(_ text: String) -> Bool {
            let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            return ["delete", "apagar", "borrar", "supprimer"].contains { folded.contains($0) }
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let lastWeek = calendar.date(byAdding: .day, value: -10, to: today)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let nextMonth = calendar.date(byAdding: .day, value: 30, to: today)!
        let owner = UUID()
        let profile = UUID()
        let extraProfile = UUID()

        let store = CheckMedStore(isolatedInMemoryForContracts: true)
        store.debugContractBind(ownerId: owner, profileId: profile)
        let current = store.debugInsertPlan(
            title: "SAF current",
            status: "active",
            startDate: lastWeek,
            endDate: nextMonth,
            medicineName: "SafNow",
            ownerId: owner,
            profileId: profile,
            logStatus: "pending",
            logScheduledAt: lastWeek
        )
        let future = store.debugInsertPlan(
            title: "SAF future",
            status: "active",
            startDate: tomorrow,
            endDate: nextMonth,
            medicineName: "SafSoon",
            ownerId: owner,
            profileId: profile
        )
        store.setActiveScope(profileId: extraProfile, includeUnscoped: false)
        let other = store.debugInsertPlan(
            title: "SAF other",
            status: "active",
            startDate: lastWeek,
            endDate: nextMonth,
            medicineName: "SafOther",
            ownerId: owner,
            profileId: extraProfile
        )
        store.setActiveScope(profileId: profile, includeUnscoped: true)
        let beforeCounts = store.debugLiveRecordCounts()
        let beforeMutations = store.pendingSyncMutationCount(ownerId: owner)
        let beforeSurfaces = store.surfacesPlan
        let session = SessionStore()
        let confirmedBefore = session.hasConfirmedMedicationPlan
        UnfinishedPlanPromptActions.continueAsNewIntake(session: session, treatments: store)
        expect(store.debugTreatmentStatus(current.treatmentId) == "active", "SAF-1 A: CURRENT stays active")
        expect(store.debugTreatmentStatus(future.treatmentId) == "active", "SAF-1 A: FUTURE stays active")
        expect(store.debugMedicineName(current.medicineId) == "SafNow", "SAF-1 B: CURRENT medicine kept")
        expect(current.logId != nil && store.debugDoseStatus(current.logId!) == "pending", "SAF-1 B: DoseLog kept")
        expect(store.debugLiveRecordCounts() == beforeCounts, "SAF-1 B: live row counts unchanged")
        expect(store.pendingSyncMutationCount(ownerId: owner) == beforeMutations, "SAF-1 C: no delete outbox")
        expect(store.debugStoredTreatmentStatus(other.treatmentId) == "active", "SAF-1 G: other profile unchanged")
        expect(store.surfacesPlan == beforeSurfaces, "SAF-1 H: surfacesPlan unchanged")
        expect(session.hasConfirmedMedicationPlan == confirmedBefore, "SAF-1 H: confirmation flag unchanged")
        session.finishFreshPlan(select: .home)
        expect(store.debugTreatmentStatus(current.treatmentId) == "active", "SAF-1 D: cancel leaves CURRENT")
        expect(store.debugTreatmentStatus(future.treatmentId) == "active", "SAF-1 D: cancel leaves FUTURE")
        expect(!session.startFreshPrescription, "SAF-1 D: cancel clears fresh-intake presentation")

        let resume = CheckMedStore(isolatedInMemoryForContracts: true)
        resume.debugContractBind(ownerId: owner, profileId: profile)
        let resumeCurrent = resume.debugInsertPlan(
            title: "SAF resume",
            status: "active",
            startDate: lastWeek,
            endDate: nextMonth,
            medicineName: "SafResume",
            ownerId: owner,
            profileId: profile
        )
        let resumeCounts = resume.debugLiveRecordCounts()
        let resumeSession = SessionStore()
        resumeSession.beginResumeSetup()
        expect(resume.debugTreatmentStatus(resumeCurrent.treatmentId) == "active", "SAF-1 F: Finish does not complete")
        expect(resume.debugLiveRecordCounts() == resumeCounts, "SAF-1 F: Finish is mutation-free")
        expect(resumeSession.showResumeSetup, "SAF-1 F: Finish opens resume setup")

        let intake = CheckMedStore(isolatedInMemoryForContracts: true)
        intake.debugContractBind(ownerId: owner, profileId: profile)
        let intakeCurrent = intake.debugInsertPlan(
            title: "SAF intake",
            status: "active",
            startDate: lastWeek,
            endDate: nextMonth,
            medicineName: "SafIntake",
            ownerId: owner,
            profileId: profile
        )
        UnfinishedPlanPromptActions.continueAsNewIntake(session: SessionStore(), treatments: intake)
        let replacement = intake.startNewTreatmentFromDrafts(
            [draft("SafReplacement")],
            ownerId: owner,
            profileId: profile,
            maximumActiveMedicines: SuperLimits.superPrescriptions
        )
        expect(replacement != nil && replacement != intakeCurrent.treatmentId, "SAF-1 E: later persist still uses TS-1 Start New")
        expect(intake.debugTreatmentStatus(intakeCurrent.treatmentId) == "completed", "SAF-1 E: TS-1 completes CURRENT")

        for locale in AppLocale.allCases {
            expect(
                !copyImpliesDeletion(L10n.string(.startNewPlan, locale: locale)),
                "SAF-1 I: startNewPlan must not imply deletion (\(locale.rawValue))"
            )
            expect(
                !copyImpliesDeletion(L10n.string(.deletePlanAndStartNew, locale: locale)),
                "SAF-1 I: deletePlanAndStartNew must not imply deletion (\(locale.rawValue))"
            )
        }

        return failures
    }
}
#endif
