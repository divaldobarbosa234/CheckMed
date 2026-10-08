import PhotosUI
import SwiftUI
import UIKit

struct RefillStockScreen: View {
    var go: (AppRoute) -> Void

    var body: some View {
        RefillRootScreen(go: go)
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
