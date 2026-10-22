import PhotosUI
import SwiftUI

/// Refill / stock family — presentation only. Canonical writes go through `updateMedicineStock`.
private enum RefillChrome {
    static let cardRadius: CGFloat = 22
    /// Matches `FloatingPlusMenu` + `ProgressOverlayGeometry`: floating tab bar
    /// 52 + gap 10 + plus 58 + 16 breathing. Color.clear only — cream shows through.
    static let fabClearance: CGFloat = 52 + 10 + 58 + 16

    static var fabScrollClearance: some View {
        Color.clear
            .frame(height: fabClearance)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    static func pinnedFooter<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity)
                .background(CheckMedTheme.background)
            fabScrollClearance
        }
    }
}

private enum StockBand {
    case healthy, low, empty, unknown
}

private func stockBand(_ med: CheckMedStore.MedicineSummary) -> StockBand {
    if med.stockPercent <= 0.5 { return .empty }
    if let remaining = remainingAmount(med), remaining.amount <= 0.05 { return .empty }
    guard med.refillDataComplete else { return .unknown }
    if let days = med.daysLeft, days.isFinite, days <= Double(ReminderPreferences.lowStockDaysThreshold) {
        return .low
    }
    return .healthy
}

private func remainingAmount(_ med: CheckMedStore.MedicineSummary) -> (amount: Double, unit: MedicineUnit)? {
    MedicineUnits.remainingDisplayAmount(
        packageAmount: med.packageAmount,
        packageUnit: med.packageUnit,
        stockPercent: med.stockPercent
    )
}

private func formatAmount(_ amount: Double) -> String {
    amount == amount.rounded() ? String(Int(amount.rounded())) : String(format: "%.1f", amount)
}

private func quantityLabel(_ med: CheckMedStore.MedicineSummary, session: SessionStore) -> String? {
    guard let remaining = remainingAmount(med) else { return nil }
    return "\(formatAmount(remaining.amount)) \(localizedUnit(remaining.unit, amount: remaining.amount, session: session))"
}

/// Presentation-only. Canonical `MedicineUnit` raw values stay unchanged.
private func localizedUnit(_ unit: MedicineUnit, amount: Double, session: SessionStore) -> String {
    let plural = abs(amount - 1) > 0.05
    switch unit {
    case .tablet: return session.t(plural ? .unitTabletPlural : .unitTablet)
    case .capsule: return session.t(plural ? .unitCapsulePlural : .unitCapsule)
    case .ml: return session.t(.unitMl)
    case .liter: return session.t(.unitLiter)
    case .g: return session.t(.unitGram)
    case .mg: return session.t(.unitMg)
    case .mcg: return session.t(.unitMcg)
    case .drop: return session.t(plural ? .unitDropPlural : .unitDrop)
    case .tsp: return session.t(.unitTsp)
    case .tbsp: return session.t(.unitTbsp)
    case .oz: return session.t(.unitOz)
    case .spray: return session.t(plural ? .unitSprayPlural : .unitSpray)
    case .unit: return session.t(plural ? .unitCountPlural : .unitCount)
    case .other: return session.t(.unitOther)
    }
}

private func daysLabel(_ med: CheckMedStore.MedicineSummary, session: SessionStore) -> String {
    guard let days = med.daysLeft, days.isFinite else { return session.t(.refillDurationUnknown) }
    if days < 1 { return session.t(.refillLessThanDay) }
    return "\(Int(days.rounded(.down)))"
}

private func estimatedDaysPhrase(_ med: CheckMedStore.MedicineSummary, session: SessionStore) -> String {
    guard let days = med.daysLeft, days.isFinite else { return session.t(.refillDurationUnknown) }
    if days < 1 { return session.t(.refillEstimatedDays, session.t(.refillLessThanDay)) }
    let count = Int(days.rounded(.down))
    if count == 1 { return session.t(.refillEstimatedDaysOne) }
    return session.t(.refillEstimatedDays, "\(count)")
}

private func daysLeftPhrase(_ med: CheckMedStore.MedicineSummary, session: SessionStore) -> String {
    guard let days = med.daysLeft, days.isFinite else { return session.t(.refillDurationUnknown) }
    if days < 1 { return session.t(.refillDaysLeftFormat, session.t(.refillLessThanDay)) }
    let count = Int(days.rounded(.down))
    if count == 1 { return session.t(.refillDaysLeftFormatOne) }
    return session.t(.refillDaysLeftFormat, "\(count)")
}

private func formTitle(_ form: MedicineForm, session: SessionStore) -> String {
    switch form {
    case .tablet: session.t(.formTablet)
    case .capsule: session.t(.formCapsule)
    case .syrup: session.t(.formSyrup)
    case .drops: session.t(.formDrops)
    case .powder: session.t(.formPowder)
    case .other: session.t(.formOther)
    }
}

private func refillDate(_ date: Date, locale: Locale) -> String {
    date.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
}

private func lookupMedicine(id: UUID, treatments: CheckMedStore) -> CheckMedStore.MedicineSummary? {
    treatments.reportCurrentMedicines().first { $0.id == id }
        ?? treatments.reportMedicineSummaries().first { $0.id == id }
}

struct RefillRootScreen: View {
    var go: (AppRoute) -> Void
    @Environment(CheckMedStore.self) private var treatments
    @Environment(SessionStore.self) private var session
    @Environment(EntitlementStore.self) private var entitlements
    @State private var filter: Filter = .all
    @State private var showTip = false
    @State private var tipMedicine: CheckMedStore.MedicineSummary?

    enum Filter { case all, low, empty }

    private var medicines: [CheckMedStore.MedicineSummary] { treatments.reportCurrentMedicines() }

    private var filtered: [CheckMedStore.MedicineSummary] {
        switch filter {
        case .all: medicines
        case .low: medicines.filter { stockBand($0) == .low }
        case .empty: medicines.filter { stockBand($0) == .empty }
        }
    }

    private var lowCount: Int { medicines.filter { stockBand($0) == .low }.count }
    private var emptyCount: Int { medicines.filter { stockBand($0) == .empty }.count }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                header
                segment
                if medicines.isEmpty {
                    Text(session.t(.refillEmpty))
                        .font(.system(.body, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.muted)
                    CheckMedButton(title: session.t(.homeScan)) { go(.addPrescription) }
                } else if filtered.isEmpty {
                    Text(session.t(.refillFilterNone))
                        .font(.system(.body, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.muted)
                } else {
                    ForEach(filtered) { med in
                        Button {
                            switch stockBand(med) {
                            case .low, .empty: go(.lowStock(med.id))
                            case .healthy, .unknown: go(.medicationStock(med.id))
                            }
                        } label: {
                            stockCard(med)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !entitlements.isSuper {
                    superCard
                }
                Text(session.t(.refillDisclaimer))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.safety)
                    .fixedSize(horizontal: false, vertical: true)
                SafetyCaption()
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: RefillChrome.fabClearance)
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .background(CheckMedTheme.background)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { presentTipIfNeeded() }
        .alert(session.t(.refillTipTitle), isPresented: $showTip) {
            Button(session.t(.ok), role: .cancel) { showTip = false }
            if let tipMedicine {
                Button(session.t(.refillTipOpen)) {
                    showTip = false
                    go(.lowStock(tipMedicine.id))
                }
            }
        } message: {
            if let tipMedicine {
                Text(session.t(.refillTipBody, tipMedicine.name, daysLabel(tipMedicine, session: session)))
            } else {
                Text(session.t(.refillTipBodyGeneric))
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                Text(session.t(.tabRefill))
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(CheckMedTheme.ink)
                Text(session.t(.refillRootIntro))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            CooperLibraryImage(asset: "phil_heart", size: 108)
        }
    }

    private var segment: some View {
        HStack(spacing: 8) {
            chip("\(session.t(.refillFilterAll)) (\(medicines.count))", selected: filter == .all) { filter = .all }
            chip("\(session.t(.refillFilterLow)) (\(lowCount))", selected: filter == .low) { filter = .low }
            chip("\(session.t(.refillFilterEmpty)) (\(emptyCount))", selected: filter == .empty) { filter = .empty }
            Spacer(minLength: 0)
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.caption, design: .rounded).weight(.heavy))
                .foregroundStyle(selected ? Color.white : CheckMedTheme.muted)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(selected ? CheckMedTheme.navy : CheckMedTheme.surface, in: Capsule())
                .overlay(Capsule().stroke(CheckMedTheme.hairline, lineWidth: selected ? 0 : 1.25))
        }
        .buttonStyle(.plain)
    }

    private func stockCard(_ med: CheckMedStore.MedicineSummary) -> some View {
        let band = stockBand(med)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                MedicationLibraryImage(form: med.form, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(med.name)
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.ink)
                    Text(formTitle(med.form, session: session))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(CheckMedTheme.muted)
                    if let qty = quantityLabel(med, session: session) {
                        Text(qty)
                            .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    } else {
                        Text(session.t(.refillStockPercent, Int(med.stockPercent.rounded())))
                            .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CheckMedTheme.muted)
                    .padding(.top, 8)
            }
            stockBar(percent: med.stockPercent, band: band)
            HStack {
                if med.refillDataComplete {
                    Text(estimatedDaysPhrase(med, session: session))
                } else {
                    Text(session.t(.refillIncomplete))
                }
                Spacer()
                if band == .low {
                    Text(session.t(.refillLow))
                        .foregroundStyle(CheckMedTheme.primaryShadow)
                } else if band == .empty {
                    Text(session.t(.refillEmptyPreset))
                        .foregroundStyle(CheckMedTheme.danger)
                }
            }
            .font(.system(.caption, design: .rounded).weight(.bold))
            .foregroundStyle(CheckMedTheme.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill(band))
        .clipShape(RoundedRectangle(cornerRadius: RefillChrome.cardRadius, style: .continuous))
        .shadow(color: CheckMedTheme.navy.opacity(0.05), radius: 10, y: 4)
    }

    private func cardFill(_ band: StockBand) -> Color {
        switch band {
        case .healthy: CheckMedTheme.mintWash.opacity(0.55)
        case .low: CheckMedTheme.belly.opacity(0.7)
        case .empty: CheckMedTheme.danger.opacity(0.08)
        case .unknown: CheckMedTheme.surface
        }
    }

    private var superCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(session.t(.refillSuperHeadline))
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 12) {
                Text(session.t(.refillSuperBody))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                CooperLibraryImage(asset: "phil_wink", size: 56)
            }
            CheckMedButton(title: session.t(.treatmentsTrySuper), style: .secondary) {
                entitlements.presentPaywall()
            }
        }
        .padding(16)
        .padding(.bottom, 8)
        .background(CheckMedTheme.blueWash.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: RefillChrome.cardRadius, style: .continuous))
    }

    private func presentTipIfNeeded() {
        let comps = session.foundationCalendar.dateComponents([.year, .month, .day], from: Date())
        let key = "checkmed.refillTip.\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let urgent = medicines
            .filter { $0.refillRemindEnabled && (stockBand($0) == .low || stockBand($0) == .empty) }
            .sorted { ($0.daysLeft ?? 999) < ($1.daysLeft ?? 999) }
            .first
        guard let urgent else { return }
        UserDefaults.standard.set(true, forKey: key)
        tipMedicine = urgent
        showTip = true
    }
}

struct MedicationStockDetailScreen: View {
    var go: (AppRoute) -> Void
    var medicineId: UUID
    @Environment(CheckMedStore.self) private var treatments
    @Environment(SessionStore.self) private var session
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(TodayPathStore.self) private var path

    private var medicine: CheckMedStore.MedicineSummary? { lookupMedicine(id: medicineId, treatments: treatments) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                if let medicine {
                    header(medicine)
                    currentStock(medicine)
                    if medicine.refillDataComplete {
                        fact(session.t(.refillDurationTitle), estimatedDaysPhrase(medicine, session: session))
                        if let consumption = consumptionLabel(medicine) {
                            fact(session.t(.refillConsumptionTitle), consumption)
                        }
                        if let next = nextRefillEstimate(medicine) {
                            fact(session.t(.refillNextEstimate), next)
                        }
                    } else {
                        fact(session.t(.refillDurationTitle), session.t(.refillDurationUnknown))
                    }
                    reminderRow(medicine)
                    pharmacyRow(medicine)
                    if !medicine.doctorNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        fact(session.t(.treatmentsNotesOptional), medicine.doctorNotes)
                    }
                    if let last = medicine.lastRefillAt {
                        fact(session.t(.reportLastRefill, refillDate(last, locale: session.locale.foundationLocale)), "")
                    }
                    if RefillPhotoStore.load(medicineId: medicine.id) != nil {
                        fact(session.t(.refillAddPhoto), session.t(.refillPhotoHint))
                    }
                } else {
                    Text(session.t(.todayNothing))
                        .font(.system(.body, design: .rounded).weight(.bold))
                }
                Text(session.t(.refillDisclaimer))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.safety)
            }
            .padding(16)
        }
        .background(CheckMedTheme.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let medicine {
                RefillChrome.pinnedFooter {
                    HStack(spacing: 8) {
                        CheckMedButton(title: session.t(.refillUpdate), style: .secondary) {
                            go(.updateStock(medicine.id))
                        }
                        CheckMedButton(title: session.t(.refillMarkFull), style: .ghost) {
                            treatments.updateMedicineStock(id: medicine.id, markRefilled: true)
                            ReminderScheduler.shared.reschedule()
                            path.reload()
                        }
                    }
                }
            }
        }
        .navigationTitle(session.t(.refillDetailTitle))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func header(_ med: CheckMedStore.MedicineSummary) -> some View {
        HStack(spacing: 14) {
            MedicationLibraryImage(form: med.form, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(med.name)
                    .font(.system(.title3, design: .rounded).weight(.black))
                Text(formTitle(med.form, session: session))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)
            }
            Spacer()
            Button(session.t(.refillUpdate)) { go(.updateStock(med.id)) }
                .font(.system(.caption, design: .rounded).weight(.heavy))
                .foregroundStyle(CheckMedTheme.primaryShadow)
        }
    }

    private func currentStock(_ med: CheckMedStore.MedicineSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.t(.refillCurrentStock))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
            Text(quantityLabel(med, session: session) ?? session.t(.refillStockPercent, Int(med.stockPercent.rounded())))
                .font(.system(.title2, design: .rounded).weight(.black))
            stockBar(percent: med.stockPercent, band: stockBand(med))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: RefillChrome.cardRadius, style: .continuous))
    }

    private func reminderRow(_ med: CheckMedStore.MedicineSummary) -> some View {
        Button { go(.refillReminders(med.id)) } label: {
            HStack {
                Image(systemName: "bell.fill")
                    .foregroundStyle(CheckMedTheme.flowDot)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.t(.refillRemindersTitle))
                        .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    Text(med.refillRemindEnabled ? session.t(.refillRemindOn) : session.t(.refillRemindOff))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(CheckMedTheme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CheckMedTheme.muted)
            }
            .padding(14)
            .background(CheckMedTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func pharmacyRow(_ med: CheckMedStore.MedicineSummary) -> some View {
        Button { go(.pharmacySearch(query: med.name)) } label: {
            HStack {
                Image(systemName: "cross.case.fill")
                    .foregroundStyle(CheckMedTheme.primaryShadow)
                Text(session.t(.pharmacyTitle))
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                Spacer()
                if !entitlements.canSearchPharmacies {
                    Text(session.t(.paywallSuper))
                        .font(.system(.caption2, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.superAccent)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CheckMedTheme.muted)
            }
            .padding(14)
            .background(CheckMedTheme.mintWash.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func consumptionLabel(_ med: CheckMedStore.MedicineSummary) -> String? {
        guard med.quantityPerDose > 0, med.timesPerDay > 0 else { return nil }
        let daily = med.quantityPerDose * Double(med.timesPerDay)
        return session.t(.refillConsumptionValue, formatAmount(daily), localizedUnit(med.doseUnit, amount: daily, session: session))
    }

    private func nextRefillEstimate(_ med: CheckMedStore.MedicineSummary) -> String? {
        guard let days = med.daysLeft, days.isFinite, days >= 0,
              let date = session.foundationCalendar.date(byAdding: .day, value: max(0, Int(days.rounded(.down))), to: Date())
        else { return nil }
        return session.t(.refillNextEstimateIn, refillDate(date, locale: session.locale.foundationLocale), daysLabel(med, session: session))
    }

    private func fact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
            if !value.isEmpty {
                Text(value)
                    .font(.system(.body, design: .rounded).weight(.heavy))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct UpdateStockScreen: View {
    var go: (AppRoute) -> Void
    var medicineId: UUID
    @Environment(CheckMedStore.self) private var treatments
    @Environment(SessionStore.self) private var session
    @Environment(TodayPathStore.self) private var path

    @State private var draftRemaining: Double = 0
    @State private var draftPercent: Double = 0
    @State private var packageAmount: String = ""
    @State private var packageUnit: MedicineUnit = .tablet
    @State private var quantityPerDose: String = ""
    @State private var doseUnit: MedicineUnit = .tablet
    @State private var form: MedicineForm = .other
    @State private var note: String = ""
    @State private var didLoad = false
    @State private var photoItem: PhotosPickerItem?
    @State private var photoPreview: UIImage?

    private var medicine: CheckMedStore.MedicineSummary? { lookupMedicine(id: medicineId, treatments: treatments) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                if let medicine {
                    HStack {
                        Spacer()
                        CooperLibraryImage(asset: "phil_wink", size: 100)
                        Spacer()
                    }
                    Text(session.t(.refillAddStockHeadline))
                        .font(.system(.title3, design: .rounded).weight(.black))
                        .frame(maxWidth: .infinity)
                    Text(session.t(.refillAddStockSupport, medicine.name))
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(CheckMedTheme.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    stepper
                    if canUseUnits {
                        quickAdds
                    }
                    totalCard
                    if let days = previewDays {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(CheckMedTheme.primaryShadow)
                            Text(days < 1 ? session.t(.refillEstimatedDays, session.t(.refillLessThanDay)) : (Int(days.rounded(.down)) == 1 ? session.t(.refillEstimatedDaysOne) : session.t(.refillEstimatedDays, "\(Int(days.rounded(.down)))")))
                                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(CheckMedTheme.mintWash)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        Text(session.t(.refillDurationUnknown))
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(CheckMedTheme.muted)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(session.t(.treatmentsNotesOptional))
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(CheckMedTheme.muted)
                        TextField(session.t(.treatmentsNotesOptional), text: $note, axis: .vertical)
                            .lineLimit(2...4)
                            .padding(12)
                            .background(CheckMedTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    packageFields
                } else {
                    Text(session.t(.todayNothing))
                }
            }
            .padding(16)
        }
        .background(CheckMedTheme.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let medicine {
                RefillChrome.pinnedFooter {
                    CheckMedButton(title: session.t(.refillSaveStock)) { save(medicine) }
                }
            }
        }
        .navigationTitle(session.t(.refillUpdate))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadIfNeeded() }
        .onChange(of: photoItem) { _, item in
            guard let item, let medicine else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        photoPreview = image
                        RefillPhotoStore.save(image, medicineId: medicine.id)
                    }
                }
            }
        }
    }

    private var canUseUnits: Bool {
        (Double(packageAmount.replacingOccurrences(of: ",", with: ".")) ?? 0) > 0
    }

    private var packAmountValue: Double {
        Double(packageAmount.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var stepper: some View {
        HStack(spacing: 18) {
            Button {
                if canUseUnits {
                    draftRemaining = max(0, draftRemaining - 1)
                } else {
                    draftPercent = max(0, draftPercent - 5)
                }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 20, weight: .bold))
                    .frame(width: 52, height: 52)
                    .background(CheckMedTheme.blueWash, in: Circle())
            }
            .buttonStyle(.plain)
            VStack(spacing: 4) {
                Text(canUseUnits ? formatAmount(draftRemaining) : "\(Int(draftPercent.rounded()))%")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                if canUseUnits {
                    Text(localizedUnit(packageUnit, amount: draftRemaining, session: session))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.muted)
                }
            }
            .frame(minWidth: 120)
            Button {
                if canUseUnits {
                    draftRemaining = min(packAmountValue, draftRemaining + 1)
                } else {
                    draftPercent = min(100, draftPercent + 5)
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .frame(width: 52, height: 52)
                    .background(CheckMedTheme.blueWash, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    private var quickAdds: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.t(.refillQuickAdd))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
            HStack(spacing: 8) {
                ForEach([7, 14, 30, 60], id: \.self) { value in
                    Button {
                        draftRemaining = min(packAmountValue, draftRemaining + Double(value))
                    } label: {
                        Text(session.t(.refillQuickAddUnits, value, localizedUnit(packageUnit, amount: Double(value), session: session)))
                            .font(.system(.caption, design: .rounded).weight(.heavy))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(CheckMedTheme.surface, in: Capsule())
                            .overlay(Capsule().stroke(CheckMedTheme.hairline, lineWidth: 1.25))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var totalCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.t(.refillNewTotal))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
            if canUseUnits {
                Text("\(formatAmount(min(packAmountValue, draftRemaining))) \(localizedUnit(packageUnit, amount: min(packAmountValue, draftRemaining), session: session))")
                    .font(.system(.title3, design: .rounded).weight(.black))
            } else {
                Text(session.t(.refillStockPercent, Int(draftPercent.rounded())))
                    .font(.system(.title3, design: .rounded).weight(.black))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var previewDays: Double? {
        let amount = packAmountValue
        let dose = Double(quantityPerDose.replacingOccurrences(of: ",", with: ".")) ?? 0
        guard let medicine, MedicineUnits.hasCompleteRefillData(
            packageAmount: amount,
            quantityPerDose: dose,
            packageUnit: packageUnit,
            doseUnit: doseUnit
        ) else { return nil }
        let percent = canUseUnits && amount > 0
            ? min(100, max(0, (min(amount, draftRemaining) / amount) * 100))
            : draftPercent
        return MedicineUnits.daysLeft(
            packageAmount: amount,
            packageUnit: packageUnit,
            stockPercent: percent,
            quantityPerDose: dose,
            doseUnit: doseUnit,
            timesPerDay: medicine.timesPerDay
        )
    }

    private var packageFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(session.t(.refillHowFull))
                .font(.system(.headline, design: .rounded).weight(.heavy))
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(session.t(.refillAddPhoto), systemImage: "camera.fill")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
            }
            if let photoPreview {
                Image(uiImage: photoPreview)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            labeledField(session.t(.refillPackageAmount), text: $packageAmount)
            Picker(session.t(.refillPackageUnit), selection: $packageUnit) {
                ForEach(MedicineUnit.allCases.filter { $0 != .other }) { unit in
                    Text(localizedUnit(unit, amount: 1, session: session)).tag(unit)
                }
            }
            labeledField(session.t(.refillDoseAmount), text: $quantityPerDose)
            Picker(session.t(.refillDoseUnit), selection: $doseUnit) {
                ForEach(MedicineUnit.allCases.filter { $0 != .other }) { unit in
                    Text(localizedUnit(unit, amount: 1, session: session)).tag(unit)
                }
            }
            Text(session.t(.refillDropsNote))
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(CheckMedTheme.safety)
        }
    }

    private func labeledField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
            TextField(title, text: text)
                .keyboardType(.decimalPad)
                .padding(12)
                .background(CheckMedTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func loadIfNeeded() {
        guard !didLoad, let medicine else { return }
        didLoad = true
        draftPercent = medicine.stockPercent
        if let remaining = remainingAmount(medicine) {
            draftRemaining = remaining.amount
        } else {
            draftRemaining = medicine.packageAmount * medicine.stockPercent / 100.0
        }
        packageAmount = medicine.packageAmount > 0 ? String(format: "%g", medicine.packageAmount) : ""
        packageUnit = medicine.packageUnit
        quantityPerDose = String(format: "%g", medicine.quantityPerDose)
        doseUnit = medicine.doseUnit
        form = medicine.form
        note = medicine.doctorNotes
        photoPreview = RefillPhotoStore.load(medicineId: medicine.id)
    }

    private func save(_ medicine: CheckMedStore.MedicineSummary) {
        let amount = packAmountValue > 0 ? packAmountValue : medicine.packageAmount
        let dose = Double(quantityPerDose.replacingOccurrences(of: ",", with: ".")) ?? medicine.quantityPerDose
        let percent: Double
        if amount > 0, canUseUnits {
            percent = min(100, max(0, (min(amount, draftRemaining) / amount) * 100))
        } else {
            percent = min(100, max(0, draftPercent))
        }
        treatments.updateMedicineStock(
            id: medicine.id,
            stockPercent: percent,
            packageAmount: amount,
            packageUnit: packageUnit,
            quantityPerDose: dose,
            doseUnit: doseUnit,
            form: form,
            doctorNotes: note
        )
        ReminderScheduler.shared.reschedule()
        path.reload()
        go(.medicationStock(medicine.id))
    }
}

struct RefillRemindersScreen: View {
    var go: (AppRoute) -> Void
    var medicineId: UUID
    @Environment(CheckMedStore.self) private var treatments
    @Environment(SessionStore.self) private var session
    @Environment(TodayPathStore.self) private var path

    @State private var enabled = true
    @State private var threshold = ReminderPreferences.lowStockDaysThreshold
    @State private var didLoad = false

    private var medicine: CheckMedStore.MedicineSummary? { lookupMedicine(id: medicineId, treatments: treatments) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(session.t(.refillRemindersNeverMiss))
                            .font(.system(.title3, design: .rounded).weight(.black))
                        Text(session.t(.refillRemindersSupport))
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(CheckMedTheme.muted)
                    }
                    Spacer()
                    CooperLibraryImage(asset: "phil_alert", size: 88)
                }
                if let medicine {
                    Toggle(isOn: Binding(
                        get: { enabled },
                        set: { newValue in
                            enabled = newValue
                            treatments.updateMedicineStock(id: medicine.id, refillRemindEnabled: newValue)
                            ReminderScheduler.shared.reschedule()
                            path.reload()
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.t(.refillRemindersTitle))
                                .font(.system(.headline, design: .rounded).weight(.heavy))
                            Text(session.t(.refillRemindToggleMedicine))
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .foregroundStyle(CheckMedTheme.muted)
                        }
                    }
                    .tint(CheckMedTheme.primaryShadow)

                    Text(session.t(.refillWhenToAlert))
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                        .padding(.top, 8)
                    Text(session.t(.refillThresholdGlobal))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(CheckMedTheme.muted)
                    VStack(spacing: 8) {
                        ForEach([1, 2, 3, 5, 7], id: \.self) { days in
                            Button {
                                threshold = days
                                ReminderPreferences.lowStockDaysThreshold = days
                                ReminderScheduler.shared.reschedule()
                            } label: {
                                HStack {
                                    Text(days == 1 ? session.t(.refillDaysBeforeOne) : session.t(.refillDaysBefore, days))
                                        .font(.system(.body, design: .rounded).weight(.heavy))
                                    Spacer()
                                    Image(systemName: threshold == days ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(threshold == days ? CheckMedTheme.primaryShadow : CheckMedTheme.muted)
                                }
                                .padding(14)
                                .background(CheckMedTheme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text(session.t(.refillMorningAlert))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(CheckMedTheme.muted)
                } else {
                    Text(session.t(.todayNothing))
                }
            }
            .padding(16)
        }
        .background(CheckMedTheme.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            RefillChrome.pinnedFooter {
                CheckMedButton(title: session.t(.treatmentsOpenNotificationPrefs), style: .secondary) {
                    go(.notificationPrefs)
                }
            }
        }
        .navigationTitle(session.t(.refillRemindersTitle))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !didLoad, let medicine else { return }
            didLoad = true
            enabled = medicine.refillRemindEnabled
            threshold = ReminderPreferences.lowStockDaysThreshold
        }
    }
}

struct LowStockScreen: View {
    var go: (AppRoute) -> Void
    var medicineId: UUID
    @Environment(CheckMedStore.self) private var treatments
    @Environment(SessionStore.self) private var session
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(TodayPathStore.self) private var path

    private var medicine: CheckMedStore.MedicineSummary? { lookupMedicine(id: medicineId, treatments: treatments) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Spacer()
                    CooperLibraryImage(asset: "phil_alert", size: 120)
                    Spacer()
                }
                if let medicine {
                    Text(session.t(.refillLowHeadline))
                        .font(.system(.title2, design: .rounded).weight(.black))
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                    Text(session.t(.refillLowSupport, medicine.name))
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(CheckMedTheme.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    HStack(spacing: 12) {
                        MedicationLibraryImage(form: medicine.form, size: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(medicine.name)
                                .font(.system(.headline, design: .rounded).weight(.heavy))
                            Text(formTitle(medicine.form, session: session))
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .foregroundStyle(CheckMedTheme.muted)
                            Text(quantityLabel(medicine, session: session) ?? session.t(.refillStockPercent, Int(medicine.stockPercent.rounded())))
                                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                        }
                        Spacer()
                        if medicine.refillDataComplete {
                            Text(daysLeftPhrase(medicine, session: session))
                                .font(.system(.caption2, design: .rounded).weight(.heavy))
                                .foregroundStyle(CheckMedTheme.danger)
                        }
                    }
                    .padding(14)
                    .background(CheckMedTheme.danger.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: RefillChrome.cardRadius, style: .continuous))

                    Text(session.t(.refillWhatNext))
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                    CheckMedButton(title: session.t(.refillMarkFull)) {
                        treatments.updateMedicineStock(id: medicine.id, markRefilled: true)
                        ReminderScheduler.shared.reschedule()
                        path.reload()
                        go(.medicationStock(medicine.id))
                    }
                    CheckMedButton(title: session.t(.refillUpdate), style: .secondary) {
                        go(.updateStock(medicine.id))
                    }
                    CheckMedButton(title: session.t(.pharmacyTitle), style: .secondary) {
                        go(.pharmacySearch(query: medicine.name))
                    }
                    HStack(alignment: .top, spacing: 10) {
                        CooperLibraryImage(asset: "phil_wink", size: 44)
                        Text(session.t(.refillLowTip))
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(CheckMedTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .padding(.trailing, 56)
                    .background(CheckMedTheme.belly.opacity(0.65))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    if !entitlements.canSearchPharmacies {
                        Text(session.t(.pharmacyPremiumOnly))
                            .font(.system(.caption2, design: .rounded).weight(.bold))
                            .foregroundStyle(CheckMedTheme.superAccent)
                    }
                } else {
                    Text(session.t(.todayNothing))
                }
            }
            .padding(16)
            .padding(.bottom, RefillChrome.fabClearance)
        }
        .background(CheckMedTheme.background)
        .navigationTitle(session.t(.refillLowHeadline))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private func stockBar(percent: Double, band: StockBand) -> some View {
    GeometryReader { geo in
        ZStack(alignment: .leading) {
            Capsule().fill(CheckMedTheme.hairline.opacity(0.35))
            Capsule()
                .fill(barColor(band))
                .frame(width: max(8, geo.size.width * min(1, max(0, percent / 100))))
        }
    }
    .frame(height: 8)
}

private func barColor(_ band: StockBand) -> Color {
    switch band {
    case .healthy: CheckMedTheme.primary
    case .low: CheckMedTheme.primaryShadow
    case .empty: CheckMedTheme.danger
    case .unknown: CheckMedTheme.muted
    }
}
