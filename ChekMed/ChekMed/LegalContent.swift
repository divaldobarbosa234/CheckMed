import Foundation

/// Single source for lawyer-facing legal copy shown in the app.
///
/// Transcribed from `CheckMed_Legal_Draft_for_Cursor.pdf` (pre-launch draft).
/// Placeholders such as `[LEGAL COMPANY NAME]`, `[EMAIL]`, and `[ADDRESS]` are kept as-is.
/// Do not invent legal facts. UI chrome is localized separately in `L10n`.
///
/// LAWYER TODO — confirm before publication (from the draft checklist and counsel notes):
/// - Legal basis for every processing activity (GDPR / LOPDGDD)
/// - Health-data condition and, where applicable, explicit consent mechanism
/// - Consent wording for each processing activity
/// - Retention periods (account, prescriptions, uploads, support, technical/security logs)
/// - Data deletion / erasure process
/// - AI providers, data sent, processing locations, retention, model-training use, safeguards
/// - International transfers and transfer safeguards
/// - Analytics tools, legal basis, and disclosures (optional; never bundled with Accept)
/// - Marketing / advertising (optional; never bundled with Accept)
/// - Medical-device classification (intended purpose, claims, EU MDR)
/// - User age (`[AGE]`)
/// - Public Privacy Policy URL
/// - Terms wording, liability, jurisdiction, LSSI-CE / consumer / e-commerce
/// - DPIA/EIPD, App Store / Play health-data declarations, EU Health Data Space as the product evolves
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
    static let lastUpdatedPlaceholder = "[DATE]"

    static let privacyPolicy = LegalDocument(
        title: "Privacy Policy",
        lastUpdatedLine: "Last updated: [DATE]",
        blocks: [
            .paragraph(
                "CheckMed (\"CheckMed\", \"we\", \"us\", \"our\") respects your privacy and is committed to protecting your personal information.",
                id: "pp-intro-1"
            ),
            .paragraph(
                "This Privacy Policy explains how we collect, use, store and protect information when you use the CheckMed application and related services.",
                id: "pp-intro-2"
            ),
            .heading("Who is responsible for your data?", id: "pp-controller-h"),
            .labeled(
                label: "Data Controller:",
                value: "",
                id: "pp-controller-label"
            ),
            .stacked(
                [
                    "[LEGAL COMPANY NAME]",
                    "[COMPANY ADDRESS]",
                    "[NIF/CIF]",
                    "[EMAIL]",
                    "[DATA PROTECTION EMAIL]",
                ],
                id: "pp-controller-lines"
            ),
            .heading("What information may we collect?", id: "pp-collect-h"),
            .labeled(
                label: "Account information:",
                value: "name or nickname, email address, account credentials, language and app preferences.",
                id: "pp-collect-account"
            ),
            .labeled(
                label: "Prescription and medication information:",
                value: "photographs of prescriptions, uploaded PDFs, manually entered prescription information, medicine names, dosages, frequency, treatment duration, medication schedules and notes voluntarily added by the user.",
                id: "pp-collect-meds"
            ),
            .labeled(
                label: "Technical information:",
                value: "device type, operating system, app version, error/diagnostic information and security information, as applicable to the actual implementation.",
                id: "pp-collect-tech"
            ),
            .heading("How can you provide prescription information?", id: "pp-methods-h"),
            .paragraph(
                "Users may be able to take a photograph, upload a PDF, or enter information manually. The final policy must describe the actual processing performed for each method.",
                id: "pp-methods"
            ),
            .heading("Why do we use your information?", id: "pp-why-h"),
            .paragraph(
                "To provide core functionality; read and organize prescription information; create medication schedules; provide requested reminders; store information the user chooses to save; provide explanations and accessibility/voice features; maintain and secure the app; detect errors, abuse or security incidents; provide support; comply with legal obligations; and improve the app where legally permitted.",
                id: "pp-why"
            ),
            .heading("Health information", id: "pp-health-h"),
            .paragraph(
                "Prescription and medication information may constitute health data and therefore receives enhanced protection under applicable data-protection law. The final legal basis and, where applicable, explicit consent mechanism for each processing activity must be confirmed by counsel.",
                id: "pp-health"
            ),
            .heading("Artificial intelligence", id: "pp-ai-h"),
            .paragraph(
                "Some features may use AI or automated technologies to extract prescription information, organize medication data, generate explanations, or provide voice/conversational assistance. AI output may contain errors and should be verified against the original prescription, packaging and professional instructions. The final policy must identify actual AI providers, data flows, retention, training use, processing locations and safeguards.",
                id: "pp-ai"
            ),
            .heading("Medical disclaimer", id: "pp-disclaimer-h"),
            .paragraph(
                "CheckMed is designed to help users organize and understand information about their medications. It does not replace a doctor, pharmacist, nurse, emergency service or other qualified healthcare professional.",
                id: "pp-disclaimer-1"
            ),
            .paragraph(
                "Users should not change, stop or start medication based solely on information provided by CheckMed. Emergency situations require appropriate professional/emergency assistance.",
                id: "pp-disclaimer-2"
            ),
            .heading("Service providers and international transfers", id: "pp-transfers-h"),
            .paragraph(
                "Depending on the actual architecture, service providers may include cloud hosting, authentication, AI, analytics, customer support, security and notification providers. The final policy must list relevant providers and international-transfer safeguards where required.",
                id: "pp-transfers"
            ),
            .heading("Retention", id: "pp-retention-h"),
            .paragraph(
                "Personal information should be kept only as long as necessary for the relevant purpose or as required by law. Final retention periods must be completed for account data, prescriptions, uploaded documents, support communications and technical/security logs.",
                id: "pp-retention"
            ),
            .heading("User rights", id: "pp-rights-h"),
            .paragraph(
                "Depending on applicable law, users may have rights of access, rectification, erasure, restriction, objection, portability and withdrawal of consent where consent is the legal basis, as well as applicable rights concerning automated decision-making. Contact: [PRIVACY EMAIL].",
                id: "pp-rights"
            ),
            .heading("Security", id: "pp-security-h"),
            .paragraph(
                "CheckMed should implement appropriate technical and organizational measures, such as encryption, access controls, authentication, secure infrastructure, logging/monitoring, backups, security testing and data minimization, consistent with the actual system.",
                id: "pp-security"
            ),
            .heading("Children, changes and contact", id: "pp-children-h"),
            .paragraph(
                "CheckMed is intended for users aged [AGE] or older unless the final legal assessment states otherwise. The policy may be updated as the service changes. Contact: [LEGAL COMPANY NAME], [EMAIL], [ADDRESS], [NIF/CIF].",
                id: "pp-children"
            ),
        ]
    )

    static let termsOfUse = LegalDocument(
        title: "Terms of Use",
        lastUpdatedLine: "Last updated: [DATE]",
        blocks: [
            .heading("CHECKMED — TERMS OF USE", id: "tou-title"),
            .heading("1. What CheckMed does", id: "tou-1-h"),
            .paragraph(
                "CheckMed is a digital tool designed to help users organize prescription and medication information. Depending on available features, it may allow users to photograph prescriptions, upload PDFs, enter information manually, organize medication information, create schedules, receive reminders, listen to medication-related information, and receive AI-assisted explanations.",
                id: "tou-1"
            ),
            .heading("2. CheckMed is not a healthcare professional", id: "tou-2-h"),
            .paragraph(
                "CheckMed does not provide medical care. The application is not a doctor, pharmacist, nurse or emergency medical service and does not replace professional medical advice.",
                id: "tou-2"
            ),
            .heading("3. Accuracy of information", id: "tou-3-h"),
            .paragraph(
                "Prescription photographs, PDFs, manually entered information and AI-generated information may contain errors. Users should verify important medication information against the original prescription, packaging and instructions from a qualified healthcare professional or pharmacist.",
                id: "tou-3"
            ),
            .heading("4. Emergency situations", id: "tou-4-h"),
            .paragraph(
                "CheckMed is not an emergency service. Users experiencing potentially serious symptoms or a medical emergency should seek immediate professional/emergency assistance.",
                id: "tou-4"
            ),
            .heading("5. User responsibility", id: "tou-5-h"),
            .paragraph(
                "Users are responsible for providing accurate information, reviewing extracted information, keeping their account secure, checking medication instructions and following advice from qualified healthcare professionals.",
                id: "tou-5"
            ),
            .heading("6. Prescription processing", id: "tou-6-h"),
            .paragraph(
                "When a prescription is photographed or uploaded, CheckMed may use OCR and/or AI to extract information. Automated extraction can be incorrect and must be reviewed by the user.",
                id: "tou-6"
            ),
            .heading("7. AI-generated information", id: "tou-7-h"),
            .paragraph(
                "AI-generated content can be inaccurate, incomplete or misleading and should be treated as assistance/information rather than medical advice.",
                id: "tou-7"
            ),
            .heading("8. Availability", id: "tou-8-h"),
            .paragraph(
                "CheckMed aims to be reliable but cannot guarantee uninterrupted operation, absence of errors, correct interpretation of every prescription or correct generation of every reminder.",
                id: "tou-8"
            ),
            .heading("9. Accounts", id: "tou-9-h"),
            .paragraph(
                "Where accounts are required, users must provide accurate information and protect their credentials.",
                id: "tou-9"
            ),
            .heading("10. Prohibited use", id: "tou-10-h"),
            .paragraph(
                "Users must not use CheckMed unlawfully, attempt unauthorized access, interfere with security, reverse engineer where prohibited by law, upload malicious content, abuse automated systems, or misuse the service to provide professional medical services unless expressly authorized.",
                id: "tou-10"
            ),
            .heading("11. Intellectual property", id: "tou-11-h"),
            .paragraph(
                "CheckMed software, branding, designs, characters, logos, text and original content are owned by or licensed to [LEGAL COMPANY NAME], subject to applicable rights and exceptions.",
                id: "tou-11"
            ),
            .heading("12. Third-party services", id: "tou-12-h"),
            .paragraph(
                "CheckMed may depend on third-party services that have their own terms and privacy policies. The final version should identify relevant providers where required.",
                id: "tou-12"
            ),
            .heading("13. Subscriptions and payments", id: "tou-13-h"),
            .paragraph(
                "If paid subscriptions are introduced, additional terms covering pricing, billing, renewals, cancellation, refunds and platform payments will apply.",
                id: "tou-13"
            ),
            .heading("14. Liability", id: "tou-14-h"),
            .paragraph(
                "Any limitation of liability must comply with mandatory consumer and applicable law. This section requires specific legal review before publication, particularly because CheckMed handles health-related information.",
                id: "tou-14"
            ),
            .heading("15. Suspension or termination", id: "tou-15-h"),
            .paragraph(
                "Access may be suspended or terminated where reasonably necessary, including for security threats, abuse, fraud, violation of the Terms or legal requirements. Users may stop using the service at any time.",
                id: "tou-15"
            ),
            .heading("16. Changes to the service and Terms", id: "tou-16-h"),
            .paragraph(
                "CheckMed may evolve and features may be added, modified or removed. Material changes to the Terms will be communicated through appropriate means where required.",
                id: "tou-16"
            ),
            .heading("17. Applicable law and contact", id: "tou-17-h"),
            .paragraph(
                "The Terms should be governed by applicable Spanish and EU law, subject to mandatory consumer rights. The final jurisdiction clause must be reviewed by Spanish counsel.",
                id: "tou-17"
            ),
            .stacked(
                [
                    "[LEGAL COMPANY NAME]",
                    "[EMAIL]",
                    "[ADDRESS]",
                    "[NIF/CIF]",
                ],
                id: "tou-contact"
            ),
        ]
    )
}
