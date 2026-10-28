import Foundation
import Observation
#if canImport(Sparkle)
import Sparkle
#endif

/// Looks for new versions of Oinkly Budget on GitHub, with Sparkle. It is off in a Debug build (the one Xcode runs), which never updates itself.
/// Sparkle asks once, on the second launch, whether to check automatically, and checks only if the answer is yes. A check sends only the app's
/// version and the macOS version, and an update is installed only if it is signed with this app's own key, so a changed download is refused.
/// Check for Updates… in the app menu, and Settings ▸ General ▸ Updates, can look at any time.
@MainActor
@Observable
final class AppUpdater: NSObject {
    static let shared = AppUpdater()

    /// Whether this build can update itself at all. False in a Debug build unless a test feed was given.
    private(set) var isAvailable = false
    /// Whether a check can be started right now (not while one is already running).
    private(set) var canCheck = false

    #if canImport(Sparkle)
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observation: NSKeyValueObservation?
    #endif

    /// Starts looking after launch. In a Debug build this does nothing unless `-sparkleTestFeed <address>` is given, which points the checks at a
    /// local test feed.
    func start() {
        #if canImport(Sparkle)
        #if DEBUG
        guard UserDefaults.standard.string(forKey: "sparkleTestFeed") != nil else { return }
        #endif
        guard controller == nil else { return }
        let made = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        controller = made
        isAvailable = true
        observation = made.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let can = updater.canCheckForUpdates
            Task { @MainActor in self?.canCheck = can }
        }
        #endif
    }

    /// Asks GitHub whether there is a newer version, and shows Sparkle's window with the answer.
    func checkForUpdates() {
        #if canImport(Sparkle)
        controller?.checkForUpdates(nil)
        #endif
    }

    /// Whether Sparkle checks by itself. It starts unset, and Sparkle asks on the second launch.
    var automaticChecks: Bool {
        get {
            #if canImport(Sparkle)
            controller?.updater.automaticallyChecksForUpdates ?? false
            #else
            false
            #endif
        }
        set {
            #if canImport(Sparkle)
            controller?.updater.automaticallyChecksForUpdates = newValue
            #endif
        }
    }
}

#if canImport(Sparkle)
extension AppUpdater: SPUUpdaterDelegate {
    #if DEBUG
    /// A Debug build checks a local test feed instead of GitHub. A Release build never does: it always uses the address in its Info.plist.
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        UserDefaults.standard.string(forKey: "sparkleTestFeed")
    }
    #endif
}
#endif
