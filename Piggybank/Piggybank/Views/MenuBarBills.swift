import SwiftUI
import SwiftData
import AppKit
import ServiceManagement

/// What the menu bar item shows beside the icon: how many bills and repeating transactions are due within three days or
/// overdue.
struct MenuBarLabel: View {
    @Query private var allBills: [Bill]
    @Query private var allRules: [RecurringTransaction]

    var body: some View {
        let soon = Bills.upcoming(allBills.live, days: 3).count + Recurring.upcoming(allRules.live, days: 3).count
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

/// The menu bar item's pop-up: important bills due in the next 30 days at the top, then the rest of this month's bills.
/// Works with no window open.
struct MenuBarBills: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allBills: [Bill]
    @Query private var allRules: [RecurringTransaction]
    @State private var contentHeight: CGFloat = 400

    private static let windowDays = 30
    private static let maxHeight: CGFloat = 640

    var body: some View {
        let bills = allBills.live
        let upcoming = Bills.upcoming(bills, days: Self.windowDays)
        // Important bills lead, and look 30 days ahead. Everything else is just this calendar month.
        let monthEnd = Calendar.current.dateInterval(of: .month, for: .now)?.end ?? .distantFuture
        let monthName = Date.now.formatted(.dateTime.month(.wide))
        let important = upcoming.filter(\.bill.isImportant)
        let others = upcoming.filter { !$0.bill.isImportant && $0.date < monthEnd }
        let alertIDs = Set(Bills.alerts(bills).map(\.id))
        let needsAttention = important.contains { !$0.isPaid && ($0.isOverdue || alertIDs.contains($0.id)) }

        let shown = important + others
        let open = shown.filter { !$0.isPaid }.sorted { $0.date < $1.date }
        let dueTotal = open.reduce(Decimal(0)) { $0 + $1.bill.amount }
        let overdue = open.filter(\.isOverdue).count
        let next = open.first { !$0.isOverdue } ?? open.first
        let repeating = Recurring.upcoming(allRules.live, days: Self.windowDays)

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
                    Text("Oinkly Budget")
                        .font(.system(size: 18, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(open.isEmpty
                         ? (repeating.isEmpty ? "Nothing due in \(monthName)" : "\(repeating.count) repeating coming up")
                         : "\(open.count) bill\(open.count == 1 ? "" : "s") to pay" + (repeating.isEmpty ? "" : " · \(repeating.count) repeating"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if !open.isEmpty {
                HStack(spacing: 10) {
                    stat("To pay", dueTotal.formatted(.appCurrency),
                         color: .primary)
                    stat(overdue > 0 ? "Overdue" : "Next bill",
                         overdue > 0 ? "\(overdue) bill\(overdue == 1 ? "" : "s")"
                             : (next.map { $0.date.formatted(.dateTime.month(.abbreviated).day()) } ?? "None"),
                         color: overdue > 0 ? Theme.red : .primary)
                }
            }

            if !important.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Important · next 30 days", systemImage: needsAttention ? "exclamationmark.triangle.fill" : "star.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.orange)
                    ForEach(important) { row($0, highlight: true) }
                }
                .padding(12)
                .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("THIS MONTH · \(monthName.uppercased())")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                if others.isEmpty {
                    Text(bills.isEmpty ? "No bills yet. Add some in Oinkly Budget ▸ Bills."
                         : (important.isEmpty ? "Nothing else due in \(monthName)." : "No other bills due in \(monthName)."))
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(others) { row($0, highlight: false) }
                }
            }

            if !repeating.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("REPEATING · NEXT \(Self.windowDays) DAYS")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ForEach(repeating) { repeatingRow($0) }
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

    /// One date of a repeating transaction. One that waits for you ("Reminder only") has a button to add it now.
    @ViewBuilder
    private func repeatingRow(_ item: Recurring.Occurrence) -> some View {
        if item.rule.isLive {
            HStack(spacing: 10) {
                if item.kind == .due {
                    Button {
                        Recurring.makeEntry(for: item.rule, on: item.date, in: modelContext)
                        Recurring.advance(item.rule)
                        modelContext.saveNow()
                        Task { await BillNotifier.refresh(in: modelContext) }
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 18))
                            .foregroundStyle(item.isOverdue ? Theme.red : Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Add it now")
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.rule.payee).font(.system(size: 15))
                    Text(repeatingWhen(item))
                        .font(.system(size: 12))
                        .foregroundStyle(item.isOverdue ? Theme.red : Color.secondary)
                }
                Spacer()
                Text(item.rule.amount, format: .appCurrency).font(.system(size: 15, weight: .semibold))
            }
        }
    }

    private func repeatingWhen(_ item: Recurring.Occurrence) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: item.date).day ?? 0
        switch days {
        case ..<0: return "Waiting since \(item.date.formatted(.dateTime.month(.abbreviated).day()))"
        case 0: return item.kind == .due ? "Waiting for you today" : "Today"
        case 1: return "Tomorrow"
        default: return "\(item.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · in \(days) days"
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
            Toggle("Show Oinkly Budget in the menu bar", isOn: $showInMenuBar)
            Toggle("Open Oinkly Budget when I log in", isOn: Binding(
                get: { opensAtLogin },
                set: { setLogin($0) }
            ))
            if let loginError {
                Text(loginError).font(.footnote).foregroundStyle(.orange)
            }
        } header: {
            Text("Background")
        } footer: {
            Text("The menu bar item shows your upcoming bills. Closing the window leaves Oinkly Budget running so the item stays; open the window again from the Dock, and quit with ⌘Q. Turn on opening at login to have it ready when you start your Mac.")
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
