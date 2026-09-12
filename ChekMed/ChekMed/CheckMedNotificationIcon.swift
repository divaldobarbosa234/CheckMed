import UIKit
import UniformTypeIdentifiers
import UserNotifications

/// Extra Phil image on the right of a banner. The left slot is always the real App Icon —
/// do not use communication intents there or iOS replaces it with an empty placeholder.
enum CheckMedNotificationIcon {
    static func decorate(_ content: UNMutableNotificationContent) -> UNMutableNotificationContent {
        if let attachment = makeAttachment() {
            content.attachments = [attachment]
        }
        return content
    }

    private static func makeAttachment() -> UNNotificationAttachment? {
        guard let data = pngData() else { return nil }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("checkmed-notification-icon", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("phil-\(UUID().uuidString).png")
        do {
            try data.write(to: url, options: .atomic)
            return try UNNotificationAttachment(
                identifier: "checkmed.phil.\(UUID().uuidString)",
                url: url,
                options: [UNNotificationAttachmentOptionsTypeHintKey: UTType.png.identifier]
            )
        } catch {
            return nil
        }
    }

    private static func pngData() -> Data? {
        if let url = Bundle.main.url(forResource: "CheckMedNotificationPhil", withExtension: "png"),
           let data = try? Data(contentsOf: url),
           !data.isEmpty {
            return data
        }
        return UIImage(named: "CheckMedNotificationPhil")?.pngData()
    }
}
