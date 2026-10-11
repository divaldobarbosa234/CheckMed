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

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let now = Date()
        let start = calendar.date(byAdding: .day, value: -1, to: now)!
        let end = calendar.date(byAdding: .day, value: 30, to: now)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
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
        return failures
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
#endif
