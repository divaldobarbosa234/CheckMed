import CoreLocation
import MapKit
import SwiftUI
import UIKit

struct FeelingCheckInSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(CheckMedStore.self) private var treatments
    @Environment(\.dismiss) private var dismiss
    let logId: UUID
    let medicine: String
    @State private var mood: FeelingMood = .okay
    @State private var note = ""

    var body: some View {
        NavigationStack {
            ScreenScaffold(
                title: session.t(.feelingTitle),
                bubble: session.t(.feelingBubble, medicine)
            ) {
                ForEach(FeelingMood.allCases) { option in
                    Button {
                        mood = option
                    } label: {
                        HStack {
                            Text(option.title(session))
                                .font(.system(.body, design: .rounded).weight(.bold))
                                .foregroundStyle(CheckMedTheme.ink)
                            Spacer()
                            if mood == option {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(CheckMedTheme.primaryShadow)
                            }
                        }
                        .padding(14)
                        .background(CheckMedTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(mood == option ? CheckMedTheme.primary : CheckMedTheme.hairline, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
                TextField(session.t(.feelingNotePlaceholder), text: $note, axis: .vertical)
                    .lineLimit(3...5)
                    .padding(14)
                    .background(CheckMedTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text(session.t(.feelingNotAdvice))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.safety)
                CheckMedButton(title: session.t(.feelingSave)) {
                    treatments.addFeeling(logId: logId, medicineName: medicine, mood: mood, note: note)
                    dismiss()
                }
                CheckMedButton(title: session.t(.feelingSkip), style: .ghost) {
                    dismiss()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(session.t(.cancel)) { dismiss() }
                }
            }
        }
    }
}

struct JourneyReportScreen: View {
    var go: (AppRoute) -> Void
    @Environment(SessionStore.self) private var session
    @Environment(CheckMedStore.self) private var treatments
    @Environment(EntitlementStore.self) private var entitlements

    private var reports: [JourneyReport] {
        let finished = treatments.finishedJourneyReports()
        return finished.isEmpty ? treatments.journeyReports() : finished
    }

    var body: some View {
        ScreenScaffold(
            title: session.t(.journeyTitle),
            bubble: entitlements.canViewJourneyReport
                ? session.t(.journeyBubble)
                : session.t(.journeyLockedBubble)
        ) {
            if !entitlements.canViewJourneyReport {
                SuperLockBadge()
                Text(session.t(.journeyLockedBody))
                    .font(.system(.body, design: .rounded).weight(.bold))
                CheckMedButton(title: session.t(.profileSuper)) { entitlements.presentPaywall() }
            } else if reports.isEmpty {
                Text(session.t(.journeyEmpty))
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
            } else {
                ForEach(reports, id: \.treatmentId) { report in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(report.title)
                            .font(.system(.title3, design: .rounded).weight(.heavy))
                        Text(session.t(.journeyStats, report.takenCount, report.plannedCount, report.percent))
                            .font(.system(.body, design: .rounded).weight(.bold))
                        Text(session.t(.journeySkipped, report.skippedCount))
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(CheckMedTheme.muted)
                        Text(session.t(
                            .journeyFeelings,
                            report.feelingGreat,
                            report.feelingOkay,
                            report.feelingLow,
                            report.feelingSideEffect
                        ))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        Text(report.medicines.joined(separator: " · "))
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(CheckMedTheme.muted)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CheckMedTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
            }
            Text(session.t(.journeyNotAdvice))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.safety)
            if entitlements.canViewJourneyReport, !reports.isEmpty {
                ShareLink(item: Self.shareText(reports: reports, session: session)) {
                    Text(session.t(.journeyShare))
                        .font(.system(.body, design: .rounded).weight(.heavy))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
            }
            CheckMedButton(title: session.t(.progressTitle), style: .ghost) { go(.progressDashboard) }
        }
    }

    private static func shareText(reports: [JourneyReport], session: SessionStore) -> String {
        reports.map { report in
            """
            \(report.title)
            \(session.t(.journeyStats, report.takenCount, report.plannedCount, report.percent))
            \(session.t(.journeySkipped, report.skippedCount))
            \(report.medicines.joined(separator: ", "))
            \(session.t(.journeyNotAdvice))
            """
        }.joined(separator: "\n\n")
    }
}

struct CommunityScreen: View {
    @Environment(SessionStore.self) private var session
    @Environment(CheckMedStore.self) private var treatments
    @State private var medicine = ""
    @State private var draft = ""

    private var query: String {
        let typed = medicine.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        return treatments.medicineSummaries().first?.name ?? "Ibuprofen"
    }

    private var comments: [CommunityCommentRecord] {
        treatments.comments(forMedicine: query)
    }

    var body: some View {
        ScreenScaffold(
            title: session.t(.notesOnDevice),
            bubble: session.t(.communityBubble)
        ) {
            MedicineNameField(title: session.t(.communityMedicine), text: $medicine)
            Text(session.t(.communityDisclaimer))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.safety)
            ForEach(CommunitySeed.notes(for: query, session: session), id: \.self) { note in
                commentCard(author: session.t(.communityPhilNote), body: note)
            }
            ForEach(comments) { row in
                commentCard(author: row.author, body: row.body)
            }
            TextField(session.t(.communityPlaceholder), text: $draft, axis: .vertical)
                .lineLimit(2...4)
                .padding(14)
                .background(CheckMedTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            CheckMedButton(title: session.t(.communityPost)) {
                treatments.addComment(
                    medicineName: query,
                    author: session.displayName,
                    body: draft
                )
                draft = ""
            }
        }
    }

    private func commentCard(author: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(author)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
            Text(body)
                .font(.system(.body, design: .rounded).weight(.bold))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private enum CommunitySeed {
    static func notes(for medicine: String, session: SessionStore) -> [String] {
        [session.t(.communitySeed1, medicine), session.t(.communitySeed2)]
    }
}

struct PharmacySearchScreen: View {
    @Environment(SessionStore.self) private var session
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(CheckMedStore.self) private var treatments
    @State private var query = ""
    @State private var items: [MKMapItem] = []
    @State private var status = ""
    @State private var locator = PharmacyLocator()

    var body: some View {
        ScreenScaffold(
            title: session.t(.pharmacyTitle),
            bubble: session.t(.pharmacyBubble)
        ) {
            if !entitlements.canSearchPharmacies {
                SuperLockBadge()
                Text(session.t(.pharmacyLocked))
                    .font(.system(.body, design: .rounded).weight(.bold))
                CheckMedButton(title: session.t(.profileSuper)) { entitlements.presentPaywall() }
            } else {
                TextField(session.t(.pharmacyQuery), text: $query)
                    .padding(14)
                    .background(CheckMedTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                CheckMedButton(title: session.t(.pharmacySearch)) {
                    Task { await search() }
                }
                if !status.isEmpty {
                    Text(status)
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.muted)
                }
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Button {
                        item.openInMaps()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name ?? session.t(.pharmacyTitle))
                                .font(.system(.body, design: .rounded).weight(.heavy))
                                .foregroundStyle(CheckMedTheme.ink)
                        Text(item.placemark.title ?? "")
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(CheckMedTheme.muted)
                        if let phone = item.phoneNumber, let url = URL(string: "tel://\(phone.filter(\.isNumber))") {
                            Text(session.t(.pharmacyCall, phone))
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .foregroundStyle(CheckMedTheme.primaryShadow)
                                .onTapGesture { UIApplication.shared.open(url) }
                        }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(CheckMedTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(session.t(.pharmacyDisclaimer))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.safety)
        }
        .onAppear {
            if query.isEmpty {
                query = treatments.medicineSummaries().first?.name ?? ""
            }
        }
        .task { await locator.request() }
    }

    private func search() async {
        status = session.t(.pharmacySearching)
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let found = await locator.search(medicine: term, locale: session.locale)
        items = found
        status = found.isEmpty ? session.t(.pharmacyEmpty) : session.t(.pharmacyFound, found.count)
    }
}

@MainActor
private final class PharmacyLocator: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request() async {
        manager.requestWhenInUseAuthorization()
    }

    func search(medicine: String, locale: AppLocale) async -> [MKMapItem] {
        let location = await currentLocation()
        let request = MKLocalSearch.Request()
        let pharmacy = switch locale {
        case .portuguese: "farmácia"
        case .spanish: "farmacia"
        case .french: "pharmacie"
        case .english: "pharmacy"
        }
        request.naturalLanguageQuery = medicine.isEmpty ? pharmacy : "\(pharmacy) \(medicine)"
        request.resultTypes = .pointOfInterest
        if let location {
            request.region = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 8_000,
                longitudinalMeters: 8_000
            )
        }
        do {
            let response = try await MKLocalSearch(request: request).start()
            return Array(response.mapItems.prefix(12))
        } catch {
            return []
        }
    }

    private func currentLocation() async -> CLLocation? {
        if let location = manager.location { return location }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            continuation?.resume(returning: locations.last)
            continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            continuation?.resume(returning: nil)
            continuation = nil
        }
    }
}

struct AppearancePicker: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.t(.appearanceTitle))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(CheckMedTheme.muted)
            ForEach(AppearanceMode.allCases) { mode in
                Button {
                    session.setAppearance(mode)
                } label: {
                    HStack {
                        Text(mode.title(session))
                            .font(.system(.body, design: .rounded).weight(.bold))
                            .foregroundStyle(CheckMedTheme.ink)
                        Spacer()
                        if session.appearance == mode {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(CheckMedTheme.primaryShadow)
                        }
                    }
                    .padding(12)
                    .background(CheckMedTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
