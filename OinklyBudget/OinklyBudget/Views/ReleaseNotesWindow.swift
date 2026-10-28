import SwiftUI

/// Everything the Release Notes window says. It lists only what is new in the version being shipped: when you ship the next one, replace the
/// release below with the new one. Earlier releases are in the project's GitHub releases and the website's Updates page.
enum ReleaseNotes {
    struct Release: Identifiable {
        let version: String
        let title: String
        let sections: [(heading: String, items: [String])]
        var id: String { version }
    }

    static let releases: [Release] = [
        Release(version: "1.1", title: "Laser Focused, You Idiot", sections: [
            ("Planning War Room", [
                "The Monthly Outlook page is now the Planning War Room, with four tabs: Strategy Plan, Monthly War Plan, Debt War Plan and Savings War Plan.",
                "The Strategy Plan counts the extra money your Debt and Savings War Plans set aside in Money Out, Left Over and Above the Buffer, and in the chart. A card says so. Closed months keep the figures they had.",
                "The Strategy Plan pulls in more from both plans: where the month's money goes, what you owe and what you save over time, a net position over time, when each debt is paid off, how each savings account grows, and what extra money does to your debt-free date and your savings.",
                "On the Monthly War Plan, Add a Line takes a payee, with suggestions from your register and the category each last had. A line can count towards your Debt or Savings War Plan, and the sheet adds those up. Link Transactions is gone.",
            ]),
            ("Debt War Plan", [
                "Laser Focus Annihilation joins Highest interest first and Smallest balance first: pick one debt and every extra dollar goes to it until it is gone, then its payment rolls on to the next.",
                "The box shows the debt-free date, time saved and interest saved for several extra amounts, and the extra each month it takes to be debt-free in 1, 2, 3, 5 or 10 years, with a Use button for each.",
                "Payments freed by a paid-off debt now roll onto the next one in every payoff calculation, the reports included.",
            ]),
            ("Savings War Plan", [
                "A new tab for saving up. Every savings account is grown month by month with its own rate and deposits. Add an extra amount, a one-time deposit or a total goal, pick where the extra goes, or point Laser Focus Annihilation at one account, and see when each account reaches its target.",
            ]),
            ("Receipt Verification", [
                "Scan a receipt while entering a transaction, or attach a PDF with text. The app reads it on this Mac and suggests corrections to the total, date and payee. Nothing changes until you press Use.",
                "The scan also finds the tax, the tip, the item count and how it was paid, and suggests a category, a payment method and a memo from them, each with its own Use button, a Use All and a way to turn one away. A blank field is offered the receipt's value and a different one is offered as a change; nothing is ever filled in on its own. It works in new transactions, credit card charges, cash transactions, edits, Pay a Bill and from the register's receipt link.",
                "It remembers which payee goes with which store, in a small file on this Mac that is not in backups. Erase All Data forgets it.",
            ]),
            ("PDF Letterhead", [
                "Printed and exported PDFs can have a letterhead across the top of the first page: none by default, or the Oinkly Budget pig and name, or your own logo, name and a line of details. It is chosen in Settings ▸ General ▸ Letterhead. Your logo stays on this Mac, outside backups.",
            ]),
            ("Saving files", [
                "Settings ▸ Data & Backup ▸ Backup Copy and Save Location has a switch, Use a default save location. Turn it on and choose a folder, and statements, reports and backups are saved straight into it with no save window, and a Backup Copy of your database starts there too. Turn it off to be asked each time. Erase Everything forgets the choice.",
            ]),
            ("Status bar", [
                "The two dots at the bottom of the window are now one. While you share your data it says Backup Copy & Shared when this Mac, the backup copy and the shared data are all saved, and it shows whichever needs attention first.",
            ]),
            ("Menu bar", [
                "The menu bar pop-up shows your upcoming bills and no longer has an Open Oinkly Budget button. Click the app in the Dock to open the window.",
            ]),
            ("Speed", [
                "The Investments reports open much faster. Their numbers are worked out a few seconds after the app starts and again after you change something, such as a price, so they are ready when you open the tab.",
            ]),
            ("Printing", [
                "Every account page has a new Print button beside Print PDF. It sends the statement for the period you choose to a real printer through the Mac's print window, with a preview. Print PDF still saves a PDF file.",
            ]),
            ("Updates", [
                "Oinkly Budget can now tell you when a new version is out. The second time you open it, it asks once whether to check for updates automatically. Say no and it never looks by itself. Oinkly Budget ▸ Check for Updates… and Settings ▸ General ▸ Updates look on request.",
                "When there is one, a window shows what is new and a link to the full release notes, and Install Update downloads it, installs it and reopens the app. Only an update signed with Oinkly Budget's own key is installed.",
                "A check reads one small list on vaultstudio.dev and sends only the app version and the macOS version, nothing about you or your money. It is the only thing the app does online. The download comes from the project's page on GitHub. Updates start with the release after 1.1, because 1.0.1 has no update check.",
            ]),
            ("Planning", [
                "The Loan Payoff Goals tab is gone, so Planning is only savings goals. Paying a debt down faster is the Debt War Plan in the Planning War Room. Loan payoff goals you made before are kept in your data but are no longer shown.",
                "Planning has an Archive tab. A savings goal you reach is congratulated for a few days on the Goals tab and then moves to the Archive tab, with the amount it finished at.",
            ]),
            ("Paid-off loans", [
                "A loan that reaches zero is archived, not deleted. Student loans and other loans archive themselves. For an auto loan or a mortgage, a sheet asks first and offers to add the car or house as an asset, with the worth starting at the original loan amount. When a lease ends, a sheet asks whether you bought the car out (the lease becomes a regular auto loan, or an asset if you paid for it) or returned it (the lease is archived). Archived accounts are left out of the side panel and listed on a new Archived tab in Manage Accounts, to look at only; their transactions are kept so net worth, debts and interest history stay right. At the end of each year the app asks whether to keep them or delete them.",
            ]),
            ("Charts", [
                "Every circle graph is now a bar or line chart, so amounts and shares are easy to compare.",
            ]),
        ]),
    ]
}

/// Help ▸ Release Notes. What is new in this version, as bullet points.
struct ReleaseNotesWindow: View {
    private var currentVersion: String { AppVersion.fullLabel }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Release Notes").font(.largeTitle.bold())
                    Text("You are running \(currentVersion)").foregroundStyle(.secondary)
                }

                // A look at the app, from the same screenshot the Help uses.
                if let image = NSImage(named: "Help-welcome") {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 560)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                }

                ForEach(ReleaseNotes.releases) { release in
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Version \(release.version) · \(release.title)").font(.title2.bold())
                        ForEach(Array(release.sections.enumerated()), id: \.offset) { _, section in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(section.heading).font(.headline)
                                ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text("•")
                                        Text(item).fixedSize(horizontal: false, vertical: true)
                                    }
                                    .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .frame(minWidth: 520, minHeight: 420)
    }
}
