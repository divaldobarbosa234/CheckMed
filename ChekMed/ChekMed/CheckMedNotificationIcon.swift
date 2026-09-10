import UniformTypeIdentifiers
import UserNotifications
import UIKit

/// Phil / App Icon thumbnail for local notification banners (expanded view + collapsed image).
enum CheckMedNotificationIcon {
    static func apply(to content: UNMutableNotificationContent) {
        if let attachment = attachment() {
            content.attachments = [attachment]
        }
    }

    private static func attachment() -> UNNotificationAttachment? {
        if let url = Bundle.main.url(forResource: "CheckMedNotificationPhil", withExtension: "png"),
           let attachment = try? UNNotificationAttachment(
            identifier: "checkmed.phil",
            url: url,
            options: [UNNotificationAttachmentOptionsTypeHintKey: UTType.png.identifier]
           ) {
            return attachment
        }

        guard let image = UIImage(named: "AppIcon") ?? UIImage(named: "CheckMedNotificationPhil"),
              let data = image.pngData()
        else { return nil }

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("checkmed-notification-icon", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("phil-\(UUID().uuidString).png")
        do {
            try data.write(to: url, options: .atomic)
            return try UNNotificationAttachment(
                identifier: "checkmed.phil",
                url: url,
                options: [UNNotificationAttachmentOptionsTypeHintKey: UTType.png.identifier]
            )
        } catch {
            return nil
        }
    }
}
