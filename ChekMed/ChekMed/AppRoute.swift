import SwiftUI

/// Destinations for the principal-screen IA (06–40).
/// Launch (root flow, not stack routes): … → confirm → plan journey → alarms → notifications → trial → Phil → Home.
enum AppRoute: Hashable {
    case todayTreatment
    case upcoming
    case dailySummary
    case addPrescription
    case cameraScanner
    case scanning
    case extractionResults
    case verifyPrescription
    case prescriptionSaved
    case treatmentOverview
    case medicationList
    case medicationDetail(UUID)
    case howToTake
    case treatmentTimeline
    case editTreatment
    case nextDose
    case medicationAlarm
    case confirmMedication
    case doseCompleted
    case missedDose
    case reminderSettings
    case progressDashboard
    case badges
    case adherence
    case treatmentHistory
    case treatmentComplete
    case myMedicines
    case medicineHistory
    case notificationPrefs
    case settings
    case privacySettings
    case privacyPolicy
    case termsOfUse
    case paywall
    case family
    case journeyTree
    case journeyReport
    case community
    case pharmacySearch(query: String = "")
    case refillStock
    case medicineReport
    case medicineReportEdit
    case reportsHub
}

enum CheckMedDemo {
    static let streakDays = 6

    struct Dose {
        let time: String
        let name: String
        let detail: String
        let period: String
        let taken: Bool
        var asNeeded: Bool = false
    }

    static let todayDoses: [Dose] = [
        .init(time: "08:00", name: "Amoxicillin 500mg", detail: "1 capsule", period: "Morning", taken: true),
        .init(time: "14:00", name: "Ibuprofen 400mg", detail: "As needed", period: "Afternoon", taken: false, asNeeded: true),
        .init(time: "20:00", name: "Amoxicillin 500mg", detail: "1 capsule", period: "Evening", taken: false),
    ]

    struct Medicine {
        let name: String
        let schedule: String
        let duration: String
        let status: String
    }

    static let medicines: [Medicine] = [
        .init(name: "Amoxicillin 500mg", schedule: "1 capsule · 3× daily", duration: "7 days", status: "Active"),
        .init(name: "Ibuprofen 400mg", schedule: "As needed", duration: "With meals if pain", status: "Active"),
    ]

    struct TimelineDay {
        let date: String
        let note: String
        let status: String
    }

    static let timelineDays: [TimelineDay] = [
        .init(date: "Aug 24", note: "Started", status: "start"),
        .init(date: "Aug 25", note: "3/3", status: "done"),
        .init(date: "Aug 26", note: "3/3", status: "done"),
        .init(date: "Aug 27", note: "2/3", status: "partial"),
        .init(date: "Aug 28", note: "Today", status: "today"),
        .init(date: "Aug 29", note: "Upcoming", status: "soon"),
        .init(date: "Aug 30", note: "Ends", status: "end"),
    ]

    static let classLabel = "Penicillin-class antibiotic"
    static let source = "Structured medication record (demo) · not a substitute for your clinician or pharmacist"
    static let whatItDoes = "Used to treat certain bacterial infections, as written on the prescription."
    static let whyPrescribed = "This plan: 7-day course from the scanned prescription."
    static let howTaken = "1 capsule, 3 times daily, with water."
    static let common = ["Upset stomach", "Diarrhea", "Mild rash"]
    static let lessCommon = ["Yeast infection", "Headache"]
    static let serious = ["Allergic reaction (hives, swelling, trouble breathing)"]
    static let interactions = "May interact with some anticoagulants and other antibiotics — confirm with your pharmacist."
    static let allergies = "Do not use if you have a known penicillin allergy, unless a clinician has advised otherwise."
    static let contraindications = "Prior severe reaction to penicillins or related drugs — clinician decision."
    static let food = "Can usually be taken with or without food. Alcohol is not a substitute for medical advice — ask your pharmacist if unsure."

    static let howSteps: [(title: String, body: String)] = [
        ("Take a photo", "Take a picture of your prescription and let Conny Cooper help read and organize the information."),
        ("Know what you’re taking", "See your medicines, dosage, frequency, and important information in one simple place."),
        ("Get reminders", "Create a personalized medication schedule and receive reminders when it’s time to take each medicine."),
        ("Hear it explained", "Use AI voice assistance to listen to your medication instructions and explanations."),
    ]
}

struct RouteNavigator {
    var path: Binding<NavigationPath>

    func go(_ route: AppRoute) {
        path.wrappedValue.append(route)
    }

    func pop() {
        guard !path.wrappedValue.isEmpty else { return }
        path.wrappedValue.removeLast()
    }
}

struct AppRouteView: View {
    let route: AppRoute
    @Binding var path: NavigationPath

    var body: some View {
        let nav = RouteNavigator(path: $path)
        switch route {
        case .todayTreatment: TodayTreatmentScreen(go: nav.go)
        case .upcoming: UpcomingScreen()
        case .dailySummary: DailySummaryScreen()
        case .addPrescription: AddPrescriptionGateHost()
        case .cameraScanner: CameraScannerScreen(go: nav.go)
        case .scanning: ScanningScreen(go: nav.go)
        case .extractionResults: ExtractionResultsScreen(go: nav.go)
        case .verifyPrescription: VerifyPrescriptionScreen(go: nav.go)
        case .prescriptionSaved: PrescriptionSavedScreen(go: nav.go)
        case .treatmentOverview: TreatmentOverviewScreen(go: nav.go)
        case .medicationList: MedicationListScreen(go: nav.go)
        case .medicationDetail(let id): MedicationDetailScreen(go: nav.go, medicineId: id)
        case .howToTake: HowToTakeScreen(go: nav.go)
        case .treatmentTimeline: TreatmentTimelineScreen(go: nav.go)
        case .editTreatment: EditTreatmentScreen(go: nav.go)
        case .nextDose: NextDoseScreen(go: nav.go)
        case .medicationAlarm: MedicationAlarmScreen(go: nav.go)
        case .confirmMedication: ConfirmMedicationScreen(go: nav.go)
        case .doseCompleted: DoseCompletedScreen(go: nav.go)
        case .missedDose: MissedDoseScreen(go: nav.go)
        case .reminderSettings: ReminderSettingsScreen(go: nav.go)
        case .progressDashboard: ProgressDashboardScreen(go: nav.go)
        case .badges: BadgesScreen()
        case .adherence: AdherenceScreen()
        case .treatmentHistory: TreatmentHistoryScreen(go: nav.go)
        case .treatmentComplete: TreatmentCompleteScreen(go: nav.go)
        case .myMedicines: MyMedicinesScreen(go: nav.go)
        case .medicineHistory: MedicineHistoryScreen()
        case .notificationPrefs: NotificationPrefsScreen()
        case .settings: SettingsScreen(go: nav.go)
        case .privacySettings: PrivacySettingsView()
        case .privacyPolicy: LegalDocumentView(kind: .privacyPolicy)
        case .termsOfUse: LegalDocumentView(kind: .termsOfUse)
        case .paywall: PaywallView()
        case .family: FamilyView()
        case .journeyTree: JourneyTreeScreen(go: nav.go)
        case .journeyReport: JourneyReportScreen(go: nav.go)
        case .community: CommunityScreen()
        case .pharmacySearch(let query): PharmacySearchScreen(initialQuery: query)
        case .refillStock: RefillStockScreen(go: nav.go)
        case .medicineReport: MedicineReportScreen(go: nav.go)
        case .medicineReportEdit: MedicineReportEditScreen()
        case .reportsHub: ReportsHubScreen(go: nav.go)
        }
    }
}

struct ScreenScaffold<Content: View>: View {
    let title: String
    var kicker: String?
    var philSize: CGFloat = 96
    var bubble: String?
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let kicker {
                    Text(kicker)
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .foregroundStyle(CheckMedTheme.muted)
                }
                if let bubble {
                    HStack(alignment: .center, spacing: 12) {
                        PhilView(size: philSize)
                        SpeechBubbleView(text: bubble)
                    }
                } else {
                    HStack {
                        Spacer()
                        PhilView(size: philSize)
                        Spacer()
                    }
                }
                content
            }
            .padding(16)
        }
        .background(CheckMedTheme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FactBlock: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(CheckMedTheme.muted)
            Text(value)
                .font(.system(.body, design: .rounded).weight(.bold))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(CheckMedTheme.hairline, lineWidth: 2)
        )
    }
}

struct CardBlock: View {
    let kicker: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(kicker)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(CheckMedTheme.muted)
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.heavy))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(CheckMedTheme.hairline, lineWidth: 2)
        )
    }
}

struct SourceNote: View {
    var text: String = CheckMedDemo.source

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .rounded).weight(.bold))
            .foregroundStyle(CheckMedTheme.safety)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
