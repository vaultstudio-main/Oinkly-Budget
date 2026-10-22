import Foundation

/// The version people see, the build's name and the build number.
///
/// The App Store needs the build number to be a plain number that goes up with every upload, so it can't be a name.
/// Each build also has a name (the OINKLY_BUILD_NAME setting in the project) that is easy to remember. About and
/// Settings show the version, the name and the number together, such as "Version 1.0 · Ridiculous Speed · build 5".
enum AppVersion {
    /// Such as "1.0".
    static var display: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    /// Such as "Version 1.0".
    static var label: String { "Version \(display)" }

    /// The build's name, such as "Ridiculous Speed". Nil when none is set.
    static var buildName: String? {
        guard let name = Bundle.main.infoDictionary?["OinklyBuildName"] as? String,
              !name.isEmpty, !name.hasPrefix("$(") else { return nil }
        return name
    }

    /// Such as "build 2".
    static var buildNumber: String {
        "build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")"
    }

    /// Such as "Ridiculous Speed · build 2". What Settings shows beside Build.
    static var buildLabel: String {
        [buildName, buildNumber].compactMap { $0 }.joined(separator: " · ")
    }

    /// Such as "Version 1.0 · Ridiculous Speed · build 5". What About shows.
    static var fullLabel: String { [label, buildLabel].joined(separator: " · ") }
}
