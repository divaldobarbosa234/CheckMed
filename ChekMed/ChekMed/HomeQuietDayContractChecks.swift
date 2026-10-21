#if DEBUG
import Foundation

/// Quiet-day Home presentation. Does not write DoseLogs or change DoseLoop.
enum HomeQuietDayContractChecks {
    @MainActor
    static func failures() -> [String] {
        var failures: [String] = []
        func expect(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 19, minute: 4))!
        let today = calendar.startOfDay(for: now)
        let tomorrow0800 = calendar.date(byAdding: .hour, value: 32, to: today)!
        let dayAfter0800 = calendar.date(byAdding: .day, value: 2, to: tomorrow0800)!
        let currentId = UUID()
        let futureId = UUID()
        let pastId = UUID()
        let aas = UUID()
        let extra = UUID()
        let futureMed = UUID()
        let pastMed = UUID()

        let currentBranch = CheckMedStore.JourneyTreeBranch(
            id: currentId,
            title: "Current",
            startDate: today,
            endDate: nil,
            medicineNames: ["AAS"]
        )
        let futureBranch = CheckMedStore.JourneyTreeBranch(
            id: futureId,
            title: "Later",
            startDate: calendar.date(byAdding: .day, value: 3, to: today)!,
            endDate: nil,
            medicineNames: ["FutureMed"]
        )
        let pastBranch = CheckMedStore.JourneyTreeBranch(
            id: pastId,
            title: "Done",
            startDate: calendar.date(byAdding: .day, value: -10, to: today)!,
            endDate: calendar.date(byAdding: .day, value: -1, to: today)!,
            medicineNames: ["PastMed"]
        )

        expect(
            HomePlanPresentationMapper.occupancy(
                planReady: true,
                tree: .init(current: [currentBranch], future: [], past: []),
                hasScheduledToday: false
            ) == .activeQuietDay,
            "quiet-day occupancy when CURRENT medicines have no today logs"
        )
        expect(
            HomePlanPresentationMapper.occupancy(
                planReady: true,
                tree: .init(current: [currentBranch], future: [], past: []),
                hasScheduledToday: true
            ) == .activeToday,
            "later-today doses keep activeToday occupancy"
        )
        expect(
            HomePlanPresentationMapper.occupancy(
                planReady: true,
                tree: .init(current: [], future: [futureBranch], past: []),
                hasScheduledToday: false
            ) == .futureOnly,
            "futureOnly occupancy unchanged when no CURRENT treatments"
        )
        expect(
            HomePlanPresentationMapper.occupancy(
                planReady: true,
                tree: .init(current: [], future: [], past: []),
                hasScheduledToday: false
            ) == .noTreatment,
            "empty tree is no medicines, not quiet day"
        )

        let noDoses = L10n.string(.challengeNoDosesToday, locale: .english)
        let noMedicines = L10n.string(.noTreatmentInProgressHeadline, locale: .english)
        let quietBody = L10n.string(.homeActiveNoDosesToday, locale: .english)
        expect(!noDoses.isEmpty && noDoses != noMedicines, "quiet-day title is not the empty-plan headline")
        expect(quietBody.localizedCaseInsensitiveContains("today"), "quiet-day body names today")
        expect(
            !quietBody.localizedCaseInsensitiveContains("no medicines"),
            "quiet-day body does not claim there are no medicines"
        )

        let mapped = HomeQuietDayPresentationMapper.rows(
            currentTreatmentIds: [currentId],
            medicines: [
                .init(id: aas, treatmentId: currentId, name: "AAS", detail: "1 tablet"),
                .init(id: aas, treatmentId: currentId, name: "AAS", detail: "1 tablet"),
                .init(id: extra, treatmentId: currentId, name: "Beta", detail: "1 tablet"),
                .init(id: futureMed, treatmentId: futureId, name: "FutureMed", detail: "1 tablet"),
                .init(id: pastMed, treatmentId: pastId, name: "PastMed", detail: "1 tablet"),
            ],
            logs: [
                .init(medicineId: aas, scheduledAt: dayAfter0800, isEligibleNextDose: true),
                .init(medicineId: aas, scheduledAt: tomorrow0800, isEligibleNextDose: true),
                .init(medicineId: extra, scheduledAt: tomorrow0800, isEligibleNextDose: false),
                .init(medicineId: futureMed, scheduledAt: tomorrow0800, isEligibleNextDose: true),
                .init(medicineId: pastMed, scheduledAt: tomorrow0800, isEligibleNextDose: true),
            ],
            now: now
        )
        expect(mapped.map(\.id) == [aas, extra], "CURRENT medicines only, no duplicates")
        expect(mapped.first?.nextScheduledAt == tomorrow0800, "next dose is earliest eligible future log")
        expect(mapped.last?.nextScheduledAt == nil, "taken/closed logs do not invent a next dose")
        expect(
            HomeQuietDayPresentationMapper.showsUpcomingChip(nextScheduledAt: mapped.first?.nextScheduledAt),
            "eligible next dose shows Upcoming"
        )
        expect(
            !HomeQuietDayPresentationMapper.showsUpcomingChip(nextScheduledAt: mapped.last?.nextScheduledAt),
            "no eligible next dose hides Upcoming"
        )

        expect(HomeQuietDayPresentationMapper.isEligibleNextDose(.pending), "future pending is eligible")
        expect(HomeQuietDayPresentationMapper.isEligibleNextDose(.snoozed), "future snoozed is eligible")
        expect(
            !HomeQuietDayPresentationMapper.isEligibleNextDose(.pendingConfirmation),
            "pendingConfirmation is not a quiet-day next dose"
        )
        expect(!HomeQuietDayPresentationMapper.isEligibleNextDose(.taken), "taken is not eligible")
        expect(!HomeQuietDayPresentationMapper.isEligibleNextDose(.missed), "missed is not eligible")
        expect(DoseLogStatus.pendingConfirmation.isOpen, "canonical isOpen still includes pendingConfirmation")

        let confirmOnly = UUID()
        let snoozedMed = UUID()
        let mixedMed = UUID()
        let eligibilityRows = HomeQuietDayPresentationMapper.rows(
            currentTreatmentIds: [currentId],
            medicines: [
                .init(id: confirmOnly, treatmentId: currentId, name: "Confirm", detail: "1 tablet"),
                .init(id: snoozedMed, treatmentId: currentId, name: "Snooze", detail: "1 tablet"),
                .init(id: mixedMed, treatmentId: currentId, name: "Mixed", detail: "1 tablet"),
            ],
            logs: [
                .init(
                    medicineId: confirmOnly,
                    scheduledAt: tomorrow0800,
                    isEligibleNextDose: HomeQuietDayPresentationMapper.isEligibleNextDose(.pendingConfirmation)
                ),
                .init(
                    medicineId: snoozedMed,
                    scheduledAt: tomorrow0800,
                    isEligibleNextDose: HomeQuietDayPresentationMapper.isEligibleNextDose(.snoozed)
                ),
                .init(
                    medicineId: mixedMed,
                    scheduledAt: tomorrow0800,
                    isEligibleNextDose: HomeQuietDayPresentationMapper.isEligibleNextDose(.pendingConfirmation)
                ),
                .init(
                    medicineId: mixedMed,
                    scheduledAt: dayAfter0800,
                    isEligibleNextDose: HomeQuietDayPresentationMapper.isEligibleNextDose(.pending)
                ),
            ],
            now: now
        )
        expect(
            eligibilityRows.first(where: { $0.id == confirmOnly })?.nextScheduledAt == nil,
            "future pendingConfirmation only has no Next dose"
        )
        expect(
            eligibilityRows.first(where: { $0.id == snoozedMed })?.nextScheduledAt == tomorrow0800,
            "future snoozed uses the existing timestamp"
        )
        expect(
            eligibilityRows.first(where: { $0.id == mixedMed })?.nextScheduledAt == dayAfter0800,
            "mixed logs pick the earliest eligible future log"
        )

        let formatted = HomeQuietDayPresentationMapper.formatNextScheduledAt(
            tomorrow0800,
            calendar: calendar,
            locale: Locale(identifier: "en_GB")
        )
        expect(formatted.contains("21"), "next-dose caption includes the local date")
        expect(
            formatted.contains("8"),
            "next-dose caption includes the local time"
        )

        let liveNow = Date()
        let liveCalendar = Calendar.current
        let liveToday = liveCalendar.startOfDay(for: liveNow)
        let liveTomorrow0800 = liveCalendar.date(
            bySettingHour: 8,
            minute: 0,
            second: 0,
            of: liveCalendar.date(byAdding: .day, value: 1, to: liveToday)!
        )!
        let owner = UUID()
        let profile = UUID()
        let otherOwner = UUID()
        let store = CheckMedStore(isolatedInMemoryForContracts: true)
        store.debugContractBind(ownerId: owner, profileId: profile)
        let current = store.debugInsertPlan(
            title: "Current AAS",
            status: "active",
            startDate: liveToday,
            endDate: liveCalendar.date(byAdding: .day, value: 6, to: liveToday),
            medicineName: "AAS",
            ownerId: owner,
            profileId: profile,
            scheduleTime: "08:00",
            logStatus: DoseLogStatus.pending.rawValue,
            logScheduledAt: liveTomorrow0800
        )
        _ = store.debugInsertPlan(
            title: "Future course",
            status: "active",
            startDate: liveCalendar.date(byAdding: .day, value: 3, to: liveToday)!,
            endDate: liveCalendar.date(byAdding: .day, value: 10, to: liveToday),
            medicineName: "FutureMed",
            ownerId: owner,
            profileId: profile,
            scheduleTime: "08:00",
            logStatus: DoseLogStatus.pending.rawValue,
            logScheduledAt: liveCalendar.date(byAdding: .day, value: 3, to: liveTomorrow0800)!
        )
        _ = store.debugInsertPlan(
            title: "Past course",
            status: "completed",
            startDate: liveCalendar.date(byAdding: .day, value: -10, to: liveToday)!,
            endDate: liveCalendar.date(byAdding: .day, value: -1, to: liveToday),
            medicineName: "PastMed",
            ownerId: owner,
            profileId: profile,
            scheduleTime: "08:00",
            logStatus: DoseLogStatus.taken.rawValue,
            logScheduledAt: liveCalendar.date(byAdding: .day, value: -2, to: liveToday)!
        )
        _ = store.debugInsertPlan(
            title: "Other owner",
            status: "active",
            startDate: liveToday,
            endDate: liveCalendar.date(byAdding: .day, value: 6, to: liveToday),
            medicineName: "OtherAAS",
            ownerId: otherOwner,
            profileId: profile,
            scheduleTime: "08:00",
            logStatus: DoseLogStatus.pending.rawValue,
            logScheduledAt: liveTomorrow0800
        )
        let second = store.debugInsertMedicine(
            treatmentId: current.treatmentId,
            name: "Beta",
            ownerId: owner,
            profileId: profile,
            scheduleTime: "20:00"
        )
        let confirmPlan = store.debugInsertPlan(
            title: "Confirm only",
            status: "active",
            startDate: liveToday,
            endDate: liveCalendar.date(byAdding: .day, value: 6, to: liveToday),
            medicineName: "ConfirmMed",
            ownerId: owner,
            profileId: profile,
            scheduleTime: "08:00",
            logStatus: DoseLogStatus.pendingConfirmation.rawValue,
            logScheduledAt: liveTomorrow0800
        )

        let rows = store.quietDayCurrentMedicines(now: liveNow)
        let names = rows.map(\.name)
        expect(store.todayNodes().isEmpty, "quiet-day first-clock skip still has todayNodes == 0")
        expect(names.contains("AAS"), "CURRENT AAS is listed on quiet-day Home")
        expect(names.contains("Beta"), "second CURRENT medicine is listed")
        expect(!names.contains("FutureMed"), "FUTURE treatment medicines are not CURRENT quiet-day rows")
        expect(!names.contains("PastMed"), "PAST treatment medicines are not CURRENT quiet-day rows")
        expect(!names.contains("OtherAAS"), "other-owner medicines are filtered out")
        expect(Set(names).count == names.count, "quiet-day rows do not duplicate medicines")
        expect(
            rows.first(where: { $0.id == current.medicineId })?.nextScheduledAt == liveTomorrow0800,
            "AAS next dose is the existing tomorrow DoseLog"
        )
        expect(
            rows.first(where: { $0.id == second })?.nextScheduledAt == nil,
            "medicine with no future DoseLog does not invent a time"
        )
        expect(names.contains("ConfirmMed"), "CURRENT ConfirmMed is still listed")
        expect(
            rows.first(where: { $0.id == confirmPlan.medicineId })?.nextScheduledAt == nil,
            "store pendingConfirmation does not become a quiet-day next dose"
        )
        expect(
            !HomeQuietDayPresentationMapper.showsUpcomingChip(
                nextScheduledAt: rows.first(where: { $0.id == confirmPlan.medicineId })?.nextScheduledAt
            ),
            "store pendingConfirmation hides Upcoming"
        )
        expect(
            HomePlanPresentationMapper.occupancy(
                planReady: true,
                tree: store.journeyTreeSnapshot(now: liveNow),
                hasScheduledToday: !store.todayNodes().isEmpty
            ) == .activeQuietDay,
            "store snapshot stays quiet-day when todayNodes is empty"
        )

        return failures
    }
}
#endif
