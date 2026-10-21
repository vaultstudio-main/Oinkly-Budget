import AppKit
import SwiftData

/// Where this Mac's own data file lives, and starting the app again.
@MainActor
enum AppStore {
    /// This Mac's own data file, as the app opens it when sharing is off.
    static func localStoreURL(for schema: Schema) -> URL {
        ModelConfiguration(schema: schema, groupContainer: .none, cloudKitDatabase: .none).url
    }

    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
