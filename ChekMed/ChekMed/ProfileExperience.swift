import SwiftUI
import UIKit
import UserNotifications

/// Profile family — presentation only. Uses SessionStore, FamilyStore, ReminderPreferences, PaywallView.
private enum ProfileChrome {
    static let cardRadius: CGFloat = 22
    /// Floating tab bar overlap only — Profile has no FAB (Alternative A).
    static let tabBarClearance: CGFloat = 52

    static var tabBarScrollClearance: some View {
        Color.clear
            .frame(height: tabBarClearance)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private func profileShownName(_ session: SessionStore) -> String {
    let raw = session.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    let lowered = raw.lowercased()
    if raw.isEmpty || lowered == "there" || lowered == "friend" {
        return session.t(.homeFriendName)
    }
    return raw
}

private func profileInitials(_ session: SessionStore) -> String {
    let name = profileShownName(session)
    let parts = name.split(whereSeparator: { $0.isWhitespace }).prefix(2)
    let letters = parts.compactMap { $0.first }.map(String.init)
    return letters.joined().uppercased()
}

struct ProfileRootScreen: View {
    @Environment(SessionStore.self) private var session
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(FamilyStore.self) private var family
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    VStack(alignment: .leading, spacing: 12) {
                        sectionLabel(session.t(.profileSectionAccount))
                        row(
                            icon: "person.fill",
                            wash: CheckMedTheme.blueWash,
                            tint: CheckMedTheme.flowDot,
                            title: session.t(.profilePersonalInfo),
                            subtitle: session.t(.profilePersonalInfoHint)
                        ) { path.append(AppRoute.personalInformation) }
                        row(
                            icon: "person.2.fill",
                            wash: CheckMedTheme.belly,
                            tint: CheckMedTheme.current,
                            title: session.t(.profileFamily),
                            subtitle: session.t(.profileFamilyManage, family.occupiedSlots, entitlements.familySlots)
                        ) { path.append(AppRoute.family) }

                        sectionLabel(session.t(.profileSectionPrefs))
                        row(
                            icon: "bell.fill",
                            wash: CheckMedTheme.philFlowCanvas,
                            tint: CheckMedTheme.flowDot,
                            title: session.t(.profileNotifsRow),
                            subtitle: session.t(.profileNotifsHint)
                        ) { path.append(AppRoute.notificationPrefs) }
                        row(
                            icon: "gearshape.fill",
                            wash: CheckMedTheme.lavenderWash,
                            tint: CheckMedTheme.superAccent,
                            title: session.t(.profileSettingsPrivacy),
                            subtitle: session.t(.profileSettingsPrivacyHint)
                        ) { path.append(AppRoute.settingsPrivacy) }

                        sectionLabel(session.t(.profileSectionCooper))
                        row(
                            icon: "sparkles",
                            wash: CheckMedTheme.lavenderWash,
                            tint: CheckMedTheme.superAccent,
                            title: session.t(.profileSuper),
                            subtitle: entitlements.isSuper ? session.t(.paywallSuper) : session.t(.profileFree)
                        ) { entitlements.presentPaywall() }
                        row(
                            icon: "questionmark.circle.fill",
                            wash: CheckMedTheme.mintWash,
                            tint: CheckMedTheme.primaryShadow,
                            title: session.t(.profileHelpTitle),
                            subtitle: session.t(.profileHelpBody)
                        ) { path.append(AppRoute.helpSupport) }

                        if let error = session.errorMessage {
                            Text(error)
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .foregroundStyle(CheckMedTheme.danger)
                        }
                        SafetyCaption()
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear
                    .frame(height: ProfileChrome.tabBarClearance)
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .background(CheckMedTheme.background.ignoresSafeArea(edges: .top))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: AppRoute.self) { route in
                AppRouteView(route: route, path: $path)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Text(session.t(.profileTitle))
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(CheckMedTheme.ink)
                Spacer(minLength: 8)
                Button { path.append(AppRoute.settingsPrivacy) } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(CheckMedTheme.muted)
                        .frame(width: 38, height: 38)
                        .background(CheckMedTheme.surface, in: Circle())
                        .shadow(color: CheckMedTheme.navy.opacity(0.08), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(session.t(.profileSettingsPrivacy))
            }
            HStack(alignment: .center, spacing: 14) {
                ProfileAvatarView(initials: profileInitials(session), size: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text(profileShownName(session))
                        .font(.system(.title3, design: .rounded).weight(.heavy))
                    Text(session.email ?? session.t(.profileNoEmail))
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(CheckMedTheme.muted)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            HStack(alignment: .top, spacing: 12) {
                Text(session.t(.profileWelcome, profileShownName(session)))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                CooperLibraryImage(asset: "phil_glasses", size: 88)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CheckMedTheme.mintWash)
            .clipShape(RoundedRectangle(cornerRadius: ProfileChrome.cardRadius, style: .continuous))
            if family.isViewingExtra, let extra = family.extra {
                Text(session.t(.familyLookingAt, extra.name))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.superAccent)
            }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(.caption, design: .rounded).weight(.heavy))
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(CheckMedTheme.muted)
            .padding(.top, 6)
    }

    private func row(icon: String, wash: Color, tint: Color, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(wash, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.body, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Text(subtitle)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(CheckMedTheme.muted)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CheckMedTheme.muted)
            }
            .padding(16)
            .background(CheckMedTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: ProfileChrome.cardRadius, style: .continuous))
            .shadow(color: CheckMedTheme.navy.opacity(0.05), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct ProfileAvatarView: View {
    var initials: String
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(CheckMedTheme.belly)
            Circle().stroke(CheckMedTheme.hairline, lineWidth: 1.5)
            Text(initials)
                .font(.system(size: size * 0.32, weight: .black, design: .rounded))
                .foregroundStyle(CheckMedTheme.navy)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct PersonalInformationScreen: View {
    @Environment(SessionStore.self) private var session
    @State private var nameDraft = ""

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(session.t(.profilePersonalInfo))
                            .font(.system(.title2, design: .rounded).weight(.black))
                        Text(session.t(.profilePersonalSupport))
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(CheckMedTheme.muted)
                    }
                    Spacer()
                    CooperLibraryImage(asset: "phil_doctor_2d", size: 88)
                }
                ProfileAvatarView(initials: profileInitials(session), size: 88)
                    .frame(maxWidth: .infinity)
                Text(session.t(.profileAvatarDefaultHint))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)

                fieldCard(session.t(.preferredName), editable: true) {
                    TextField(session.t(.preferredName), text: $nameDraft)
                        .onSubmit { session.setDisplayName(nameDraft) }
                }
                fieldCard(session.t(.profileAccount), editable: false) {
                    Text(session.email ?? session.t(.profileNoEmail))
                        .font(.system(.body, design: .rounded).weight(.bold))
                }
                DateOfBirthSelectField(
                    date: Binding(
                        get: { session.birthDate },
                        set: { session.setBirthDate($0) }
                    )
                )
                Text(session.t(.profileOptionalLater))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)
                PronounSelectField(
                    value: Binding(
                        get: { session.pronouns },
                        set: { session.setPronouns($0) }
                    )
                )
                GenderSelectField(
                    value: Binding(
                        get: { session.gender },
                        set: { session.setGender($0) }
                    )
                )
                CareContextSelectField(
                    value: Binding(
                        get: { session.careContextChoice },
                        set: { if let next = $0 { session.setCareContext(next) } }
                    )
                )
                LanguageSelectField(
                    locale: Binding(
                        get: { session.locale },
                        set: { session.setLocale($0) }
                    )
                )
                TimeZoneSelectField(
                    timeZone: Binding(
                        get: { session.timeZoneName },
                        set: { session.setTimeZoneName($0) }
                    )
                )
                SafetyCaption().frame(maxWidth: .infinity)
                ProfileChrome.tabBarScrollClearance
            }
            .padding(16)
        }
        .background(CheckMedTheme.background)
        .navigationTitle(session.t(.profilePersonalInfo))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { nameDraft = session.hasPreferredName ? session.displayName : "" }
        .onDisappear { session.setDisplayName(nameDraft) }
    }

    private func fieldCard<Content: View>(_ title: String, editable: Bool, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
                Spacer()
                Text(session.t(editable ? .profileEditable : .profileReadOnly))
                    .font(.system(.caption2, design: .rounded).weight(.heavy))
                    .foregroundStyle(editable ? CheckMedTheme.primaryShadow : CheckMedTheme.muted)
            }
            content()
        }
        .padding(14)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct FamilyProfilesScreen: View {
    var go: (AppRoute) -> Void
    @Environment(SessionStore.self) private var session
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(FamilyStore.self) private var family
    @Environment(CheckMedStore.self) private var treatments

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(session.t(.profileFamily))
                            .font(.system(.title2, design: .rounded).weight(.black))
                        Text(session.t(.familyOverviewSupport))
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(CheckMedTheme.muted)
                    }
                    Spacer()
                    CooperLibraryImage(asset: "phil_heart", size: 88)
                }

                memberCard(
                    title: profileShownName(session),
                    subtitle: session.t(.familyYou),
                    badge: family.isViewingExtra ? nil : session.t(.familyYouActive),
                    isActive: !family.isViewingExtra
                ) {
                    if family.isViewingExtra {
                        family.selectPrimary()
                        family.applyScope(to: treatments, primaryProfileId: session.profileId)
                    }
                    go(.personalInformation)
                }

                if let extra = family.extra {
                    memberCard(
                        title: extra.name,
                        subtitle: session.t(.familyExtraProfile),
                        badge: family.isViewingExtra ? session.t(.familyYouActive) : nil,
                        isActive: family.isViewingExtra
                    ) {
                        _ = family.selectExtra()
                        family.applyScope(to: treatments, primaryProfileId: session.profileId)
                        go(.familyDetail(extra.id))
                    }
                }

                if entitlements.extraFamilySlotUnlocked {
                    if family.extra == nil {
                        CheckMedButton(title: session.t(.familyAddProfile)) { go(.familyAdd) }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(session.t(.familySuperUpsell))
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(CheckMedTheme.muted)
                        CheckMedButton(title: session.t(.treatmentsTrySuper), style: .secondary) {
                            entitlements.presentPaywall()
                        }
                    }
                    .padding(16)
                    .background(CheckMedTheme.lavenderWash.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: ProfileChrome.cardRadius, style: .continuous))
                }
                SafetyCaption().frame(maxWidth: .infinity)
                ProfileChrome.tabBarScrollClearance
            }
            .padding(16)
        }
        .background(CheckMedTheme.background)
        .navigationTitle(session.t(.profileFamily))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func memberCard(title: String, subtitle: String, badge: String?, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ProfileAvatarView(initials: String(title.prefix(1)).uppercased(), size: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                    Text(subtitle)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(CheckMedTheme.muted)
                    if let badge {
                        Text(badge)
                            .font(.system(.caption2, design: .rounded).weight(.heavy))
                            .foregroundStyle(CheckMedTheme.primaryShadow)
                    }
                }
                Spacer()
                Image(systemName: isActive ? "checkmark.circle.fill" : "chevron.right")
                    .foregroundStyle(isActive ? CheckMedTheme.primaryShadow : CheckMedTheme.muted)
            }
            .padding(16)
            .background(isActive ? CheckMedTheme.mintWash.opacity(0.7) : CheckMedTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: ProfileChrome.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct FamilyAddScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(FamilyStore.self) private var family
    @State private var nameDraft = ""

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Spacer()
                    CooperLibraryImage(asset: "phil_wink", size: 96)
                    Spacer()
                }
                Text(session.t(.familyAddProfile))
                    .font(.system(.title2, design: .rounded).weight(.black))
                Text(session.t(.familyAddSupportedHint))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)
                TextField(session.t(.familyNamePlaceholder), text: $nameDraft)
                    .padding(14)
                    .background(CheckMedTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                CheckMedButton(title: session.t(.familySaveMember)) {
                    if family.addExtra(name: nameDraft, allowed: entitlements.extraFamilySlotUnlocked) {
                        dismiss()
                    } else {
                        entitlements.presentPaywall()
                    }
                }
                .disabled(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                ProfileChrome.tabBarScrollClearance
            }
            .padding(16)
        }
        .background(CheckMedTheme.background)
        .navigationTitle(session.t(.familyAddProfile))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FamilyDetailScreen: View {
    var memberId: UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @Environment(FamilyStore.self) private var family
    @Environment(CheckMedStore.self) private var treatments
    @State private var nameDraft = ""

    private var member: FamilyMember? {
        guard let extra = family.extra, extra.id == memberId else { return nil }
        return extra
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                if let member {
                    Text(session.t(.familyDetailTitle))
                        .font(.system(.title2, design: .rounded).weight(.black))
                    TextField(session.t(.familyNamePlaceholder), text: $nameDraft)
                        .padding(14)
                        .background(CheckMedTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    CheckMedButton(title: session.t(.familySaveMember)) {
                        _ = family.addExtra(name: nameDraft, allowed: true)
                    }
                    CheckMedButton(title: session.t(.familyRemove), style: .ghost) {
                        family.selectPrimary()
                        family.removeExtra()
                        family.applyScope(to: treatments, primaryProfileId: session.profileId)
                        dismiss()
                    }
                } else {
                    Text(session.t(.todayNothing))
                }
                ProfileChrome.tabBarScrollClearance
            }
            .padding(16)
        }
        .background(CheckMedTheme.background)
        .navigationTitle(session.t(.familyDetailTitle))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { nameDraft = member?.name ?? "" }
    }
}

struct ProfileNotificationsScreen: View {
    @Environment(SessionStore.self) private var session
    @Environment(EntitlementStore.self) private var entitlements
    @State private var quietHours = ReminderPreferences.quietHoursEnabled
    @State private var alarmTheme = ReminderPreferences.alarmTheme
    @State private var authorized = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(session.t(.profileNotifsRow))
                            .font(.system(.title2, design: .rounded).weight(.black))
                        Text(session.t(.profileNotifsSupport))
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(CheckMedTheme.muted)
                    }
                    Spacer()
                    CooperLibraryImage(asset: "phil_alert", size: 88)
                }

                statusCard
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(session.t(.prefsQuietToggle), isOn: $quietHours)
                        .font(.system(.body, design: .rounded).weight(.bold))
                        .onChange(of: quietHours) { _, value in
                            ReminderPreferences.quietHoursEnabled = value
                            ReminderScheduler.shared.reschedule()
                        }
                    Text(session.t(.profileQuietHint))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(CheckMedTheme.muted)
                }
                .padding(14)
                .background(CheckMedTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                AlarmThemePreferenceCard(alarmTheme: $alarmTheme)
                Toggle(session.t(.advanceHourToggle), isOn: Binding(
                    get: { entitlements.canUseAdvanceReminder && ReminderPreferences.advanceHourEnabled },
                    set: { value in
                        if entitlements.canUseAdvanceReminder {
                            ReminderPreferences.advanceHourEnabled = value
                            ReminderScheduler.shared.reschedule()
                        } else {
                            entitlements.presentPaywall()
                        }
                    }
                ))
                .font(.system(.body, design: .rounded).weight(.bold))
                .padding(14)
                .background(CheckMedTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                if !entitlements.canUseAdvanceReminder {
                    Text(session.t(.advanceHourLocked))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.muted)
                }
                Toggle(session.t(.winBackToggle), isOn: Binding(
                    get: { ReminderPreferences.winBackEnabled },
                    set: { value in
                        ReminderPreferences.winBackEnabled = value
                        ReminderScheduler.shared.reschedule()
                    }
                ))
                .font(.system(.body, design: .rounded).weight(.bold))
                .padding(14)
                .background(CheckMedTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Text(session.t(.profileRefillNotifsHint))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)

                Stepper(
                    "\(session.t(.prefsGraceMinutes)): \(ReminderPreferences.confirmationGraceMinutes)",
                    value: Binding(
                        get: { ReminderPreferences.confirmationGraceMinutes },
                        set: {
                            ReminderPreferences.confirmationGraceMinutes = $0
                            ReminderScheduler.shared.reschedule()
                        }
                    ),
                    in: 10...180,
                    step: 5
                )
                .font(.system(.body, design: .rounded).weight(.bold))
                Stepper(
                    "\(session.t(.prefsSnoozeMinutes)): \(ReminderPreferences.snoozeMinutes)",
                    value: Binding(
                        get: { ReminderPreferences.snoozeMinutes },
                        set: {
                            ReminderPreferences.snoozeMinutes = $0
                            ReminderScheduler.shared.reschedule()
                        }
                    ),
                    in: 5...30,
                    step: 1
                )
                .font(.system(.body, design: .rounded).weight(.bold))
                ProfileChrome.tabBarScrollClearance
            }
            .padding(16)
        }
        .background(CheckMedTheme.background)
        .navigationTitle(session.t(.profileNotifsRow))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            quietHours = ReminderPreferences.quietHoursEnabled
            alarmTheme = ReminderPreferences.resolvedAlarmTheme(canChoose: entitlements.canChooseAlarmTheme)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(authorized ? session.t(.notifsEnable) : session.t(.remindersPermissionOff))
                .font(.system(.body, design: .rounded).weight(.bold))
            if !authorized, let url = URL(string: UIApplication.openSettingsURLString) {
                Link(session.t(.profileOpenSystemSettings), destination: url)
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckMedTheme.primaryShadow)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

}

struct SettingsPrivacyScreen: View {
    var go: (AppRoute) -> Void
    @Environment(SessionStore.self) private var session

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(session.t(.profileSettingsPrivacy))
                            .font(.system(.title2, design: .rounded).weight(.black))
                        Text(session.t(.profileSettingsPrivacySupport))
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(CheckMedTheme.muted)
                    }
                    Spacer()
                    CooperLibraryImage(asset: "phil_thinking", size: 88)
                }
                navRow("paintpalette.fill", session.t(.appearanceTitle), session.t(.profileAppearanceHint)) { go(.appearance) }
                navRow("hand.raised.fill", session.t(.privacySettingsTitle), session.t(.privacySettingsHint)) { go(.privacyData) }
                navRow("lock.fill", session.t(.profileSecurityAccount), session.t(.profileSecurityHint)) { go(.securityAccount) }
                navRow("doc.text.fill", session.t(.profileTermsPolicies), session.t(.profileTermsHint)) { go(.termsOfUse) }
                navRow("questionmark.circle.fill", session.t(.profileHelpTitle), session.t(.profileHelpBody)) { go(.helpSupport) }
                ProfileChrome.tabBarScrollClearance
            }
            .padding(16)
        }
        .background(CheckMedTheme.background)
        .navigationTitle(session.t(.profileSettingsPrivacy))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func navRow(_ icon: String, _ title: String, _ subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(CheckMedTheme.primaryShadow)
                    .frame(width: 36, height: 36)
                    .background(CheckMedTheme.mintWash, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(.body, design: .rounded).weight(.heavy)).foregroundStyle(CheckMedTheme.ink)
                    Text(subtitle).font(.system(.caption, design: .rounded).weight(.semibold)).foregroundStyle(CheckMedTheme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(CheckMedTheme.muted)
            }
            .padding(14)
            .background(CheckMedTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct AppearanceScreen: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(session.t(.appearanceTitle))
                            .font(.system(.title2, design: .rounded).weight(.black))
                        Text(session.t(.profileAppearanceLockedHint))
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(CheckMedTheme.muted)
                    }
                    Spacer()
                    CooperLibraryImage(asset: "phil_onboarding_05_healthy", size: 88)
                }
                HStack(alignment: .top, spacing: 10) {
                    ForEach([AppearanceMode.light, .dark, .system]) { mode in
                        appearanceChip(mode)
                    }
                }
                ProfileChrome.tabBarScrollClearance
            }
            .padding(16)
        }
        .background(CheckMedTheme.background)
        .navigationTitle(session.t(.appearanceTitle))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func appearanceChip(_ mode: AppearanceMode) -> some View {
        let available = mode == .light
        let selected = available && session.appearance == .light
        return VStack(spacing: 8) {
            Image(systemName: mode == .light ? "sun.max.fill" : (mode == .dark ? "moon.fill" : "circle.lefthalf.filled"))
                .font(.system(size: 22, weight: .bold))
            Text(mode.title(session))
                .font(.system(.caption, design: .rounded).weight(.heavy))
            if !available {
                Text(session.t(.profileAppearanceComingSoon))
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(CheckMedTheme.muted)
            }
        }
        .foregroundStyle(selected ? CheckMedTheme.onPrimary : CheckMedTheme.ink.opacity(available ? 1 : 0.45))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 6)
        .background(selected ? CheckMedTheme.navy : CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(selected ? CheckMedTheme.navy : CheckMedTheme.hairline, lineWidth: 1.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected, .isStaticText] : .isStaticText)
        .accessibilityHint(available ? "" : session.t(.profileAppearanceComingSoon))
        .allowsHitTesting(false)
    }
}

struct PrivacyDataScreen: View {
    var go: (AppRoute) -> Void
    @Environment(SessionStore.self) private var session

    var body: some View {
        VStack(spacing: 0) {
            PrivacySettingsView()
            Text(session.t(.profileExportHonestHint))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(CheckMedTheme.muted)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            CheckMedButton(title: session.t(.reportsHubTitle), style: .secondary) { go(.reportsHub) }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            ProfileChrome.tabBarScrollClearance
        }
        .background(CheckMedTheme.background)
        .navigationTitle(session.t(.privacySettingsTitle))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SecurityAccountScreen: View {
    @Environment(SessionStore.self) private var session
    @Environment(CheckMedStore.self) private var treatments
    @Environment(FamilyStore.self) private var family
    @State private var confirmDelete = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    Text(session.t(.profileSecurityAccount))
                        .font(.system(.title2, design: .rounded).weight(.black))
                    Spacer()
                    CooperLibraryImage(asset: "phil_mask", size: 80)
                }
                infoRow(session.t(.profileAccount), session.email ?? session.t(.profileNoEmail))
                if session.hasAppleIdentity {
                    infoRow(session.t(.continueWithApple), session.t(.profileLinked))
                }
                CheckMedButton(title: session.t(.profileSignOut), style: .secondary) { session.signOut() }
                    .accessibilityIdentifier("profile-sign-out")
                Button(session.t(.profileDelete)) { confirmDelete = true }
                    .font(.system(.body, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckMedTheme.danger)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(CheckMedTheme.danger.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                ProfileChrome.tabBarScrollClearance
            }
            .padding(16)
        }
        .background(CheckMedTheme.background)
        .navigationTitle(session.t(.profileSecurityAccount))
        .navigationBarTitleDisplayMode(.inline)
        .alert(session.t(.profileDeleteTitle), isPresented: $confirmDelete) {
            Button(session.t(.profileDeleteConfirm), role: .destructive) {
                session.deleteAccount(treatments: treatments, family: family)
            }
            Button(session.t(.cancel), role: .cancel) {}
        } message: {
            Text(session.t(session.hasAppleIdentity ? .profileDeleteBodyApple : .profileDeleteBody))
        }
        .disabled(session.isDeletingAccount)
        .overlay {
            if session.isDeletingAccount {
                ZStack {
                    Color.black.opacity(0.18).ignoresSafeArea()
                    ProgressView().tint(CheckMedTheme.primary)
                }
            }
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(.caption, design: .rounded).weight(.bold)).foregroundStyle(CheckMedTheme.muted)
            Text(value).font(.system(.body, design: .rounded).weight(.heavy))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct HelpSupportScreen: View {
    var go: (AppRoute) -> Void
    @Environment(SessionStore.self) private var session

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(session.t(.profileHelpTitle))
                            .font(.system(.title2, design: .rounded).weight(.black))
                        Text(session.t(.profileHelpBody))
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(CheckMedTheme.muted)
                    }
                    Spacer()
                    CooperLibraryImage(asset: "phil_wink", size: 88)
                }
                Link(destination: CheckMedPublicWeb.siteURL) {
                    labelRow("globe", session.t(.profileVisitSite), CheckMedPublicWeb.siteHost)
                }
                Link(destination: CheckMedPublicWeb.supportURL) {
                    labelRow("questionmark.circle.fill", session.t(.profileSupportPage), CheckMedPublicWeb.supportURL.host ?? CheckMedPublicWeb.siteHost)
                }
                Link(destination: CheckMedPublicWeb.supportMailto) {
                    labelRow("envelope.fill", session.t(.profileTalkToUs), CheckMedPublicWeb.supportEmail)
                }
                Button { go(.privacyPolicy) } label: { labelRow("hand.raised.fill", session.t(.privacyPolicyTitle), "") }
                Button { go(.termsOfUse) } label: { labelRow("doc.text.fill", session.t(.termsOfUseTitle), "") }
                Text(session.t(.profileDeleteGuidance))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)
                CheckMedButton(title: session.t(.profileSecurityAccount), style: .secondary) { go(.securityAccount) }
                ProfileChrome.tabBarScrollClearance
            }
            .padding(16)
        }
        .background(CheckMedTheme.background)
        .navigationTitle(session.t(.profileHelpTitle))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func labelRow(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(CheckMedTheme.primaryShadow)
            VStack(alignment: .leading) {
                Text(title).font(.system(.body, design: .rounded).weight(.heavy)).foregroundStyle(CheckMedTheme.ink)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(.caption, design: .rounded).weight(.semibold)).foregroundStyle(CheckMedTheme.muted)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(CheckMedTheme.muted)
        }
        .padding(14)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
