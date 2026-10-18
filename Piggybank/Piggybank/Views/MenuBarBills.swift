import SwiftUI
import SwiftData
import AppKit
import ServiceManagement

/// What the menu bar item shows beside the icon: how many bills are due within three days or overdue.
struct MenuBarLabel: View {
    @Query private var allBills: [Bill]

    var body: some View {
        let soon = Bills.upcoming(allBills.live, days: 3).count
        // The pig from the app icon as a one-color silhouette, so it matches light and dark menu bars.
        if soon > 0 {
            Label {
                Text("\(soon)")
            } icon: {
                Image("MenuBarPig")
            }
        } else {
            Image("MenuBarPig")
        }
    }
}

/// The menu bar item's pop-up: important bills at the top, then everything due in the next 30 days. Works with no window open.
struct MenuBarBills: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allBills: [Bill]
    @State private var contentHeight: CGFloat = 400

    private static let windowDays = 30
    private static let maxHeight: CGFloat = 640

    var body: some View {
        let bills = allBills.live
        let upcoming = Bills.upcoming(bills, days: Self.windowDays)
        // Important bills lead; the rest follow in date order.
        let important = upcoming.filter(\.bill.isImportant)
        let others = upcoming.filter { !$0.bill.isImportant }
        let alertIDs = Set(Bills.alerts(bills).map(\.id))
        let needsAttention = important.contains { !$0.isPaid && ($0.isOverdue || alertIDs.contains($0.id)) }

        let open = upcoming.filter { !$0.isPaid }
        let dueTotal = open.reduce(Decimal(0)) { $0 + $1.bill.amount }
        let overdue = open.filter(\.isOverdue).count
        let next = open.first { !$0.isOverdue } ?? open.first

        // Fixed point sizes, so the pop-up looks the same however the system sizes menu bar windows.
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Theme.green.gradient, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("OinklyBudget")
                        .font(.system(size: 18, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(open.isEmpty
                         ? "Nothing due in the next 30 days"
                         : "\(open.count) bill\(open.count == 1 ? "" : "s") due in the next 30 days")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if !open.isEmpty {
                HStack(spacing: 10) {
                    stat("Due soon", dueTotal.formatted(.appCurrency),
                         color: .primary)
                    stat(overdue > 0 ? "Overdue" : "Next bill",
                         overdue > 0 ? "\(overdue) bill\(overdue == 1 ? "" : "s")"
                             : (next.map { $0.date.formatted(.dateTime.month(.abbreviated).day()) } ?? "None"),
                         color: overdue > 0 ? Theme.red : .primary)
                }
            }

            if !important.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Important bills", systemImage: needsAttention ? "exclamationmark.triangle.fill" : "star.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.orange)
                    ForEach(important) { row($0, highlight: true) }
                }
                .padding(12)
                .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("COMING UP · NEXT 30 DAYS")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                if others.isEmpty {
                    Text(bills.isEmpty ? "No bills yet. Add some in OinklyBudget ▸ Bills."
                         : (important.isEmpty ? "Nothing due in the next 30 days." : "No other bills in the next 30 days."))
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(others) { row($0, highlight: false) }
                }
            }
        }
        .padding(18)
        .frame(width: 400)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        // Tall lists scroll inside the pop-up instead of running off the screen.
        .frame(width: 400, height: min(max(contentHeight, 160), Self.maxHeight))
    }

    private func stat(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func row(_ item: Bills.Occurrence, highlight: Bool) -> some View {
        if item.bill.isLive {
            HStack(spacing: 10) {
                Button {
                    item.bill.setPaid(true, on: item.date)
                    modelContext.saveNow()
                    Task { await BillNotifier.refresh(in: modelContext) }
                } label: {
                    Image(systemName: "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(item.isOverdue ? Theme.red : Color.secondary)
                }
                .buttonStyle(.plain)
                .help("Mark as paid")

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.bill.name).font(.system(size: 15))
                    Text(when(item))
                        .font(.system(size: 12))
                        .foregroundStyle(item.isOverdue ? Theme.red : Color.secondary)
                }
                Spacer()
                Text(item.bill.amount, format: .appCurrency).font(.system(size: 15, weight: .semibold))
            }
        }
    }

    private func when(_ item: Bills.Occurrence) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: item.date).day ?? 0
        switch days {
        case ..<0: return "Overdue by \(-days) day\(days == -1 ? "" : "s")"
        case 0: return "Due today"
        case 1: return "Due tomorrow"
        default: return "\(item.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · in \(days) days"
        }
    }
}

/// The background switches in Settings: menu bar item, staying open, and starting at login.
struct BackgroundSettingsSection: View {
    static let showMenuBarKey = "showMenuBarItem"

    @AppStorage(BackgroundSettingsSection.showMenuBarKey) private var showInMenuBar = true
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Section {
            Toggle("Show OinklyBudget in the menu bar", isOn: $showInMenuBar)
            Toggle("Open OinklyBudget when I log in", isOn: Binding(
                get: { opensAtLogin },
                set: { setLogin($0) }
            ))
            if let loginError {
                Text(loginError).font(.footnote).foregroundStyle(.orange)
            }
        } header: {
            Text("Background")
        } footer: {
            Text("The menu bar item shows your upcoming bills. Closing the window leaves OinklyBudget running so the item stays; open the window again from the Dock, and quit with ⌘Q. Turn on opening at login to have it ready when you start your Mac.")
        }
    }

    private func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't change this: \(error.localizedDescription)"
        }
        opensAtLogin = SMAppService.mainApp.status == .enabled
    }
}
