import Foundation

/// In-app legal copy aligned with the published Conny Cooper pages
/// (`https://connycooper.com/privacy/`, `/terms/`, `/legal/`, `/support/`).
/// Do not invent legal identity, addresses, prices, or URLs.
enum LegalDocumentKind: String, Hashable, Identifiable {
    case privacyPolicy
    case termsOfUse

    var id: String { rawValue }

    var document: LegalDocument {
        switch self {
        case .privacyPolicy: LegalContent.privacyPolicy
        case .termsOfUse: LegalContent.termsOfUse
        }
    }

    var officialURL: URL {
        switch self {
        case .privacyPolicy: CheckMedPublicWeb.privacyURL
        case .termsOfUse: CheckMedPublicWeb.termsURL
        }
    }
}

struct LegalDocument {
    let title: String
    let lastUpdatedLine: String
    let blocks: [LegalBlock]
}

struct LegalBlock: Identifiable {
    enum Kind {
        case heading
        case paragraph
        case labeled
        case stacked
    }

    let id: String
    let kind: Kind
    let title: String
    let body: String
    let lines: [String]

    static func heading(_ title: String, id: String) -> LegalBlock {
        LegalBlock(id: id, kind: .heading, title: title, body: "", lines: [])
    }

    static func paragraph(_ body: String, id: String) -> LegalBlock {
        LegalBlock(id: id, kind: .paragraph, title: "", body: body, lines: [])
    }

    static func labeled(label: String, value: String, id: String) -> LegalBlock {
        LegalBlock(id: id, kind: .labeled, title: label, body: value, lines: [])
    }

    static func stacked(_ lines: [String], id: String) -> LegalBlock {
        LegalBlock(id: id, kind: .stacked, title: "", body: "", lines: lines)
    }
}

enum LegalContent {
    static let privacyPolicy = LegalDocument(
        title: "Privacy Policy",
        lastUpdatedLine: "Effective date: 4 October 2026",
        blocks: [
            .paragraph(
                "This policy explains how personal information is handled when you use the Conny Cooper app, website and support services. The official page is https://connycooper.com/privacy/",
                id: "pp-intro"
            ),
            .heading("Who we are", id: "pp-who-h"),
            .paragraph(
                "Conny Cooper is operated by Divaldo Magalhães Lucas, an individual operator established in Spain. For data-protection purposes, Divaldo Magalhães Lucas is the controller of personal information processed for Conny Cooper.",
                id: "pp-who"
            ),
            .stacked(
                [
                    "Divaldo Magalhães Lucas",
                    "Calle Nebrija 9, Valladolid, Spain",
                    "NIF: Z51668279E",
                    "support@connycooper.com",
                ],
                id: "pp-controller-lines"
            ),
            .heading("Scope and age", id: "pp-scope-h"),
            .paragraph(
                "This policy applies to the Conny Cooper iOS app, the website at connycooper.com, and related support. Conny Cooper is available worldwide and is intended for people aged 16 or older. There is no guest or anonymous account.",
                id: "pp-scope"
            ),
            .heading("What information may we collect?", id: "pp-collect-h"),
            .labeled(
                label: "Account and profile:",
                value: "user identifier, email where supplied, display name or nickname, date of birth, language, time zone, pronouns or gender, and optional family-seat information. You can sign in using Apple, Google, or email and password. Supabase provides authentication and cloud account services.",
                id: "pp-collect-account"
            ),
            .labeled(
                label: "Medication and treatment:",
                value: "treatments, medicine core fields, treatment dates, dose schedules, and dose logs or statuses synchronised through Supabase. Additional medicine details, notes, refill or stock details, reward records, local community notes, and original prescription images or PDFs may remain on your device.",
                id: "pp-collect-meds"
            ),
            .labeled(
                label: "Support communications:",
                value: "contact details and information you include so that we can respond to and manage your request.",
                id: "pp-collect-support"
            ),
            .heading("Prescription scanning", id: "pp-ocr-h"),
            .paragraph(
                "Camera images and photos are processed on the device using Apple Vision. PDFs are processed using PDFKit and on-device Apple Vision. Manual entry does not use OCR. Original prescription images and PDFs are not uploaded to Supabase for OCR. You are responsible for checking extracted information before relying on it.",
                id: "pp-ocr"
            ),
            .heading("Health information", id: "pp-health-h"),
            .paragraph(
                "Medication and treatment information can constitute information concerning health under applicable data-protection law. We process this information only to provide the features you choose to use and on an appropriate legal basis, including explicit consent where applicable.",
                id: "pp-health"
            ),
            .heading("How we use information", id: "pp-why-h"),
            .paragraph(
                "To create and maintain your account; provide medication and treatment-organisation features; synchronise supported account-linked information; provide configured reminders and alarms on your device; provide optional nearby-pharmacy search; manage Conny Cooper Super access and purchase restoration; provide support and respond to privacy requests; protect the service; and comply with legal obligations.",
                id: "pp-why"
            ),
            .heading("Purchases", id: "pp-buy-h"),
            .paragraph(
                "Conny Cooper Super purchases and restores are handled by Apple through StoreKit. Conny Cooper receives the purchase or entitlement information needed to provide and restore access, but does not directly receive or store your payment-card information.",
                id: "pp-buy"
            ),
            .heading("Medical disclaimer", id: "pp-disclaimer-h"),
            .paragraph(
                "Conny Cooper is not a doctor, pharmacist, diagnostic service or emergency service and does not replace a qualified healthcare professional. Users should not change, stop or start medication based solely on information in the app. Emergencies require local emergency services.",
                id: "pp-disclaimer"
            ),
            .heading("Service providers", id: "pp-providers-h"),
            .paragraph(
                "Supabase provides authentication, account profiles, supported medication-data synchronisation and account deletion. Apple provides Sign in with Apple, StoreKit, on-device Vision and PDFKit, local notifications, AlarmKit, and MapKit where used. Google provides Google Sign-In when you select that method. Google is not used as an OCR recipient in the current release.",
                id: "pp-providers"
            ),
            .heading("Retention, deletion and rights", id: "pp-rights-h"),
            .paragraph(
                "Account-linked information is retained while needed to provide your account and the service, and as otherwise required or permitted by law. You can initiate permanent deletion in the app: Profile → Delete account & data. Signing out is not account deletion. Privacy requests: support@connycooper.com. You may complain to the Spanish Data Protection Agency where it is the competent authority.",
                id: "pp-rights"
            ),
            .heading("No advertising or cross-app tracking", id: "pp-ads-h"),
            .paragraph(
                "The current release does not include advertising SDKs, cross-app tracking, App Tracking Transparency tracking, analytics SDKs, crash-reporting SDKs or behavioural advertising. Local analytics or marketing preference controls do not, by themselves, send analytics or marketing data.",
                id: "pp-ads"
            ),
            .heading("Contact", id: "pp-contact-h"),
            .paragraph(
                "Privacy questions and requests: support@connycooper.com. Also see https://connycooper.com/privacy/ and the Legal Notice at https://connycooper.com/legal/",
                id: "pp-contact"
            ),
        ]
    )

    static let termsOfUse = LegalDocument(
        title: "Terms of Use",
        lastUpdatedLine: "Effective date: 4 October 2026",
        blocks: [
            .paragraph(
                "These terms apply to your account and use of the Conny Cooper app, website, support services and Conny Cooper Super. The official page is https://connycooper.com/terms/",
                id: "tou-intro"
            ),
            .heading("1. Operator", id: "tou-1-h"),
            .paragraph(
                "Conny Cooper is operated by Divaldo Magalhães Lucas, an individual operator established in Spain. Contact: support@connycooper.com. Further operator information appears in the Legal Notice at https://connycooper.com/legal/",
                id: "tou-1"
            ),
            .heading("2. Acceptance, Apple terms and age", id: "tou-2-h"),
            .paragraph(
                "By creating an account or using Conny Cooper, you agree to these Terms of Use and the Apple Standard End User License Agreement. You must be at least 16 years old. There is no child-account or parental-consent account system.",
                id: "tou-2"
            ),
            .heading("3. Accounts", id: "tou-3-h"),
            .paragraph(
                "Conny Cooper requires an account. You may sign in with Apple, Google, or email and password. You must provide accurate information and keep account access secure.",
                id: "tou-3"
            ),
            .heading("4. Not medical advice or an emergency service", id: "tou-4-h"),
            .paragraph(
                "Conny Cooper is a medication and treatment organisation companion. Cooper is a companion character, not a clinician. The app does not provide diagnosis, prescribing or clinical decisions. Do not use it for emergency assistance. Contact local emergency services in an emergency.",
                id: "tou-4"
            ),
            .heading("5. Medication information and OCR", id: "tou-5-h"),
            .paragraph(
                "You are responsible for checking information you enter or import. Prescription scanning uses on-device text extraction and can be incomplete or inaccurate. Review and confirm extracted information against the original prescription and your qualified healthcare professional’s instructions.",
                id: "tou-5"
            ),
            .heading("6. Conny Cooper Super", id: "tou-6-h"),
            .paragraph(
                "Conny Cooper Super provides premium features through Apple in-app purchases. Available subscriptions, billing periods, current prices, and any trial or promotion are shown by Apple before purchase. These terms do not set a price because displayed offers can vary by storefront and time. Apple processes payment and manages billing. Unless Apple states otherwise, subscriptions renew according to the terms shown at purchase. Manage or cancel through your Apple account settings and use Restore Purchases in the app where needed. Trials apply only where Apple offers them. Refunds are handled under Apple’s purchase terms and mandatory consumer law.",
                id: "tou-6"
            ),
            .heading("7. Account deletion", id: "tou-7-h"),
            .paragraph(
                "You can permanently delete your account from Profile → Delete account & data. Signing out does not delete your account.",
                id: "tou-7"
            ),
            .heading("8. Applicable law", id: "tou-8-h"),
            .paragraph(
                "These terms are governed by Spanish law. If you are a consumer, this choice does not deprive you of mandatory protections available under the law of your country of residence.",
                id: "tou-8"
            ),
            .heading("9. Contact", id: "tou-9-h"),
            .stacked(
                [
                    "Divaldo Magalhães Lucas",
                    "Calle Nebrija 9, Valladolid, Spain",
                    "NIF: Z51668279E",
                    "support@connycooper.com",
                    "https://connycooper.com/support/",
                ],
                id: "tou-contact"
            ),
        ]
    )
}
