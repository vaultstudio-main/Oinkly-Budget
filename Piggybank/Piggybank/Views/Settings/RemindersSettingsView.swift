import SwiftUI

/// Settings ▸ Reminders: nudges you set up yourself, such as reviewing the budget each month.
struct RemindersSettingsView: View {
    @State private var reminders = CustomReminders.shared
    @State private var editing: CustomReminder?
    @State private var isNew = false
    @State private var status: BillNotifier.Status?
    @State private var testMessage: String?
    @AppStorage(BillNotifier.enabledKey) private var billReminders = true

    var body: some View {
        Form {
            Section {
                if reminders.items.isEmpty {
                    Text("No reminders yet. Add one to get a notification to do something in the app, like reviewing your budget.")
                        .foregroundStyle(.secondary)
                }
                ForEach(reminders.items) { item in
                    HStack {
                        Toggle("", isOn: binding(for: item.id, \.isOn)).labelsHidden()
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title.isEmpty ? "Untitled reminder" : item.title)
                            Text(item.hasPassed ? "Already happened" : item.summary)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Edit…") { isNew = false; editing = item }
                        Button(role: .destructive) {
                            reminders.items.removeAll { $0.id == item.id }
                        } label: { Image(systemName: "trash") }
                            .help("Delete this reminder")
                    }
                }
                Menu("Add a Reminder") {
                    ForEach(CustomReminder.presets, id: \.title) { preset in
                        Button(preset.title) { var r = preset.reminder; r.id = UUID(); isNew = true; editing = r }
                    }
                    Divider()
                    Button("Custom…") { isNew = true; editing = CustomReminder() }
                }
                .menuStyle(.borderedButton)
                .fixedSize()
            } header: {
                Text("Your Reminders")
            } footer: {
                Text("Each one arrives as a notification, even when Piggybank Budgeting isn't open. Click it to jump to the page you chose.")
            }

            Section {
                Toggle("Remind me about upcoming bills", isOn: $billReminders)
                    .onChange(of: billReminders) { _, on in
                        if on { Task { await BillNotifier.requestAccess(); status = await BillNotifier.status() } }
                    }
                LabeledContent("Notifications") {
                    switch status {
                    case .allowed: Label("On", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.green)
                    case .denied: Label("Off in System Settings", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    case .notAsked: Text("Not allowed yet").foregroundStyle(.secondary)
                    case nil: Text("Checking…").foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button("Send a Test Notification") {
                        Task {
                            let sent = await BillNotifier.sendTest()
                            testMessage = sent ? "Sent. It should appear in a moment." : "Notifications aren't allowed yet. Turn them on in System Settings."
                            status = await BillNotifier.status()
                        }
                    }
                    Button("Open Notification Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                if let testMessage {
                    Text(testMessage).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("Bill Reminders")
            } footer: {
                Text("You get a notification the number of days before a bill is due that you chose for it, and another on the day it is due, at 9 AM, even when Piggybank Budgeting isn't open.")
            }
        }
        .formStyle(.grouped)
        .task { status = await BillNotifier.status() }
        .sheet(item: $editing) { draft in
            ReminderEditor(reminder: draft) { saved in
                if let index = reminders.items.firstIndex(where: { $0.id == saved.id }) {
                    reminders.items[index] = saved
                } else {
                    reminders.items.append(saved)
                }
                Task {
                    _ = await BillNotifier.requestAccess()
                    status = await BillNotifier.status()
                }
            }
        }
    }

    private func binding<T>(for id: UUID, _ keyPath: WritableKeyPath<CustomReminder, T>) -> Binding<T> {
        Binding(
            get: { reminders.items.first { $0.id == id }?[keyPath: keyPath] ?? CustomReminder()[keyPath: keyPath] },
            set: { value in
                if let index = reminders.items.firstIndex(where: { $0.id == id }) { reminders.items[index][keyPath: keyPath] = value }
            }
        )
    }
}

private struct ReminderEditor: View {
    @State var reminder: CustomReminder
    let onSave: (CustomReminder) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Title", text: $reminder.title, prompt: Text("Review my budget"))
                    TextField("Message", text: $reminder.note, prompt: Text("Optional"), axis: .vertical)
                        .lineLimit(1...3)
                }
                Section("When") {
                    Picker("Repeat", selection: $reminder.repeats) {
                        ForEach(CustomReminder.Repeat.allCases) { Text($0.title).tag($0) }
                    }
                    switch reminder.repeats {
                    case .daily:
                        DatePicker("Time", selection: $reminder.time, displayedComponents: .hourAndMinute)
                    case .weekly:
                        Picker("Day", selection: $reminder.weekday) {
                            ForEach(1...7, id: \.self) { Text(Calendar.current.weekdaySymbols[$0 - 1]).tag($0) }
                        }
                        DatePicker("Time", selection: $reminder.time, displayedComponents: .hourAndMinute)
                    case .monthly:
                        Picker("Day of the month", selection: $reminder.dayOfMonth) {
                            ForEach(1...28, id: \.self) { Text("\($0)").tag($0) }
                        }
                        DatePicker("Time", selection: $reminder.time, displayedComponents: .hourAndMinute)
                    case .once:
                        DatePicker("Date and time", selection: $reminder.onceDate)
                    }
                }
                Section {
                    Picker("When I click it", selection: $reminder.page) {
                        ForEach(ReminderPage.allCases) { Text($0.title).tag($0) }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { onSave(reminder); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(reminder.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 440, height: 500)
    }
}
