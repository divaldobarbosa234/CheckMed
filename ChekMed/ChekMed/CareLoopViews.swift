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

    private var finishedReports: [JourneyReport] {
        treatments.finishedJourneyReports()
    }

    private var reports: [JourneyReport] {
        // Prefer finished plans (e.g. after "See the report") so completing never looks like a wipe.
        if !finishedReports.isEmpty { return finishedReports }
        return treatments.journeyReports()
    }

    var body: some View {
        ScreenScaffold(
            title: session.t(.journeyTitle),
            bubble: session.t(.journeyBubble)
        ) {
            // Free users can browse/view; Super gates share/export.
            if reports.isEmpty {
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
            if !reports.isEmpty {
                if entitlements.canViewJourneyReport {
                    ShareLink(item: Self.shareText(reports: reports, session: session)) {
                        Text(session.t(.journeyShare))
                            .font(.system(.body, design: .rounded).weight(.heavy))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                } else {
                    CheckMedButton(title: session.t(.journeyShare), style: .secondary) {
                        entitlements.presentPaywall()
                    }
                }
            }
            CheckMedButton(title: session.t(.reportHeadline), style: .secondary) {
                go(.medicineReport)
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

struct PharmacyResult: Identifiable, Hashable {
    let id: String
    let item: MKMapItem
    let distanceMeters: CLLocationDistance?
    let coordinate: CLLocationCoordinate2D

    init(item: MKMapItem, distanceMeters: CLLocationDistance?, coordinate: CLLocationCoordinate2D) {
        let lat = String(format: "%.5f", coordinate.latitude)
        let lon = String(format: "%.5f", coordinate.longitude)
        self.id = "\(item.name ?? "pharmacy")-\(lat)-\(lon)"
        self.item = item
        self.distanceMeters = distanceMeters
        self.coordinate = coordinate
    }

    static func == (lhs: PharmacyResult, rhs: PharmacyResult) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct PharmacySearchScreen: View {
    @Environment(SessionStore.self) private var session
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(CheckMedStore.self) private var treatments
    var initialQuery: String = ""
    @State private var query = ""
    @State private var results: [PharmacyResult] = []
    @State private var status = ""
    @State private var locator = PharmacyLocator()
    @State private var userLocation: CLLocation?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedResultID: String?

    var body: some View {
        ScreenScaffold(
            title: session.t(.pharmacyTitle),
            bubble: session.t(.pharmacyBubble)
        ) {
            // Free users can open the map UI; Super gates MapKit search only.
            TextField(session.t(.pharmacyQuery), text: $query)
                .textInputAutocapitalization(.words)
                .padding(14)
                .background(CheckMedTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(CheckMedTheme.hairline, lineWidth: 1.5)
                )
                .onSubmit {
                    Task { await runSearchOrPaywall() }
                }
            CheckMedButton(title: session.t(.pharmacySearch)) {
                Task { await runSearchOrPaywall() }
            }
            ZStack {
                pharmacyMap
                if !entitlements.canSearchPharmacies, results.isEmpty {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(CheckMedTheme.ink.opacity(0.28))
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 22, weight: .bold))
                        Text(session.t(.pharmacySearchHint))
                            .font(.system(.subheadline, design: .rounded).weight(.heavy))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .allowsHitTesting(false)
                }
            }
            if !status.isEmpty {
                Text(status)
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
            }
            ForEach(results) { result in
                pharmacyCard(result)
            }
            Text(session.t(.pharmacyDisclaimer))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.safety)
        }
        .onAppear {
            seedQueryIfNeeded()
        }
        .onChange(of: entitlements.isSuper) { _, isSuper in
            if isSuper {
                Task {
                    seedQueryIfNeeded()
                    userLocation = await locator.requestAndLocate()
                    await search()
                }
            }
        }
        .task {
            seedQueryIfNeeded()
            userLocation = await locator.requestAndLocate()
            fitCameraToContext()
            if entitlements.canSearchPharmacies {
                await search()
            }
        }
    }

    private func runSearchOrPaywall() async {
        guard entitlements.canSearchPharmacies else {
            entitlements.presentPaywall()
            return
        }
        await search()
    }

    private var pharmacyMap: some View {
        Map(position: $cameraPosition, selection: $selectedResultID) {
            if let userLocation {
                Annotation("", coordinate: userLocation.coordinate) {
                    ZStack {
                        Circle()
                            .fill(CheckMedTheme.flowDot.opacity(0.22))
                            .frame(width: 28, height: 28)
                        Circle()
                            .fill(CheckMedTheme.flowDot)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    }
                }
                .tag("user")
            }
            ForEach(results) { result in
                Annotation(result.item.name ?? session.t(.pharmacyTitle), coordinate: result.coordinate) {
                    Image(systemName: "cross.case.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(
                            selectedResultID == result.id
                                ? CheckMedTheme.primaryShadow
                                : CheckMedTheme.flowDot,
                            in: Circle()
                        )
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                }
                .tag(result.id)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(CheckMedTheme.hairline, lineWidth: 1.5)
        )
        .onChange(of: selectedResultID) { _, id in
            guard let id, let match = results.first(where: { $0.id == id }) else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: match.coordinate,
                        latitudinalMeters: 1_200,
                        longitudinalMeters: 1_200
                    )
                )
            }
        }
    }

    private func pharmacyCard(_ result: PharmacyResult) -> some View {
        let item = result.item
        let isSelected = selectedResultID == result.id
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name ?? session.t(.pharmacyTitle))
                        .font(.system(.body, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.ink)
                    if let address = Self.addressLine(for: item) {
                        Text(address)
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(CheckMedTheme.muted)
                    }
                    if let meters = result.distanceMeters {
                        Text(session.t(.pharmacyDistance, Self.formatDistance(meters, locale: session.locale)))
                            .font(.system(.caption, design: .rounded).weight(.heavy))
                            .foregroundStyle(CheckMedTheme.flowDot)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "cross.case.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(CheckMedTheme.primaryShadow)
                    .frame(width: 40, height: 40)
                    .background(CheckMedTheme.mintWash, in: Circle())
            }

            HStack(spacing: 8) {
                if let phone = item.phoneNumber {
                    let digits = phone.filter(\.isNumber)
                    if let url = URL(string: "tel://\(digits)"), !digits.isEmpty {
                        Button {
                            UIApplication.shared.open(url)
                        } label: {
                            Label(session.t(.pharmacyCallShort), systemImage: "phone.fill")
                                .font(.system(.caption, design: .rounded).weight(.heavy))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(CheckMedTheme.primary.opacity(0.35))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(session.t(.pharmacyCall, phone))
                    }
                }
                Button {
                    item.openInMaps(launchOptions: [
                        MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving,
                    ])
                } label: {
                    Label(session.t(.pharmacyOpenMaps), systemImage: "map.fill")
                        .font(.system(.caption, design: .rounded).weight(.heavy))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(CheckMedTheme.philFlowCanvas)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? CheckMedTheme.flowDot : CheckMedTheme.hairline, lineWidth: isSelected ? 2 : 1.5)
        )
        .onTapGesture {
            selectedResultID = result.id
            withAnimation(.easeInOut(duration: 0.25)) {
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: result.coordinate,
                        latitudinalMeters: 1_200,
                        longitudinalMeters: 1_200
                    )
                )
            }
        }
    }

    private func seedQueryIfNeeded() {
        guard query.isEmpty else { return }
        query = initialQuery.isEmpty
            ? (treatments.medicineSummaries().first?.name ?? "")
            : initialQuery
    }

    private func search() async {
        status = session.t(.pharmacySearching)
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let found = await locator.search(medicine: term, locale: session.locale)
        let origin = userLocation ?? locator.lastLocation
        if origin != nil { userLocation = origin }
        let mapped: [PharmacyResult] = found.compactMap { item in
            guard let coordinate = Self.coordinate(for: item) else { return nil }
            let meters: CLLocationDistance?
            if let origin {
                meters = origin.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            } else {
                meters = nil
            }
            return PharmacyResult(item: item, distanceMeters: meters, coordinate: coordinate)
        }
        .sorted { lhs, rhs in
            (lhs.distanceMeters ?? .greatestFiniteMagnitude) < (rhs.distanceMeters ?? .greatestFiniteMagnitude)
        }
        results = mapped
        selectedResultID = mapped.first?.id
        status = mapped.isEmpty ? session.t(.pharmacyEmpty) : session.t(.pharmacyFound, mapped.count)
        fitCameraToContext()
    }

    private func fitCameraToContext() {
        let coords = results.map(\.coordinate)
        if coords.isEmpty {
            if let user = userLocation?.coordinate ?? locator.lastLocation?.coordinate {
                cameraPosition = .region(
                    MKCoordinateRegion(center: user, latitudinalMeters: 5_000, longitudinalMeters: 5_000)
                )
            }
            return
        }
        if coords.count == 1, let only = coords.first {
            cameraPosition = .region(
                MKCoordinateRegion(center: only, latitudinalMeters: 1_800, longitudinalMeters: 1_800)
            )
            return
        }
        var minLat = coords[0].latitude
        var maxLat = coords[0].latitude
        var minLon = coords[0].longitude
        var maxLon = coords[0].longitude
        for c in coords.dropFirst() {
            minLat = min(minLat, c.latitude)
            maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude)
            maxLon = max(maxLon, c.longitude)
        }
        if let user = userLocation?.coordinate {
            minLat = min(minLat, user.latitude)
            maxLat = max(maxLat, user.latitude)
            minLon = min(minLon, user.longitude)
            maxLon = max(maxLon, user.longitude)
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let latDelta = max((maxLat - minLat) * 1.45, 0.02)
        let lonDelta = max((maxLon - minLon) * 1.45, 0.02)
        cameraPosition = .region(MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)))
    }

    private static func coordinate(for item: MKMapItem) -> CLLocationCoordinate2D? {
        let coordinate = item.location.coordinate
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }

    private static func addressLine(for item: MKMapItem) -> String? {
        if let short = item.address?.shortAddress, !short.isEmpty {
            return short
        }
        if let full = item.address?.fullAddress, !full.isEmpty {
            return full
        }
        if let city = item.addressRepresentations?.cityWithContext, !city.isEmpty {
            return city
        }
        if let singleLine = item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true), !singleLine.isEmpty {
            return singleLine
        }
        return nil
    }

    private static func formatDistance(_ meters: CLLocationDistance, locale: AppLocale) -> String {
        if meters < 1000 {
            return String(format: "%.0f m", meters)
        }
        let km = meters / 1000
        let formatter = NumberFormatter()
        formatter.locale = locale.foundationLocale
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 1
        let value = formatter.string(from: NSNumber(value: km)) ?? String(format: "%.1f", km)
        return "\(value) km"
    }
}

@MainActor
private final class PharmacyLocator: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private(set) var lastLocation: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request() async {
        manager.requestWhenInUseAuthorization()
    }

    func requestAndLocate() async -> CLLocation? {
        manager.requestWhenInUseAuthorization()
        let location = await currentLocation()
        lastLocation = location
        return location
    }

    func search(medicine: String, locale: AppLocale) async -> [MKMapItem] {
        let location: CLLocation?
        if let lastLocation {
            location = lastLocation
        } else {
            location = await currentLocation()
        }
        lastLocation = location
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
        if let location = manager.location {
            lastLocation = location
            return location
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            lastLocation = locations.last
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
