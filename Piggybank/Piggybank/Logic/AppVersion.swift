import Foundation

/// The version people see, and a build name only the developer sees.
///
/// The App Store needs the build number to be a plain number that goes up with every upload, so it can't be a name.
/// Instead each build also has a name (the OINKLY_BUILD_NAME setting in the project) that is easy to remember. It
/// is shown only in Debug builds, never in what ships, and the number is never shown to the people using the app.
enum AppVersion {
    /// Such as "1.1".
    static var display: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    /// Such as "Version 1.1".
    static var label: String { "Version \(display)" }

    /// Debug builds only: the build's name and number, such as "Acorn (build 2)". Nil in a shipping build.
    static var developerBuild: String? {
        #if DEBUG
        let info = Bundle.main.infoDictionary
        let name = info?["OinklyBuildName"] as? String
        let number = info?["CFBundleVersion"] as? String ?? "?"
        if let name, !name.isEmpty, !name.hasPrefix("$(") { return "\(name) (build \(number))" }
        return "build \(number)"
        #else
        return nil
        #endif
    }
}
