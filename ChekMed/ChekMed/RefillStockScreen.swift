import PhotosUI
import SwiftUI
import UIKit

struct RefillStockScreen: View {
    @Environment(SessionStore.self) private var session
    @Environment(CheckMedStore.self) private var treatments
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(TodayPathStore.self) private var path
    var go: (AppRoute) -> Void

    @State private var showTip = false
    @State private var tipMedicine: CheckMedStore.MedicineSummary?
    @State private var editing: CheckMedStore.MedicineSummary?
    @State private var tipShownKey = ""

    private var medicines: [CheckMedStore.MedicineSummary] { treatments.medicineSummaries() }

    private var todayStamp: String {
        let comps = session.foundationCalendar.dateComponents([.year, .month, .day], from: Date())
        return "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                header
                pharmaciesNearbyCard
                Text(session.t(.refillDisclaimer))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.safety)
                if medicines.isEmpty {
                    Text(session.t(.refillEmpty))
                        .font(.system(.body, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.muted)
                    CheckMedButton(title: session.t(.homeScan)) { go(.addPrescription) }
                } else {
                    ForEach(medicines) { med in
                        refillCard(med)
                    }
                }
                SafetyCaption()
                    .frame(maxWidth: .infinity)
            }
            .padding(16)
        }
        .background(CheckMedTheme.background)
        .navigationTitle(session.t(.refillHeadline))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { presentTipIfNeeded() }
        .sheet(item: $editing) { med in
            RefillEditSheet(medicine: med) {
                editing = nil
                path.reload()
            }
        }
        .alert(
            session.t(.refillTipTitle),
            isPresented: $showTip
        ) {
            Button(session.t(.ok), role: .cancel) { showTip = false }
            if tipMedicine != nil {
                Button(session.t(.refillTipOpen)) {
                    showTip = false
                    if let tipMedicine { editing = tipMedicine }
                }
            }
        } message: {
            if let tipMedicine {
                Text(session.t(.refillTipBody, tipMedicine.name, daysLabel(tipMedicine)))
            } else {
                Text(session.t(.refillTipBodyGeneric))
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "battery.75percent")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(CheckMedTheme.onPrimary)
                .frame(width: 36, height: 36)
                .background(CheckMedTheme.primary, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(session.t(.refillHeadline))
                    .font(.system(.title, design: .rounded).weight(.black))
                Text(session.t(.refillSubhead))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)
            }
            Spacer()
        }
    }

    private var pharmaciesNearbyCard: some View {
        Button {
            go(.pharmacySearch(query: medicines.first?.name ?? ""))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "cross.case.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(CheckMedTheme.onPrimary)
                    .frame(width: 40, height: 40)
                    .background(CheckMedTheme.primaryShadow, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.t(.pharmacyTitle))
                        .font(.system(.subheadline, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.ink)
                    Text(session.t(.pharmacyProgressHint))
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(CheckMedTheme.muted)
                }
                Spacer(minLength: 4)
                if !entitlements.canSearchPharmacies {
                    Text(session.t(.paywallSuper))
                        .font(.system(.caption2, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.superAccent)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CheckMedTheme.muted)
            }
            .padding(14)
            .background(CheckMedTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(CheckMedTheme.hairline, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(session.t(.pharmacyTitle))
    }

    private func refillCard(_ med: CheckMedStore.MedicineSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: med.form.systemImage)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(CheckMedTheme.flowDot)
                    .frame(width: 52, height: 52)
                    .background(CheckMedTheme.philFlowCanvas, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(med.name)
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                    if med.refillDataComplete {
                        Text(session.t(.refillDaysLeftFormat, daysLabel(med)))
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(CheckMedTheme.muted)
                        if let days = med.daysLeft, days <= Double(ReminderPreferences.lowStockDaysThreshold) {
                            Text(session.t(.refillRunningLow))
                                .font(.system(.caption, design: .rounded).weight(.heavy))
                                .foregroundStyle(CheckMedTheme.primaryShadow)
                            if let remaining = remainingLabel(med) {
                                Text(session.t(.refillApproxRemaining, remaining))
                                    .font(.system(.caption2, design: .rounded).weight(.bold))
                                    .foregroundStyle(CheckMedTheme.muted)
                            }
                        }
                    } else {
                        Text(session.t(.refillIncomplete))
                            .font(.system(.caption, design: .rounded).weight(.heavy))
                            .foregroundStyle(CheckMedTheme.safety)
                    }
                }
                Spacer()
                StockBatteryView(percent: med.stockPercent)
                    .frame(width: 36, height: 56)
            }

            if med.refillDataComplete {
                Text(session.t(.refillStockPercent, Int(med.stockPercent.rounded())))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.ink)
            }

            HStack(spacing: 8) {
                CheckMedButton(title: session.t(.refillUpdate), style: .secondary) {
                    editing = med
                }
                CheckMedButton(title: session.t(.refillMarkFull), style: .ghost) {
                    treatments.updateMedicineStock(id: med.id, markRefilled: true)
                    path.reload()
                }
            }

            Toggle(isOn: Binding(
                get: { med.refillRemindEnabled },
                set: { treatments.updateMedicineStock(id: med.id, refillRemindEnabled: $0) }
            )) {
                Text(session.t(.refillRemindToggle))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
            }
            .tint(CheckMedTheme.primaryShadow)

            Button {
                go(.pharmacySearch(query: med.name))
            } label: {
                HStack {
                    Image(systemName: "cross.case.fill")
                    Text(session.t(.refillFindPharmacy))
                        .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    Spacer()
                    if !entitlements.canSearchPharmacies {
                        Text(session.t(.paywallSuper))
                            .font(.system(.caption2, design: .rounded).weight(.heavy))
                            .foregroundStyle(CheckMedTheme.superAccent)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(CheckMedTheme.ink)
                .padding(12)
                .background(CheckMedTheme.mintWash, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(CheckMedTheme.hairline, lineWidth: 1.5)
        )
    }

    private func remainingLabel(_ med: CheckMedStore.MedicineSummary) -> String? {
        guard med.refillDataComplete,
              let remaining = MedicineUnits.remainingDisplayAmount(
                packageAmount: med.packageAmount,
                packageUnit: med.packageUnit,
                stockPercent: med.stockPercent
              )
        else { return nil }
        let amount = remaining.amount == remaining.amount.rounded()
            ? String(Int(remaining.amount.rounded()))
            : String(format: "%.1f", remaining.amount)
        return "\(amount) \(remaining.unit.rawValue)"
    }

    private func daysLabel(_ med: CheckMedStore.MedicineSummary) -> String {
        guard let days = med.daysLeft, days.isFinite else { return "—" }
        if days < 1 { return session.t(.refillLessThanDay) }
        return "\(Int(days.rounded(.down)))"
    }

    private func presentTipIfNeeded() {
        let key = "checkmed.refillTip.\(todayStamp)"
        tipShownKey = key
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        tipMedicine = treatments.medicineMostUrgentForRefill()
        guard tipMedicine != nil else { return }
        UserDefaults.standard.set(true, forKey: key)
        showTip = true
    }
}

struct StockBatteryView: View {
    var percent: Double

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let w = geo.size.width
            let fill = min(100, max(0, percent)) / 100
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(CheckMedTheme.ink.opacity(0.35), lineWidth: 2)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(CheckMedTheme.ink.opacity(0.2))
                    .frame(width: w * 0.45, height: 5)
                    .offset(y: -h / 2 - 2)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(batteryColor)
                    .frame(height: max(4, (h - 8) * fill))
                    .padding(4)
                    .animation(.easeInOut(duration: 0.45), value: percent)
            }
        }
    }

    private var batteryColor: Color {
        if percent > 55 { return Color(hex: 0x5FA86B) }
        if percent > 25 { return CheckMedTheme.primary }
        return CheckMedTheme.danger
    }
}

struct RefillEditSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(CheckMedStore.self) private var treatments
    let medicine: CheckMedStore.MedicineSummary
    var onDone: () -> Void

    @State private var stock: Double
    @State private var packageAmount: String
    @State private var packageUnit: MedicineUnit
    @State private var quantityPerDose: String
    @State private var doseUnit: MedicineUnit
    @State private var form: MedicineForm
    @State private var photoItem: PhotosPickerItem?
    @State private var photoPreview: UIImage?

    init(medicine: CheckMedStore.MedicineSummary, onDone: @escaping () -> Void) {
        self.medicine = medicine
        self.onDone = onDone
        _stock = State(initialValue: medicine.stockPercent)
        _packageAmount = State(initialValue: medicine.packageAmount > 0 ? String(format: "%g", medicine.packageAmount) : "")
        _packageUnit = State(initialValue: medicine.packageUnit)
        _quantityPerDose = State(initialValue: String(format: "%g", medicine.quantityPerDose))
        _doseUnit = State(initialValue: medicine.doseUnit)
        _form = State(initialValue: medicine.form)
        _photoPreview = State(initialValue: RefillPhotoStore.load(medicineId: medicine.id))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(medicine.name)
                        .font(.system(.title3, design: .rounded).weight(.heavy))
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(session.t(.refillAddPhoto), systemImage: "camera.fill")
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                    }
                    if let preview = photoPreview {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    Text(session.t(.refillPhotoHint))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(CheckMedTheme.muted)

                    Text(session.t(.refillHowFull))
                        .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    HStack {
                        ForEach([100.0, 75, 50, 25, 5], id: \.self) { value in
                            Button {
                                withAnimation { stock = value }
                            } label: {
                                Text(presetLabel(value))
                                    .font(.system(.caption2, design: .rounded).weight(.heavy))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(stock == value ? CheckMedTheme.primary : CheckMedTheme.surface)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Slider(value: $stock, in: 0...100, step: 1)
                        .tint(CheckMedTheme.primaryShadow)
                    Text("\(Int(stock))%")
                        .font(.system(.caption, design: .rounded).weight(.bold))

                    StockBatteryView(percent: stock)
                        .frame(width: 44, height: 72)
                        .frame(maxWidth: .infinity)

                    labeledField(session.t(.refillPackageAmount), text: $packageAmount)
                    Picker(session.t(.refillPackageUnit), selection: $packageUnit) {
                        ForEach(MedicineUnit.allCases.filter { $0 != .other }) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                    labeledField(session.t(.refillDoseAmount), text: $quantityPerDose)
                    Picker(session.t(.refillDoseUnit), selection: $doseUnit) {
                        ForEach(MedicineUnit.allCases.filter { $0 != .other }) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                    Picker(session.t(.refillForm), selection: $form) {
                        ForEach(MedicineForm.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }

                    Text(session.t(.refillDropsNote))
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(CheckMedTheme.safety)

                    if let days = previewDays {
                        Text(session.t(.refillDaysLeftFormat, days < 1 ? session.t(.refillLessThanDay) : "\(Int(days.rounded(.down)))"))
                            .font(.system(.body, design: .rounded).weight(.heavy))
                    } else {
                        Text(session.t(.refillIncomplete))
                            .font(.system(.caption, design: .rounded).weight(.heavy))
                            .foregroundStyle(CheckMedTheme.safety)
                    }

                    CheckMedButton(title: session.t(.feelingSave)) { save() }
                    CheckMedButton(title: session.t(.cancel), style: .ghost, action: onDone)
                }
                .padding(20)
            }
            .background(CheckMedTheme.background)
            .navigationTitle(session.t(.refillUpdate))
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
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
    }

    private var previewDays: Double? {
        let amount = Double(packageAmount.replacingOccurrences(of: ",", with: ".")) ?? 0
        let dose = Double(quantityPerDose.replacingOccurrences(of: ",", with: ".")) ?? 0
        guard MedicineUnits.hasCompleteRefillData(
            packageAmount: amount,
            quantityPerDose: dose,
            packageUnit: packageUnit,
            doseUnit: doseUnit
        ) else { return nil }
        return MedicineUnits.daysLeft(
            packageAmount: amount,
            packageUnit: packageUnit,
            stockPercent: stock,
            quantityPerDose: dose,
            doseUnit: doseUnit,
            timesPerDay: medicine.timesPerDay
        )
    }

    private func presetLabel(_ value: Double) -> String {
        switch value {
        case 100: return session.t(.refillFull)
        case 75: return session.t(.refillAlmostFull)
        case 50: return session.t(.refillHalf)
        case 25: return session.t(.refillLow)
        default: return session.t(.refillEmptyPreset)
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

    private func save() {
        let amount = Double(packageAmount.replacingOccurrences(of: ",", with: ".")) ?? medicine.packageAmount
        let dose = Double(quantityPerDose.replacingOccurrences(of: ",", with: ".")) ?? medicine.quantityPerDose
        treatments.updateMedicineStock(
            id: medicine.id,
            stockPercent: stock,
            packageAmount: amount,
            packageUnit: packageUnit,
            quantityPerDose: dose,
            doseUnit: doseUnit,
            form: form
        )
        ReminderScheduler.shared.reschedule()
        onDone()
    }
}

enum RefillPhotoStore {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("refill-photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func url(for medicineId: UUID) -> URL {
        directory.appendingPathComponent("\(medicineId.uuidString).jpg")
    }

    static func save(_ image: UIImage, medicineId: UUID) {
        guard let data = image.jpegData(compressionQuality: 0.82) else { return }
        try? data.write(to: url(for: medicineId), options: .atomic)
    }

    static func load(medicineId: UUID) -> UIImage? {
        let path = url(for: medicineId)
        guard FileManager.default.fileExists(atPath: path.path),
              let data = try? Data(contentsOf: path)
        else { return nil }
        return UIImage(data: data)
    }
}
