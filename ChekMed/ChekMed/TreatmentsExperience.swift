import SwiftUI

/// Treatments family — presentation only. Canonical identity is Treatment UUID / Medicine UUID.
private enum TreatmentsChrome {
    static let cardRadius: CGFloat = 22
    static let fabClearance: CGFloat = 136
}

private func treatmentsDate(_ date: Date, locale: Locale) -> String {
    date.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
}

private func weekProgress(start: Date, end: Date?, calendar: Calendar, now: Date = Date()) -> (current: Int, total: Int, remaining: Int)? {
    guard let end else { return nil }
    let startDay = calendar.startOfDay(for: start)
    let endDay = calendar.startOfDay(for: end)
    let totalDays = max(1, calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 1)
    let totalWeeks = max(1, Int((Double(totalDays) / 7.0).rounded(.up)))
    let elapsed = max(0, calendar.dateComponents([.day], from: startDay, to: calendar.startOfDay(for: now)).day ?? 0)
    let currentWeek = min(totalWeeks, max(1, elapsed / 7 + 1))
    return (currentWeek, totalWeeks, max(0, totalWeeks - currentWeek))
}

private func dateProgress(start: Date, end: Date?, calendar: Calendar, now: Date = Date()) -> Double {
    guard let end else { return 0 }
    let startDay = calendar.startOfDay(for: start)
    let endDay = calendar.startOfDay(for: end)
    let today = calendar.startOfDay(for: now)
    let total = max(1, calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 1)
    let elapsed = calendar.dateComponents([.day], from: startDay, to: today).day ?? 0
    return min(1, max(0, Double(elapsed) / Double(total)))
}

private func durationDays(start: Date, end: Date?, calendar: Calendar) -> Int? {
    guard let end else { return nil }
    return max(1, calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 1)
}

private func medicineCountLabel(_ count: Int, session: SessionStore) -> String {
    count == 1 ? session.t(.treatmentsMedicineCountOne) : session.t(.treatmentsMedicineCountMany, count)
}

/// Formatted skipped-count copy. Never returns a raw `%d` placeholder.
func completedSkippedCountText(_ count: Int, session: SessionStore) -> String {
    count == 1 ? session.t(.journeySkippedOne) : session.t(.journeySkipped, count)
}

/// Detail Finish mutation boundary. Captures the treatment UUID explicitly so a later
/// session/profile bind cannot complete a different row. Reminder rebuild stays on the screen.
enum TreatmentDetailFinishCommand {
    enum Decision: Equatable {
        case confirm
        case cancel
    }

    enum Outcome: Equatable {
        case cancelled
        case refused
        case completed
    }

    /// Presentation effects derived from `Outcome`. Does not call ReminderScheduler.
    struct FollowUp: Equatable {
        var rescheduleReminders: Bool
        var navigate: AppRoute?
        var showRefusalAlert: Bool
    }

    @MainActor
    @discardableResult
    static func apply(
        _ decision: Decision,
        store: CheckMedStore,
        treatmentId: UUID
    ) -> Outcome {
        switch decision {
        case .cancel:
            return .cancelled
        case .confirm:
            return store.completeTreatment(id: treatmentId) ? .completed : .refused
        }
    }

    static func followUp(for outcome: Outcome, successRoute: AppRoute) -> FollowUp {
        switch outcome {
        case .cancelled:
            return FollowUp(rescheduleReminders: false, navigate: nil, showRefusalAlert: false)
        case .refused:
            return FollowUp(rescheduleReminders: false, navigate: nil, showRefusalAlert: true)
        case .completed:
            return FollowUp(rescheduleReminders: true, navigate: successRoute, showRefusalAlert: false)
        }
    }
}

struct TreatmentsRootScreen: View {
    var go: (AppRoute) -> Void
    @Environment(CheckMedStore.self) private var treatments
    @Environment(SessionStore.self) private var session
    @Environment(EntitlementStore.self) private var entitlements
    @State private var showCompleted = false

    private var tree: CheckMedStore.JourneyTreeSnapshot { treatments.journeyTreeSnapshot() }
    private var remainingSlots: Int {
        entitlements.freeMedicineSlotsRemaining(existingCount: treatments.storedMedicineCount)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                header
                segment
                if showCompleted {
                    completedList
                } else {
                    activeList
                    upcomingList
                    addTreatmentCard
                    encouragement
                }
                if !entitlements.isSuper, treatments.storedMedicineCount > 0 {
                    freeSlotsNote
                }
                SafetyCaption()
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, TreatmentsChrome.fabClearance)
        }
        .background(CheckMedTheme.background)
        .checkMedStatusBarSafeContent()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                Text(session.t(.tabTreatments))
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(CheckMedTheme.ink)
                Text(session.t(.treatmentsIntro))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            // Temporary stand-in: phil_clipboard JPEG is black-backed and must not ship.
            // Replace with phil_clipboard transparent PNG when supplied. Do not commit this substitution as final.
            CooperLibraryImage(asset: "phil_doctor_2d", size: 108)
        }
    }

    private var segment: some View {
        HStack(spacing: 8) {
            segmentChip(
                title: "\(session.t(.treatmentsActiveTab)) (\(tree.current.count))",
                selected: !showCompleted
            ) {
                showCompleted = false
            }
            segmentChip(
                title: "\(session.t(.treatmentsCompletedTab)) (\(tree.past.count))",
                selected: showCompleted
            ) {
                showCompleted = true
            }
            Spacer(minLength: 0)
        }
    }

    private func segmentChip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .foregroundStyle(selected ? Color.white : CheckMedTheme.muted)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(selected ? CheckMedTheme.navy : CheckMedTheme.surface, in: Capsule())
                .overlay(Capsule().stroke(CheckMedTheme.hairline, lineWidth: selected ? 0 : 1.25))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var activeList: some View {
        if tree.current.isEmpty {
            Text(session.t(.noTreatmentInProgressHeadline))
                .font(.system(.body, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
        } else {
            ForEach(tree.current) { branch in
                Button { go(.treatmentDetail(branch.id)) } label: {
                    treatmentCard(branch, kind: .current)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var upcomingList: some View {
        if !tree.future.isEmpty {
            Text(session.t(.treatmentsUpcomingTitle))
                .font(.system(.caption, design: .rounded).weight(.heavy))
                .foregroundStyle(CheckMedTheme.muted)
                .padding(.top, 4)
            Text(session.t(.treatmentsUpcomingHint))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(CheckMedTheme.muted)
            ForEach(tree.future) { branch in
                Button { go(.treatmentDetail(branch.id)) } label: {
                    treatmentCard(branch, kind: .future)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var completedList: some View {
        if tree.past.isEmpty {
            Text(session.t(.journeyTreeEmptyPast))
                .font(.system(.body, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
        } else {
            ForEach(tree.past) { branch in
                Button {
                    TreatmentNavPerf.tap(treatmentId: branch.id)
                    go(.treatmentCompleted(branch.id))
                } label: {
                    treatmentCard(branch, kind: .past)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("completed-treatment-\(branch.id.uuidString)")
            }
        }
    }

    private func treatmentCard(_ branch: CheckMedStore.JourneyTreeBranch, kind: TreatmentJourneyKind) -> some View {
        let form = MedicineForm.other
        let weeks = weekProgress(start: branch.startDate, end: branch.endDate, calendar: session.foundationCalendar)
        let progress = dateProgress(start: branch.startDate, end: branch.endDate, calendar: session.foundationCalendar)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                MedicationLibraryImage(form: form, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(branch.title)
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.ink)
                    Text(medicineCountLabel(branch.medicineNames.count, session: session))
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(CheckMedTheme.muted)
                    Text(session.t(.treatmentsStartedOn, treatmentsDate(branch.startDate, locale: session.locale.foundationLocale)))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(CheckMedTheme.muted)
                }
                Spacer(minLength: 0)
                if kind == .current {
                    Text(session.t(.treatmentsInCourse))
                        .font(.system(.caption2, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.primaryShadow)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(CheckMedTheme.mintWash, in: Capsule())
                } else if kind == .future {
                    Text(session.t(.treatmentsUpcomingTitle))
                        .font(.system(.caption2, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.flowDot)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(CheckMedTheme.blueWash, in: Capsule())
                }
            }
            if kind == .current, let weeks {
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(CheckMedTheme.mintWash)
                            Capsule()
                                .fill(CheckMedTheme.primary)
                                .frame(width: max(8, geo.size.width * progress))
                        }
                    }
                    .frame(height: 8)
                    HStack {
                        Text(session.t(.treatmentsWeekOf, weeks.current, weeks.total))
                        Spacer()
                        Text(
                            weeks.remaining == 1
                                ? session.t(.treatmentsWeeksLeftOne)
                                : session.t(.treatmentsWeeksLeftMany, weeks.remaining)
                        )
                    }
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(kind == .current ? CheckMedTheme.mintWash.opacity(0.65) : CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: TreatmentsChrome.cardRadius, style: .continuous))
        .shadow(color: CheckMedTheme.navy.opacity(0.05), radius: 10, y: 4)
    }

    private var addTreatmentCard: some View {
        Button(action: attemptAdd) {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(CheckMedTheme.flowDot)
                    .frame(width: 40, height: 40)
                    .background(CheckMedTheme.blueWash, in: Circle())
                Text(session.t(.treatmentsAddNew))
                    .font(.system(.body, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckMedTheme.ink)
                Spacer()
            }
            .padding(16)
            .background(CheckMedTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: TreatmentsChrome.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TreatmentsChrome.cardRadius, style: .continuous)
                    .stroke(CheckMedTheme.hairline, lineWidth: 1.25)
            )
        }
        .buttonStyle(.plain)
    }

    private var encouragement: some View {
        HStack(alignment: .center, spacing: 12) {
            CooperLibraryImage(asset: "phil_wink", size: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.t(.treatmentsEncourageTitle))
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                Text(session.t(.treatmentsEncourageBody))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(CheckMedTheme.sunshineWash.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: TreatmentsChrome.cardRadius, style: .continuous))
    }

    private var freeSlotsNote: some View {
        Text(
            remainingSlots > 0
                ? session.t(.treatmentsSlotsLeft, treatments.storedMedicineCount, remainingSlots)
                : session.t(.treatmentsSlotsFull)
        )
        .font(.system(.caption, design: .rounded).weight(.semibold))
        .foregroundStyle(CheckMedTheme.muted)
    }

    private func attemptAdd() {
        if !entitlements.isSuper, remainingSlots <= 0 {
            entitlements.presentPaywall()
            return
        }
        go(.addPrescription)
    }
}

struct TreatmentDetailScreen: View {
    private enum Pane: Hashable {
        case overview
        case doses
    }

    var go: (AppRoute) -> Void
    var treatmentId: UUID
    @Environment(CheckMedStore.self) private var treatments
    @Environment(SessionStore.self) private var session
    @Environment(EntitlementStore.self) private var entitlements
    @State private var pane: Pane = .overview
    @State private var didApplyDebugPane = false
    @State private var showFinishConfirm = false
    @State private var showRename = false
    @State private var renameDraft = ""
    @State private var finishTargetId: UUID?
    @State private var showFinishRefused = false

    private var snapshot: CheckMedStore.TreatmentDetailSnapshot? {
        treatments.treatmentDetailSnapshot(id: treatmentId)
    }

    private var isCurrent: Bool { snapshot?.kind == .current }
    private var remainingSlots: Int {
        entitlements.freeMedicineSlotsRemaining(existingCount: treatments.storedMedicineCount)
    }

    var body: some View {
        Group {
            if let snapshot {
                tabContent(snapshot)
            } else {
                ScrollView(showsIndicators: false) {
                    Text(session.t(.todayNothing))
                        .font(.system(.body, design: .rounded).weight(.bold))
                        .padding(16)
                    SafetyCaption().frame(maxWidth: .infinity)
                }
            }
        }
        .background(CheckMedTheme.background)
        .onAppear { applyDebugPaneIfRequested() }
        .navigationTitle(session.t(.treatmentDetailsTitle))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("treatment-detail-\(treatmentId.uuidString)")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                overflowMenu
            }
        }
        .alert(session.t(.finishTreatmentCouldNotComplete), isPresented: $showFinishRefused) {
            Button(session.t(.tryAgain), role: .cancel) {}
        } message: {
            Text(session.t(.finishTreatmentCouldNotCompleteBody))
        }
        .alert(session.t(.treatmentsRename), isPresented: $showRename) {
            TextField(session.t(.treatmentsRenamePrompt), text: $renameDraft)
            Button(session.t(.cancel), role: .cancel) {}
            Button(session.t(.done)) {
                _ = treatments.setTreatmentTitle(id: treatmentId, title: renameDraft)
            }
        }
        .sheet(isPresented: $showFinishConfirm) {
            FinishTreatmentConfirmSheet(
                missingMedicineNames: treatments.incompleteMedicineNames(
                    forTreatmentId: finishTargetId ?? treatmentId
                ),
                onScanNew: { finishTreatment(then: .addPrescription) },
                onSeeReport: { finishTreatment(then: .journeyReport) },
                onCancel: {
                    let cancelled = TreatmentDetailFinishCommand.apply(
                        .cancel,
                        store: treatments,
                        treatmentId: finishTargetId ?? treatmentId
                    )
                    let follow = TreatmentDetailFinishCommand.followUp(
                        for: cancelled,
                        successRoute: .journeyReport
                    )
                    showFinishConfirm = false
                    if follow.rescheduleReminders {
                        ReminderScheduler.shared.reschedule()
                    }
                    if let route = follow.navigate {
                        DispatchQueue.main.async { go(route) }
                    }
                }
            )
            .environment(session)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private func tabContent(_ snapshot: CheckMedStore.TreatmentDetailSnapshot) -> some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 12, pinnedViews: []) {
                if pane == .overview {
                    overviewHero(snapshot)
                } else {
                    dosesIdentity(snapshot)
                }
                panePicker
                if pane == .overview {
                    overviewBody(snapshot)
                } else {
                    dosesBody(snapshot)
                }
                SafetyCaption().frame(maxWidth: .infinity)
            }
            .padding(16)
            .padding(.bottom, TreatmentsChrome.fabClearance)
        }
    }

    private var overflowMenu: some View {
        Menu {
            Button {
                renameDraft = snapshot?.title ?? ""
                showRename = true
            } label: {
                Label(session.t(.treatmentsRename), systemImage: "pencil")
            }
            if isCurrent {
                Button(action: attemptAdd) {
                    Label(session.t(.treatmentsAddMedicine), systemImage: "plus")
                }
                Button {
                    finishTargetId = treatmentId
                    showFinishConfirm = true
                } label: {
                    Label(session.t(.completeTreatment), systemImage: "checkmark.circle")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(CheckMedTheme.navy)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier("treatment-detail-overflow")
        .accessibilityLabel(session.t(.treatmentDetailsTitle))
    }

    private var panePicker: some View {
        HStack(spacing: 8) {
            paneChip(.overview, title: session.t(.treatmentDetailTabOverview))
            paneChip(.doses, title: session.t(.treatmentDetailTabDoses))
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
    }

    private func paneChip(_ value: Pane, title: String) -> some View {
        let selected = pane == value
        return Button {
            pane = value
        } label: {
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .foregroundStyle(selected ? Color.white : CheckMedTheme.muted)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(selected ? CheckMedTheme.navy : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(value == .overview ? "treatment-detail-tab-overview" : "treatment-detail-tab-doses")
    }

    private func overviewHero(_ snapshot: CheckMedStore.TreatmentDetailSnapshot) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                lifecycleChip(snapshot)
                Text(snapshot.title)
                    .font(.system(.title2, design: .rounded).weight(.black))
                    .foregroundStyle(CheckMedTheme.navy)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("treatment-detail-title")
                Text(periodText(snapshot))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            CooperLibraryImage(asset: "phil_doctor_2d", size: 128)
                .accessibilityHidden(true)
        }
    }

    private func dosesIdentity(_ snapshot: CheckMedStore.TreatmentDetailSnapshot) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                lifecycleChip(snapshot)
                Text(snapshot.title)
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckMedTheme.navy)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            CooperLibraryImage(asset: "phil_doctor_2d", size: 76)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("treatment-detail-doses-identity")
    }

    private func lifecycleChip(_ snapshot: CheckMedStore.TreatmentDetailSnapshot) -> some View {
        let title: String
        let tint: Color
        let wash: Color
        let icon: String
        switch snapshot.kind {
        case .past:
            title = session.t(.treatmentsCompletedTab)
            tint = CheckMedTheme.primaryShadow
            wash = CheckMedTheme.mintWash
            icon = "checkmark.circle.fill"
        case .current:
            title = session.t(.treatmentsInCourse)
            tint = CheckMedTheme.primaryShadow
            wash = CheckMedTheme.mintWash
            icon = "circle.fill"
        case .future:
            title = session.t(.treatmentsUpcomingTitle)
            tint = CheckMedTheme.navy
            wash = CheckMedTheme.blueWash
            icon = "clock.fill"
        }
        return HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
            Text(title)
                .font(.system(.caption, design: .rounded).weight(.heavy))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(wash, in: Capsule())
    }

    private func overviewBody(_ snapshot: CheckMedStore.TreatmentDetailSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if snapshot.kind == .past {
                encouragement(snapshot)
            }
            summaryCard(snapshot)
            medicinesSection(snapshot.medicines)
            if isCurrent {
                addMedicineButton
            }
            if snapshot.kind != .past {
                encouragement(snapshot)
            }
            reportButton
            if isCurrent {
                CheckMedButton(title: session.t(.completeTreatment), style: .ghost) {
                    finishTargetId = treatmentId
                    showFinishConfirm = true
                }
            }
        }
    }

    private func summaryCard(_ snapshot: CheckMedStore.TreatmentDetailSnapshot) -> some View {
        let weeks = weekProgress(
            start: snapshot.startDate,
            end: snapshot.endDate,
            calendar: session.foundationCalendar
        )
        return VStack(alignment: .leading, spacing: 8) {
            Text(session.t(.treatmentsSummary))
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .foregroundStyle(CheckMedTheme.navy)
            summaryRow("calendar", session.t(.treatmentDetailPeriod), periodText(snapshot))
            summaryRow(
                "pills.fill",
                session.t(.treatmentsMedicinesHeader),
                snapshot.medicines.map(\.name).joined(separator: " + ")
            )
            summaryRow(
                "checkmark.circle.fill",
                session.t(.treatmentDetailTaken),
                session.t(.treatmentDetailTakenValueFormat, snapshot.takenCount, snapshot.percent),
                tint: CheckMedTheme.primary
            )
            summaryRow(
                "xmark.circle.fill",
                session.t(.treatmentDetailSkipped),
                "\(snapshot.skippedCount)",
                tint: CheckMedTheme.danger
            )
            VStack(alignment: .leading, spacing: 6) {
                summaryRow(
                    "list.bullet.rectangle",
                    session.t(.treatmentDetailPlannedDoses),
                    session.t(.treatmentDetailPerDayFormat, snapshot.timesPerDay)
                )
                if let days = durationDays(
                    start: snapshot.startDate,
                    end: snapshot.endDate,
                    calendar: session.foundationCalendar
                ) {
                    summaryRow("clock", session.t(.treatmentsDurationDays), "\(days)")
                }
                if let weeks {
                    summaryRow(
                        "chart.bar",
                        session.t(.treatmentsWeekOf, weeks.current, weeks.total),
                        weeks.remaining == 1
                            ? session.t(.treatmentsWeeksLeftOne)
                            : session.t(.treatmentsWeeksLeftMany, weeks.remaining)
                    )
                }
            }
            .padding(.top, 2)
            .opacity(0.92)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: TreatmentsChrome.cardRadius, style: .continuous))
        .shadow(color: CheckMedTheme.navy.opacity(0.05), radius: 10, y: 4)
    }

    private func summaryRow(_ icon: String, _ label: String, _ value: String, tint: Color? = nil) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint ?? CheckMedTheme.navy.opacity(0.7))
                .frame(width: 18)
            Text(label)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(CheckMedTheme.muted)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .foregroundStyle(CheckMedTheme.navy)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func medicinesSection(_ medicines: [CheckMedStore.MedicineSummary]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(session.t(.treatmentsMedicinesHeader))
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                Text("(\(medicines.count))")
                    .foregroundStyle(CheckMedTheme.muted)
                Spacer()
            }
            ForEach(medicines) { med in
                Button { go(.medicationDetail(med.id)) } label: {
                    HStack(spacing: 12) {
                        MedicationLibraryImage(form: med.form, size: 46)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(med.name)
                                .font(.system(.body, design: .rounded).weight(.heavy))
                                .foregroundStyle(CheckMedTheme.ink)
                            Text("\(med.doseLabel) · \(session.t(.timesPerDayFormat, med.timesPerDay))")
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .foregroundStyle(CheckMedTheme.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(CheckMedTheme.muted)
                    }
                    .padding(12)
                    .background(CheckMedTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: CheckMedTheme.navy.opacity(0.04), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("treatment-medicine-\(med.id.uuidString)")
                .accessibilityLabel(med.name)
            }
        }
    }

    private var addMedicineButton: some View {
        Button(action: attemptAdd) {
            HStack {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CheckMedTheme.primaryShadow)
                Text(session.t(.treatmentsAddMedicine))
                    .font(.system(.body, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckMedTheme.ink)
                Spacer()
            }
            .padding(14)
            .background(CheckMedTheme.mintWash.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func encouragement(_ snapshot: CheckMedStore.TreatmentDetailSnapshot) -> some View {
        let title: String
        let body: String
        switch snapshot.kind {
        case .past where isFullyTakenOnTime(snapshot):
            title = session.t(.treatmentsCompletedHeadline)
            body = session.t(.treatmentDetailCompletedOnTime)
        case .past:
            title = session.t(.treatmentsCompletedHeadline)
            body = session.t(.treatmentsCompletedSupport)
        case .future:
            title = session.t(.treatmentsUpcomingTitle)
            body = session.t(.treatmentsUpcomingHint)
        case .current:
            title = session.t(.treatmentsEncourageTitle)
            body = session.t(.treatmentsEncourageBody)
        }
        return HStack(alignment: .center, spacing: 12) {
            CooperLibraryImage(asset: snapshot.kind == .past ? "phil_heart" : "phil_wink", size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckMedTheme.navy)
                Text(body)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(CheckMedTheme.sunshineWash.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var reportButton: some View {
        Button { go(.journeyReport) } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 16, weight: .bold))
                Text(session.t(.treatmentDetailViewReport))
                    .font(.system(.body, design: .rounded).weight(.heavy))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(CheckMedTheme.navy)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(CheckMedTheme.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(CheckMedTheme.navy.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(session.t(.treatmentsViewMedicalReport))
    }

    private func dosesBody(_ snapshot: CheckMedStore.TreatmentDetailSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if isFullyTakenOnTime(snapshot) {
                compactDosesCelebration()
            }
            doseProgressCard(snapshot)
            if snapshot.events.isEmpty {
                Text(session.t(.treatmentDetailEmptyDoses))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CheckMedTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                ForEach(doseDays(snapshot.events), id: \.day) { group in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(treatmentsDate(group.day, locale: session.locale.foundationLocale))
                            .font(.system(.subheadline, design: .rounded).weight(.heavy))
                            .foregroundStyle(CheckMedTheme.navy)
                            .padding(.top, 4)
                        ForEach(group.events) { event in
                            doseRow(event)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("treatment-detail-doses")
    }

    private func compactDosesCelebration() -> some View {
        HStack(alignment: .center, spacing: 10) {
            CooperLibraryImage(asset: "phil_heart", size: 52)
            Text(session.t(.treatmentDetailAllDosesOnTime))
                .font(.system(.caption, design: .rounded).weight(.heavy))
                .foregroundStyle(CheckMedTheme.navy)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(CheckMedTheme.sunshineWash.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func doseProgressCard(_ snapshot: CheckMedStore.TreatmentDetailSnapshot) -> some View {
        let fraction = snapshot.dueCount == 0 ? 0 : CGFloat(snapshot.takenCount) / CGFloat(snapshot.dueCount)
        return VStack(alignment: .leading, spacing: 10) {
            Text(session.t(.treatmentDetailDoseHistory))
                .font(.system(.title3, design: .rounded).weight(.black))
                .foregroundStyle(CheckMedTheme.navy)
            Text(session.t(.treatmentDetailDoseProgressFormat, snapshot.takenCount, snapshot.dueCount, snapshot.percent))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(CheckMedTheme.muted)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(CheckMedTheme.mintWash)
                    Capsule()
                        .fill(CheckMedTheme.primary)
                        .frame(width: max(snapshot.dueCount == 0 ? 0 : 8, geo.size.width * min(1, fraction)))
                }
            }
            .frame(height: 10)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: TreatmentsChrome.cardRadius, style: .continuous))
        .shadow(color: CheckMedTheme.navy.opacity(0.05), radius: 10, y: 4)
    }

    private func doseRow(_ event: CheckMedStore.TreatmentDoseEvent) -> some View {
        Button { go(.medicationDetail(event.medicineId)) } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: doseSymbol(event.status))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(doseTint(event.status))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(event.scheduledAt.formatted(.dateTime.hour().minute().locale(session.locale.foundationLocale)))
                            .font(.system(.subheadline, design: .rounded).weight(.heavy))
                            .foregroundStyle(CheckMedTheme.navy)
                            .monospacedDigit()
                        Text(event.medicineName)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(CheckMedTheme.navy)
                            .multilineTextAlignment(.leading)
                    }
                    if let confirmed = event.confirmedAt, event.status.isConfirmedTaken {
                        Text(session.t(.treatmentDetailConfirmedAt, confirmed.formatted(.dateTime.hour().minute().locale(session.locale.foundationLocale))))
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            .foregroundStyle(CheckMedTheme.muted)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CheckMedTheme.muted)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("treatment-dose-\(event.id.uuidString)")
            .accessibilityLabel("\(event.medicineName), \(event.status.rawValue)")
            .accessibilityValue(event.status.rawValue)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("treatment-dose-\(event.id.uuidString)")
        .accessibilityLabel("\(event.medicineName), \(event.status.rawValue)")
        .accessibilityValue(event.status.rawValue)
    }

    private func applyDebugPaneIfRequested() {
        #if DEBUG
        guard !didApplyDebugPane else { return }
        guard TH1LocalVerification.isAllowed else { return }
        guard ProcessInfo.processInfo.environment["CHECKMED_TH2_TAB"] == "doses" else { return }
        didApplyDebugPane = true
        pane = .doses
        #endif
    }

    private func doseDays(
        _ events: [CheckMedStore.TreatmentDoseEvent]
    ) -> [(day: Date, events: [CheckMedStore.TreatmentDoseEvent])] {
        let calendar = session.foundationCalendar
        var grouped: [(Date, [CheckMedStore.TreatmentDoseEvent])] = []
        var index: [Date: Int] = [:]
        for event in events {
            let day = calendar.startOfDay(for: event.scheduledAt)
            if let i = index[day] {
                grouped[i].1.append(event)
            } else {
                index[day] = grouped.count
                grouped.append((day, [event]))
            }
        }
        return grouped.map { (day: $0.0, events: $0.1) }
    }

    private func isFullyTaken(_ snapshot: CheckMedStore.TreatmentDetailSnapshot) -> Bool {
        snapshot.kind == .past
            && snapshot.dueCount > 0
            && snapshot.skippedCount == 0
            && snapshot.takenCount == snapshot.dueCount
    }

    private func isFullyTakenOnTime(_ snapshot: CheckMedStore.TreatmentDetailSnapshot) -> Bool {
        isFullyTaken(snapshot)
            && !snapshot.events.isEmpty
            && snapshot.events.allSatisfy { $0.status == .taken }
    }

    private func doseSymbol(_ status: DoseLogStatus) -> String {
        if status.isConfirmedTaken { return "checkmark.circle.fill" }
        if status.isMissedLike { return "xmark.circle.fill" }
        return "clock.circle"
    }

    private func doseTint(_ status: DoseLogStatus) -> Color {
        if status.isConfirmedTaken { return CheckMedTheme.primary }
        if status.isMissedLike { return CheckMedTheme.danger }
        return CheckMedTheme.muted
    }

    private func periodText(_ snapshot: CheckMedStore.TreatmentDetailSnapshot) -> String {
        let locale = session.locale.foundationLocale
        let start = treatmentsDate(snapshot.startDate, locale: locale)
        if let end = snapshot.endDate {
            return "\(start) – \(treatmentsDate(end, locale: locale))"
        }
        return start
    }

    private func attemptAdd() {
        if !entitlements.isSuper, remainingSlots <= 0 {
            entitlements.presentPaywall()
            return
        }
        go(.addPrescription)
    }

    private func finishTreatment(then route: AppRoute) {
        let id = finishTargetId ?? treatmentId
        let outcome = TreatmentDetailFinishCommand.apply(.confirm, store: treatments, treatmentId: id)
        showFinishConfirm = false
        let follow = TreatmentDetailFinishCommand.followUp(for: outcome, successRoute: route)
        if follow.showRefusalAlert {
            showFinishRefused = true
        }
        if follow.rescheduleReminders {
            ReminderScheduler.shared.reschedule()
        }
        if let next = follow.navigate {
            DispatchQueue.main.async { go(next) }
        }
    }
}

struct TreatmentsMedicationDetailScreen: View {
    var go: (AppRoute) -> Void
    var medicineId: UUID
    @Environment(CheckMedStore.self) private var treatments
    @Environment(SessionStore.self) private var session
    @Environment(TodayPathStore.self) private var path
    @State private var showDeleteRecipeConfirm = false

    private var medicine: CheckMedStore.MedicineSummary? {
        treatments.reportMedicineSummaries().first { $0.id == medicineId }
    }

    private var isCurrent: Bool {
        guard let medicine else { return false }
        return treatments.isCurrentOnJourneyHistory(treatmentId: medicine.treatmentId)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                if let medicine {
                    HStack(alignment: .top, spacing: 14) {
                        MedicationLibraryImage(form: medicine.form, size: 72)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(medicine.name)
                                .font(.system(size: 26, weight: .black, design: .rounded))
                            Text(formTitle(medicine.form))
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(CheckMedTheme.muted)
                        }
                        Spacer()
                    }
                    facts(medicine)
                    CheckMedButton(title: session.t(.treatmentsSchedulesTitle)) {
                        go(.medicationSchedule(medicine.id))
                    }
                    if isCurrent {
                        CheckMedButton(title: session.t(.howYouTakeIt), style: .secondary) {
                            go(.howToTake(medicine.id))
                        }
                    }
                    CheckMedButton(title: session.t(.deleteRecipe), style: .ghost) {
                        showDeleteRecipeConfirm = true
                    }
                } else {
                    Text(session.t(.todayNothing))
                        .font(.system(.body, design: .rounded).weight(.bold))
                }
                Text(session.t(.planOnlyDisclaimer))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.safety)
            }
            .padding(16)
            .padding(.bottom, TreatmentsChrome.fabClearance)
        }
        .background(CheckMedTheme.background)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("treatment-medicine-detail-\(medicineId.uuidString)")
        .toolbar {
            if let medicine, isCurrent {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(session.t(.howYouTakeIt)) { go(.howToTake(medicine.id)) }
                }
            }
        }
        .confirmationDialog(
            session.t(.deleteRecipeConfirm),
            isPresented: $showDeleteRecipeConfirm,
            titleVisibility: .visible
        ) {
            Button(session.t(.deleteRecipeYes), role: .destructive) {
                guard let medicine else { return }
                treatments.deleteMedicine(id: medicine.id)
                path.reload()
                go(.addPrescription)
            }
            Button(session.t(.cancel), role: .cancel) {}
        }
    }

    private func facts(_ medicine: CheckMedStore.MedicineSummary) -> some View {
        VStack(spacing: 10) {
            fact(session.t(.manualDose), medicine.doseLabel)
            fact(session.t(.treatmentsTimesPerDose), medicine.doseLabel)
            fact(session.t(.treatmentsDosesPerDay), session.t(.timesPerDayFormat, medicine.timesPerDay))
            if !medicine.scheduleTimes.isEmpty {
                Button { go(.medicationSchedule(medicine.id)) } label: {
                    factRow(session.t(.treatmentsDoseTimes), medicine.scheduleTimes.joined(separator: " · "), chevron: true)
                }
                .buttonStyle(.plain)
            }
            if let start = relatedBranch?.startDate {
                fact(session.t(.treatmentsStartDate), treatmentsDate(start, locale: session.locale.foundationLocale))
            }
            if let end = relatedBranch?.endDate {
                fact(session.t(.treatmentsExpectedEnd), treatmentsDate(end, locale: session.locale.foundationLocale))
            }
            if !medicine.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fact(session.t(.medicineReason), medicine.reason)
            }
            if !medicine.doctorNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fact(session.t(.treatmentsNotesOptional), medicine.doctorNotes)
            }
        }
    }

    private var relatedBranch: CheckMedStore.JourneyTreeBranch? {
        guard let medicine else { return nil }
        let tree = treatments.journeyTreeSnapshot()
        return (tree.current + tree.future + tree.past).first { $0.id == medicine.treatmentId }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        factRow(label, value, chevron: false)
    }

    private func factRow(_ label: String, _ value: String, chevron: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
                Text(value)
                    .font(.system(.body, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckMedTheme.ink)
            }
            Spacer()
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CheckMedTheme.muted)
            }
        }
        .padding(14)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func formTitle(_ form: MedicineForm) -> String {
        switch form {
        case .tablet: session.t(.formTablet)
        case .capsule: session.t(.formCapsule)
        case .syrup: session.t(.formSyrup)
        case .drops: session.t(.formDrops)
        case .powder: session.t(.formPowder)
        case .other: session.t(.formOther)
        }
    }
}

struct MedicationScheduleScreen: View {
    var go: (AppRoute) -> Void
    var medicineId: UUID
    @Environment(CheckMedStore.self) private var treatments
    @Environment(SessionStore.self) private var session

    private var medicine: CheckMedStore.MedicineSummary? {
        treatments.reportMedicineSummaries().first { $0.id == medicineId }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                if let medicine {
                    HStack(spacing: 12) {
                        MedicationLibraryImage(form: medicine.form, size: 52)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.t(.treatmentsSchedulesTitle))
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .foregroundStyle(CheckMedTheme.muted)
                            Text(medicine.name)
                                .font(.system(.title3, design: .rounded).weight(.black))
                            Text(medicine.doseLabel)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(CheckMedTheme.muted)
                        }
                    }
                    Text(session.t(.treatmentsDoseTimes))
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                    if medicine.scheduleTimes.isEmpty {
                        Text(session.t(.remindersNoneScheduled))
                            .font(.system(.body, design: .rounded).weight(.bold))
                            .foregroundStyle(CheckMedTheme.muted)
                    } else {
                        ForEach(medicine.scheduleTimes, id: \.self) { time in
                            HStack {
                                Image(systemName: "clock.fill")
                                    .foregroundStyle(CheckMedTheme.flowDot)
                                Text(time)
                                    .font(.system(.title3, design: .rounded).weight(.heavy))
                                Spacer()
                            }
                            .padding(14)
                            .background(CheckMedTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                    Text(session.t(.treatmentsScheduleReadOnly))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(CheckMedTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(session.t(.treatmentsRemindersHeader))
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                        .padding(.top, 8)
                    globalRow(session.t(.treatmentsReminderGlobal), session.t(.prefsTypes))
                    globalRow(session.t(.treatmentsSoundGlobal), session.t(.alarmThemePhil))
                    globalRow(
                        session.t(.treatmentsAdvanceGlobal),
                        ReminderPreferences.advanceHourEnabled ? session.t(.advanceHourToggle) : session.t(.todayNothing)
                    )
                    globalRow(
                        session.t(.treatmentsGraceGlobal),
                        "\(ReminderPreferences.confirmationGraceMinutes)"
                    )
                    CheckMedButton(title: session.t(.treatmentsOpenNotificationPrefs), style: .secondary) {
                        go(.notificationPrefs)
                    }
                } else {
                    Text(session.t(.todayNothing))
                        .font(.system(.body, design: .rounded).weight(.bold))
                }
            }
            .padding(16)
            .padding(.bottom, TreatmentsChrome.fabClearance)
        }
        .background(CheckMedTheme.background)
        .navigationTitle(session.t(.treatmentsSchedulesTitle))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func globalRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
            Text(value)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(CheckMedTheme.muted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckMedTheme.blueWash.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct TreatmentCompletedScreen: View {
    var go: (AppRoute) -> Void
    var treatmentId: UUID
    @Environment(CheckMedStore.self) private var treatments
    @Environment(SessionStore.self) private var session
    @Environment(EntitlementStore.self) private var entitlements
    @State private var prepared: (
        branch: CheckMedStore.JourneyTreeBranch?,
        report: JourneyReport?,
        medicineNames: [String]
    )?

    private var remainingSlots: Int {
        entitlements.freeMedicineSlotsRemaining(existingCount: treatments.storedMedicineCount)
    }

    var body: some View {
        let _ = TreatmentNavPerf.mark("TreatmentCompletedScreen body")
        let prepared = self.prepared ?? computePrepared()
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(CheckMedTheme.primary)
                    Spacer()
                }
                if let branch = prepared.branch {
                    Text(branch.title)
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                        .frame(maxWidth: .infinity)
                    Text(dateRange(branch))
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(CheckMedTheme.muted)
                        .frame(maxWidth: .infinity)
                }
                HStack(alignment: .center, spacing: 12) {
                    CooperLibraryImage(asset: "phil_heart", size: 88)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(session.t(.treatmentsCompletedHeadline))
                            .font(.system(.title3, design: .rounded).weight(.black))
                        Text(session.t(.treatmentsCompletedSupport))
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(CheckMedTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
                .background(CheckMedTheme.mintWash)
                .clipShape(RoundedRectangle(cornerRadius: TreatmentsChrome.cardRadius, style: .continuous))

                summaryCard(branch: prepared.branch, report: prepared.report, medicineNames: prepared.medicineNames)
                CheckMedButton(title: session.t(.treatmentsViewMedicines)) {
                    go(.treatmentDetail(treatmentId))
                }
                CheckMedButton(title: session.t(.treatmentsViewDetails), style: .secondary) {
                    go(.treatmentDetail(treatmentId))
                }
                CheckMedButton(title: session.t(.treatmentsViewMedicalReport), style: .secondary) {
                    go(.journeyReport)
                }
                CheckMedButton(title: session.t(.treatmentsAddAgain), style: .ghost, action: attemptAdd)
            }
            .padding(16)
            .padding(.bottom, TreatmentsChrome.fabClearance)
        }
        .background(CheckMedTheme.background)
        .navigationTitle(session.t(.treatmentsCompletedKicker))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("treatment-completed-\(treatmentId.uuidString)")
        .onAppear {
            TreatmentNavPerf.mark("TreatmentCompletedScreen onAppear")
            if self.prepared == nil {
                self.prepared = prepared
            }
        }
    }

    private func computePrepared() -> (
        branch: CheckMedStore.JourneyTreeBranch?,
        report: JourneyReport?,
        medicineNames: [String]
    ) {
        TreatmentNavPerf.mark("computePrepared start")
        let report = treatments.journeyReport(treatmentId: treatmentId)
        TreatmentNavPerf.mark("journeyReport(treatmentId)")
        if let report {
            let branch = CheckMedStore.JourneyTreeBranch(
                id: report.treatmentId,
                title: report.title,
                startDate: report.startDate,
                endDate: report.endDate,
                medicineNames: report.medicines
            )
            TreatmentNavPerf.mark("branch from report")
            return (branch, report, report.medicines)
        }
        TreatmentNavPerf.mark("report missing — snapshot fallback")
        let tree = treatments.journeyTreeSnapshot()
        TreatmentNavPerf.mark("journeyTreeSnapshot fallback")
        let branch = tree.past.first { $0.id == treatmentId }
            ?? (tree.current + tree.future).first { $0.id == treatmentId }
        return (branch, nil, branch?.medicineNames ?? [])
    }

    private func summaryCard(
        branch: CheckMedStore.JourneyTreeBranch?,
        report: JourneyReport?,
        medicineNames: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(session.t(.treatmentsSummary))
                .font(.system(.headline, design: .rounded).weight(.heavy))
            if let branch, let days = durationDays(start: branch.startDate, end: branch.endDate, calendar: session.foundationCalendar) {
                row(session.t(.treatmentsDurationDays), "\(days)")
            }
            row(session.t(.treatmentsMedicinesHeader), medicineCountLabel(medicineNames.count, session: session))
            if let report {
                row(session.t(.treatmentsDosesConfirmed), "\(report.takenCount)/\(report.plannedCount) (\(report.percent)%)")
                Text(completedSkippedCountText(report.skippedCount, session: session))
                    .foregroundStyle(CheckMedTheme.muted)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .accessibilityIdentifier("completed-skipped-count")
            }
            ForEach(Array(medicineNames.enumerated()), id: \.offset) { _, name in
                HStack(spacing: 10) {
                    MedicationLibraryImage(form: .other, size: 32)
                    Text(name)
                        .font(.system(.subheadline, design: .rounded).weight(.heavy))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: TreatmentsChrome.cardRadius, style: .continuous))
        .shadow(color: CheckMedTheme.navy.opacity(0.04), radius: 8, y: 3)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(CheckMedTheme.muted)
            Spacer()
            Text(value).fontWeight(.heavy)
        }
        .font(.system(.subheadline, design: .rounded).weight(.semibold))
    }

    private func dateRange(_ branch: CheckMedStore.JourneyTreeBranch) -> String {
        let locale = session.locale.foundationLocale
        let start = treatmentsDate(branch.startDate, locale: locale)
        if let end = branch.endDate {
            return "\(start) – \(treatmentsDate(end, locale: locale))"
        }
        return start
    }

    private func attemptAdd() {
        if !entitlements.isSuper, remainingSlots <= 0 {
            entitlements.presentPaywall()
            return
        }
        go(.addPrescription)
    }
}
