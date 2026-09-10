import Foundation

enum MedicineForm: String, CaseIterable, Identifiable, Sendable {
    case tablet, capsule, syrup, drops, powder, other

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .tablet: "pills.fill"
        case .capsule: "capsule.fill"
        case .syrup: "cross.vial.fill"
        case .drops: "drop.fill"
        case .powder: "leaf.fill"
        case .other: "cross.case.fill"
        }
    }

    static func infer(from doseLabel: String, medicineName: String = "") -> MedicineForm {
        let raw = "\(doseLabel) \(medicineName)".lowercased()
        if raw.contains("syrup") || raw.contains("xarope") || raw.contains("jarabe") || raw.contains("sirop")
            || raw.contains("ml") || raw.contains("colher") || raw.contains("cucharad") || raw.contains("spoon")
            || raw.contains("tsp") || raw.contains("tbsp") {
            return .syrup
        }
        if raw.contains("gota") || raw.contains("drop") || raw.contains("gtt") {
            return .drops
        }
        if raw.contains("pó") || raw.contains("po ") || raw.contains("powder") || raw.contains("polvo") {
            return .powder
        }
        if raw.contains("cápsula") || raw.contains("capsula") || raw.contains("capsule") || raw.contains("gélule") {
            return .capsule
        }
        if raw.contains("comprimido") || raw.contains("tablet") || raw.contains("comp.") {
            return .tablet
        }
        return .other
    }
}

enum MedicineUnit: String, CaseIterable, Identifiable, Sendable {
    case tablet, capsule, ml, g, mg, mcg, drop, tsp, tbsp, oz, other

    var id: String { rawValue }

    /// Convert amount into a canonical base for comparison within the same family.
    /// Volume family → mL. Mass family → mg. Count family → each (1:1).
    func toBase(_ amount: Double) -> (value: Double, family: UnitFamily)? {
        switch self {
        case .ml: return (amount, .volume)
        case .drop: return (amount / 20.0, .volume) // 20 drops = 1 mL
        case .tsp: return (amount * 5.0, .volume)
        case .tbsp: return (amount * 15.0, .volume)
        case .oz: return (amount * 30.0, .volume)
        case .g: return (amount * 1000.0, .mass)
        case .mg: return (amount, .mass)
        case .mcg: return (amount / 1000.0, .mass)
        case .tablet, .capsule: return (amount, .count)
        case .other: return (amount, .count)
        }
    }

    static func parse(_ text: String) -> MedicineUnit? {
        let lower = text.lowercased()
        if lower.contains("cápsula") || lower.contains("capsula") || lower.contains("capsule") || lower.contains("gélule") {
            return .capsule
        }
        if lower.contains("comprimido") || lower.contains("tablet") || lower.contains("pill") {
            return .tablet
        }
        if lower.contains("colher de sopa") || lower.contains("cucharada") || lower.contains("tbsp") || lower.contains("tablespoon") {
            return .tbsp
        }
        if lower.contains("colher") || lower.contains("cucharadita") || lower.contains("tsp") || lower.contains("teaspoon") {
            return .tsp
        }
        if lower.contains("gota") || lower.contains("drop") || lower.contains("gtt") {
            return .drop
        }
        if lower.contains("mcg") || lower.contains("µg") || lower.contains("ug") || lower.contains("microgram") {
            return .mcg
        }
        if lower.contains("mg") || lower.contains("miligram") {
            return .mg
        }
        if lower.contains("ml") || lower.contains("mililit") || lower.contains("cm3") || lower.contains("cm³") || lower.contains("cc") {
            return .ml
        }
        if lower.contains(" oz") || lower.hasPrefix("oz") || lower.contains("ounce") {
            return .oz
        }
        if lower.contains("gram") || lower.hasSuffix(" g") || lower == "g" || lower.contains("gramos") || lower.contains("gramas") {
            return .g
        }
        return nil
    }
}

enum UnitFamily: Sendable {
    case volume, mass, count
}

struct ParsedDose: Sendable {
    var quantity: Double
    var unit: MedicineUnit
}

enum MedicineUnits {
    /// 20 drops ≈ 1 mL for oral liquids (droppers vary).
    static let dropsPerMilliliter = 20.0

    static func parseDoseLabel(_ text: String) -> ParsedDose {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"(\d+(?:[.,]\d+)?)"#
        let number: Double = {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                  let range = Range(match.range(at: 1), in: trimmed)
            else { return 1 }
            return Double(trimmed[range].replacingOccurrences(of: ",", with: ".")) ?? 1
        }()
        let unit = MedicineUnit.parse(trimmed) ?? .tablet
        return ParsedDose(quantity: max(0.01, number), unit: unit)
    }

    static func parsePackage(amountText: String, unitHint: String) -> (amount: Double, unit: MedicineUnit) {
        let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let unit = MedicineUnit.parse(unitHint) ?? MedicineUnit.parse(amountText) ?? .tablet
        return (max(0, amount), unit)
    }

    /// Days of supply from package size × stock% and dose × times/day.
    static func daysLeft(
        packageAmount: Double,
        packageUnit: MedicineUnit,
        stockPercent: Double,
        quantityPerDose: Double,
        doseUnit: MedicineUnit,
        timesPerDay: Int
    ) -> Double? {
        guard timesPerDay > 0,
              packageAmount > 0,
              quantityPerDose > 0,
              let pack = packageUnit.toBase(packageAmount),
              let dose = doseUnit.toBase(quantityPerDose),
              pack.family == dose.family,
              dose.value > 0
        else { return nil }
        let remaining = pack.value * min(100, max(0, stockPercent)) / 100.0
        let daily = dose.value * Double(timesPerDay)
        guard daily > 0 else { return nil }
        return remaining / daily
    }

    static func remainingBase(
        packageAmount: Double,
        packageUnit: MedicineUnit,
        stockPercent: Double
    ) -> (value: Double, family: UnitFamily)? {
        guard let pack = packageUnit.toBase(packageAmount) else { return nil }
        return (pack.value * min(100, max(0, stockPercent)) / 100.0, pack.family)
    }

    /// New stock % after consuming one dose.
    static func stockPercentAfterDose(
        packageAmount: Double,
        packageUnit: MedicineUnit,
        stockPercent: Double,
        quantityPerDose: Double,
        doseUnit: MedicineUnit
    ) -> Double? {
        guard packageAmount > 0,
              let pack = packageUnit.toBase(packageAmount),
              let dose = doseUnit.toBase(quantityPerDose),
              pack.family == dose.family,
              pack.value > 0
        else { return nil }
        let remaining = pack.value * min(100, max(0, stockPercent)) / 100.0
        let next = max(0, remaining - dose.value)
        return (next / pack.value) * 100.0
    }
}
