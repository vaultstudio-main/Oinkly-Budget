import SwiftUI
import SwiftData
import AppKit
import ServiceManagement

/// What the menu bar item shows beside the icon: how many bills and repeating transactions are due within three days or
/// overdue.
struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow
    @Query private var allBills: [Bill]
    @Query private var allRules: [RecurringTransaction]

    var body: some View {
        let soon = Bills.upcoming(allBills.live, days: 3).count + Recurring.upcoming(allRules.live, days: 3).count
        // The pig from the app icon as a one-color silhouette, so it matches light and dark menu bars.
        Group {
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
        // This item is always there, so it is what opens the window when a reminder or the widget needs one.
        .onReceive(NotificationCenter.default.publisher(for: .piggybankNeedsMainWindow)) { _ in
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }
    }
}

/// The menu bar item's pop-up: everything due this month in one list, bills and repeating transactions together, each
/// marked as one or the other, with the date and how many days away it is. Works with no window open.
struct MenuBarBills: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Query private var allBills: [Bill]
    @Query private var allRules: [RecurringTransaction]
    @State private var contentHeight: CGFloat = 400

    private static let maxHeight: CGFloat = 640

    /// One line of the list: a bill or a repeating transaction.
    private struct Line: Identifiable {
        enum Source {
            case bill(Bills.Occurrence)
            case repeating(Recurring.Occurrence)
        }

        let source: Source
        let name: String
        let date: Date
        let amount: Decimal
        let isOverdue: Bool
        let isImportant: Bool
        var id: String {
            switch source {
            case .bill(let item): "bill-" + item.id
            case .repeating(let item): "repeat-" + item.id
            }
        }
        var isBill: Bool { if case .bill = source { true } else { false } }
    }

    var body: some View {
        let bills = allBills.live
        let calendar = Calendar.current
        let monthEnd = calendar.dateInterval(of: .month, for: .now)?.end ?? .distantFuture
        let monthName = Date.now.formatted(.dateTime.month(.wide))
        // Overdue ones first, then the rest of this calendar month, soonest first.
        let billLines = Bills.upcoming(bills, days: 31).filter { $0.date < monthEnd && $0.bill.isLive }.map {
            Line(source: .bill($0), name: $0.bill.name, date: $0.date, amount: $0.bill.amount, isOverdue: $0.isOverdue, isImportant: $0.bill.isImportant)
        }
        let repeatingLines = Recurring.upcoming(allRules.live, days: 31).filter { $0.date < monthEnd && $0.rule.isLive }.map {
            Line(source: .repeating($0), name: $0.rule.payee, date: $0.date, amount: $0.rule.amount, isOverdue: $0.isOverdue, isImportant: false)
        }
        let lines = (billLines + repeatingLines).sorted { $0.date != $1.date ? $0.date < $1.date : $0.name < $1.name }

        let dueTotal = billLines.reduce(Decimal(0)) { $0 + $1.amount }
        let overdue = lines.filter(\.isOverdue).count
        let next = lines.first { !$0.isOverdue } ?? lines.first

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
                    Text(lines.isEmpty ? "Nothing due in \(monthName)" : summary(billLines.count, repeatingLines.count))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if !lines.isEmpty {
                HStack(spacing: 10) {
                    stat("Bills to pay", dueTotal.formatted(.appCurrency), color: .primary)
                    stat(overdue > 0 ? "Overdue" : "Next up",
                         overdue > 0 ? "\(overdue) item\(overdue == 1 ? "" : "s")"
                             : (next.map { $0.date.formatted(.dateTime.month(.abbreviated).day()) } ?? "None"),
                         color: overdue > 0 ? Theme.red : .primary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(monthName.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                if lines.isEmpty {
                    Text(bills.isEmpty && allRules.live.isEmpty ? "Nothing set up yet. Add bills and repeating transactions in Oinkly Budget ▸ Bills & Recurring."
                         : "Nothing else due in \(monthName).")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(lines) { row($0) }
                }
            }

            Button {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.title == "Oinkly Budget" }) {
                    window.makeKeyAndOrderFront(nil)
                } else {
                    openWindow(id: "main")
                }
            } label: {
                Label("Open Oinkly Budget", systemImage: "arrow.up.forward.app")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(18)
        .frame(width: 400)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        // Tall lists scroll inside the pop-up instead of running off the screen.
        .frame(width: 400, height: min(max(contentHeight, 160), Self.maxHeight))
    }

    private func summary(_ bills: Int, _ repeating: Int) -> String {
        var parts: [String] = []
        if bills > 0 { parts.append("\(bills) bill\(bills == 1 ? "" : "s") to pay") }
        if repeating > 0 { parts.append("\(repeating) repeating") }
        return parts.joined(separator: " · ")
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

    /// A bill is paid by ticking it. A repeating transaction that waits for you ("Reminder only") is added by ticking it;
    /// the others are added on their own on their date.
    @ViewBuilder
    private func row(_ line: Line) -> some View {
        HStack(spacing: 10) {
            tick(line)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(line.name).font(.system(size: 15)).lineLimit(1)
                    if line.isImportant { Image(systemName: "exclamationmark.circle.fill").font(.system(size: 11)).foregroundStyle(.orange) }
                    tag(line)
                }
                Text(when(line.date, overdue: line.isOverdue))
                    .font(.system(size: 12))
                    .foregroundStyle(line.isOverdue ? Theme.red : Color.secondary)
            }
            Spacer()
            Text(line.amount, format: .appCurrency).font(.system(size: 15, weight: .semibold))
        }
    }

    private func tag(_ line: Line) -> some View {
        Text(line.isBill ? "Bill" : "Repeating")
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background((line.isBill ? Color.blue : Color.purple).opacity(0.16), in: Capsule())
            .foregroundStyle(line.isBill ? Color.blue : Color.purple)
    }

    @ViewBuilder
    private func tick(_ line: Line) -> some View {
        switch line.source {
        case .bill(let item):
            Button {
                BillEntries.markPaid(item.bill, on: item.date, in: modelContext)
                modelContext.saveNow()
                Task { await BillNotifier.refresh(in: modelContext) }
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(item.isOverdue ? Theme.red : Color.secondary)
            }
            .buttonStyle(.plain)
            .help("Mark as paid")
        case .repeating(let item) where item.kind == .due:
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
        case .repeating:
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 18)
        }
    }

    private func when(_ date: Date, overdue: Bool) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: date).day ?? 0
        switch days {
        case ..<0: return "Overdue by \(-days) day\(days == -1 ? "" : "s")"
        case 0: return "Due today"
        case 1: return "Due tomorrow"
        default: return "\(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · in \(days) days"
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
            Text("The menu bar item shows your upcoming bills. Closing the window leaves Oinkly Budget running so the item stays; open the window again from the menu bar item or the Dock, and quit with ⌘Q. With opening at login on, it starts quietly in the menu bar with no window; click the item and choose Open Oinkly Budget when you want the window. If the menu bar item is off, it opens its window at login instead.")
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
