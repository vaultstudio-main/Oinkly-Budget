import AppKit

/// The folder every save window opens in, when the person has chosen one in Settings ▸ General. Without one, macOS opens the window where
/// it did last time. Only the choice is kept (as a bookmark, so it still works if the folder is renamed or moved); nothing is saved
/// anywhere until the person presses Save.
@MainActor
enum DefaultSaveFolder {
    private static let bookmarkKey = "defaultSaveFolderBookmark"
    private static let nameKey = "defaultSaveFolderName"

    /// The chosen folder, when there is one and it still exists.
    static var url: URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        if stale { remember(url) }
        return url
    }

    /// What Settings shows for the choice: the folder's name, or nil when none is chosen.
    static var displayName: String? { url == nil ? nil : UserDefaults.standard.string(forKey: nameKey) }

    static func remember(_ folder: URL) {
        guard let data = try? folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        UserDefaults.standard.set(data, forKey: bookmarkKey)
        UserDefaults.standard.set(folder.lastPathComponent, forKey: nameKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: nameKey)
    }

    /// Asks which folder to use. Returns false when the window was cancelled.
    @discardableResult
    static func choose() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Folder"
        panel.message = "Choose the folder save windows should open in."
        panel.directoryURL = url
        guard panel.runModal() == .OK, let folder = panel.url else { return false }
        remember(folder)
        return true
    }

    /// Writes a file straight into the chosen folder, with no save window, and returns where it went. Nil when no folder is chosen (or it
    /// can't be found), so the caller asks with a save window as before. A name that is already taken gets " 2", " 3" and so on, so
    /// nothing is ever replaced.
    static func save(named name: String, _ write: (URL) throws -> Void) throws -> URL? {
        guard let folder = url else { return nil }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        let clean = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let base = (clean as NSString).deletingPathExtension, ext = (clean as NSString).pathExtension
        var target = folder.appendingPathComponent(clean)
        var count = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(count)" : "\(base) \(count).\(ext)")
            count += 1
        }
        try write(target)
        return target
    }
}
