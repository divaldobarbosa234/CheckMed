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
            profileId: profile
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
            profileId: profile
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
            profileId: profile
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

        return failures
    }
}
#endif
