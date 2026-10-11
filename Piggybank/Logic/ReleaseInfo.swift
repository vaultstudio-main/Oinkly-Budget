import Foundation

/// Which platforms have been released. The code for iPhone and iPad is already in the project and builds, but the first
/// release is Mac only, so anything the Mac app tells the user must not promise the others yet.
///
/// When iPhone and iPad ship, change `mobileReleased` to `true`. That brings back the mobile wording in About and the
/// Release Notes. Builds that run on iPhone or iPad always show it.
enum ReleaseInfo {
    static let mobileReleased = false

    /// Whether to mention iPhone and iPad in text.
    static var mentionsMobile: Bool {
        #if os(iOS)
        true
        #else
        mobileReleased
        #endif
    }

    /// "Mac" for now, "Mac, iPhone or iPad" once mobile ships.
    static var devicesPhrase: String { mentionsMobile ? "Mac, iPhone or iPad" : "Mac" }
}
