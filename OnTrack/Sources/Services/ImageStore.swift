import UIKit

/// Stores food photos on disk (Documents/FoodImages). Image blobs are kept OUT
/// of SwiftData/CloudKit — only the filename is persisted on the FoodItem, so
/// sync stays lean. Images are device-local; on another synced device the
/// thumbnail falls back to an icon.
enum ImageStore {
    private static var directory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FoodImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Saves JPEG data; returns the filename to store on the model (nil on failure).
    static func save(_ jpeg: Data) -> String? {
        let name = UUID().uuidString + ".jpg"
        do {
            try jpeg.write(to: directory.appendingPathComponent(name))
            return name
        } catch {
            return nil
        }
    }

    static func load(_ name: String) -> UIImage? {
        UIImage(contentsOfFile: directory.appendingPathComponent(name).path)
    }

    static func delete(_ name: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }
}
