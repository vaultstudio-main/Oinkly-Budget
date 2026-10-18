import SwiftUI
import AppKit

/// Everything the About window says. Edit the text here; the layout below picks it up.
enum AboutInfo {
    /// Shown under the app name.
    static let tagline = "Your money, kept personal."

    /// A short paragraph about the app.
    static var summary: String {
        "OinklyBudget is a personal finance app that keeps accounts, budgets, bills and investments in your control."
    }

    /// Lines near the bottom, such as who made it. Remove a line to hide it.
    static let credits: [String] = [
        "Vault Studio",
        "Made by Donald Stibich",
    ]

    /// The studio's website, shown as a link under the credits.
    static let website = URL(string: "https://vaultstudio.dev")!
    static let websiteTitle = "vaultstudio.dev"

    /// Small print at the very bottom.
    static let copyright = "© 2026 Vault Studio. All rights reserved."
}

/// OinklyBudget ▸ About OinklyBudget. The text lives in `AboutInfo` above.
struct AboutWindow: View {
    private var version: String {
        // The build number isn't shown to the people using the app. Debug builds add the build's name.
        [AppVersion.label, AppVersion.developerBuild].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 112, height: 112)

            VStack(spacing: 4) {
                Text("OinklyBudget").lineLimit(1).minimumScaleFactor(0.6).font(.system(size: 28, weight: .bold, design: .rounded))
                Text(AboutInfo.tagline).foregroundStyle(.secondary)
                Text(version).font(.caption).foregroundStyle(.tertiary)
            }

            Text(AboutInfo.summary)
                .font(.callout)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if !AboutInfo.credits.isEmpty {
                VStack(spacing: 2) {
                    ForEach(AboutInfo.credits, id: \.self) { Text($0).font(.callout) }
                }
            }

            Link(destination: AboutInfo.website) {
                Label(AboutInfo.websiteTitle, systemImage: "globe")
                    .font(.callout)
            }
            .help("Open the Vault Studio website")

            Text(AboutInfo.copyright)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(28)
        .frame(width: 360)
        .background(Theme.background)
    }
}
