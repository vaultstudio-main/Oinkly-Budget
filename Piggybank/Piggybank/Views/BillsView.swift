import SwiftUI
import PhotosUI
import SwiftData

private enum BillSheet: Identifiable {
    case add(Date)
    case edit(Bill)

    var id: String {
        switch self {
        case .add(let date): "add-\(date.timeIntervalSince1970)"
        case .edit(let bill): "edit-\(bill.persistentModelID.hashValue)"
        }
    }
}

/// Plan the month: a small calendar with every bill on it, what is coming up, and a place to add or remove bills.
/// On the Mac the calendar and upcoming list sit in a sidebar.
struct BillsView: View {
    @Query private var allBills: [Bill]
    private var bills: [Bill] { allBills.live }

    @Environment(\.modelContext) private var modelContext
    @State private var month = Calendar.current.startOfDay(for: .now)
    @State private var selectedDay: Date?
    @State private var sheet: BillSheet?
    private enum Tab: String, CaseIterable, Identifiable {
        case bills = "Bills", recurring = "Recurring"
        var id: Self { self }
    }
    @State private var tab = Tab.bills

    private var calendar: Calendar { .current }

    private var monthStart: Date { calendar.dateInterval(of: .month, for: month)?.start ?? month }
    private var monthEnd: Date { calendar.date(byAdding: .day, value: -1, to: calendar.date(byAdding: .month, value: 1, to: monthStart)!)! }

    var body: some View {
        let monthItems = Bills.occurrences(bills, from: monthStart, through: monthEnd)
        let upcoming = Bills.upcoming(bills).filter(\.bill.isImportant)
        Group {
            VStack(spacing: 0) {
            HStack {
                PageTitle("Bills & Recurring")
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
            }
            .padding([.horizontal, .top], 16)
            if tab == .recurring {
                RecurringView()
            } else {
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(spacing: 14) {
                        BillAlertBanner()
                        tiles(monthItems)
                        monthCard(monthItems)
                    }
                    .padding(16)
                }
                Divider()
                ScrollView {
                    VStack(spacing: 14) {
                        BillCalendar(month: $month, selectedDay: $selectedDay, items: monthItems)
                        addBillButton
                        upcomingCard(upcoming)
                    }
                    .padding(16)
                }
                .frame(width: 360)
            }
            }
            }
            .background(Theme.background)
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .add(let date): BillEditView(bill: nil, defaultDate: date)
            case .edit(let bill): BillEditView(bill: bill, defaultDate: bill.dueDate)
            }
        }
    }

    // MARK: Tiles

    private func tiles(_ items: [Bills.Occurrence]) -> some View {
        let total = items.reduce(Decimal(0)) { $0 + $1.bill.amount }
        let paid = items.filter(\.isPaid).reduce(Decimal(0)) { $0 + $1.bill.amount }
        let left = total - paid
        let next = Bills.upcoming(bills, days: 365, missedDays: 0).first
        return StatGrid {
            StatTile(title: "Due This Month") {
                Text(total, format: .appCurrency)
            } note: {
                Text("\(items.count) bill\(items.count == 1 ? "" : "s")")
            }
            StatTile(title: "Paid") {
                Text(paid, format: .appCurrency).foregroundStyle(Theme.green)
            } note: {
                Text("\(items.filter(\.isPaid).count) of \(items.count) marked paid")
            }
            StatTile(title: "Still To Pay") {
                Text(left, format: .appCurrency).foregroundStyle(left > 0 ? Theme.red : Color.primary)
            } note: {
                Text(items.contains(where: \.isOverdue) ? "Some are overdue" : "Nothing overdue")
            }
            StatTile(title: "Next Bill") {
                if let next { Text(next.date, format: .dateTime.month(.abbreviated).day()) } else { Text("None") }
            } note: {
                Text(next.map { "\($0.bill.name) · \($0.bill.amount.formatted(.appCurrency))" } ?? "Nothing coming up")
            }
        }
    }

    /// Right under the calendar, so a new bill is always one click away. It uses the selected day, or today.
    private var addBillButton: some View {
        Button {
            sheet = .add(selectedDay ?? .now)
        } label: {
            Label("Add a Bill", systemImage: "plus.circle.fill")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    // MARK: Lists

    private func upcomingCard(_ items: [Bills.Occurrence]) -> some View {
        ReportCard(title: "Important · Next 30 Days") {
            if items.isEmpty {
                Text(bills.isEmpty ? "No bills yet. Use Add a Bill under the calendar."
                     : (bills.contains(where: \.isImportant) ? "No important bills due in the next 30 days."
                        : "Mark a bill as important when you add or edit it and it shows up here."))
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        BillRow(item: item, showsYear: false, onEdit: { sheet = .edit(item.bill) }, onDelete: delete)
                        if item.id != items.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private func monthCard(_ items: [Bills.Occurrence]) -> some View {
        let shown = selectedDay.map { day in items.filter { calendar.isDate($0.date, inSameDayAs: day) } } ?? items
        let title = selectedDay.map { $0.formatted(.dateTime.weekday(.wide).month(.wide).day()) }
            ?? monthStart.formatted(.dateTime.month(.wide).year())
        return ReportCard(title: title, fillsHeight: false) {
            VStack(alignment: .leading, spacing: 8) {
                if selectedDay != nil {
                    HStack {
                        Button("Show whole month") { selectedDay = nil }
                        Spacer()
                    }
                    .font(.callout)
                    .buttonStyle(.borderless)
                }
                if shown.isEmpty {
                    Text(selectedDay == nil ? "No bills this month." : "No bills on this day.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(shown) { item in
                        BillRow(item: item, showsYear: false, onEdit: { sheet = .edit(item.bill) }, onDelete: delete)
                        if item.id != shown.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private func delete(_ bill: Bill) {
        modelContext.delete(bill)
        modelContext.saveNow()
        Task { await BillNotifier.refresh(in: modelContext) }
    }
}

// MARK: Rows

private struct BillRow: View {
    let item: Bills.Occurrence
    let showsYear: Bool
    let onEdit: () -> Void
    let onDelete: (Bill) -> Void

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if item.bill.isLive {
            HStack(spacing: 12) {
                Button {
                    item.bill.setPaid(!item.isPaid, on: item.date)
                    modelContext.saveNow()
                    Task { await BillNotifier.refresh(in: modelContext) }
                } label: {
                    Image(systemName: item.isPaid ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(item.isPaid ? Theme.green : (item.isOverdue ? Theme.red : Color.secondary))
                }
                .buttonStyle(.plain)
                .help(item.isPaid ? "Mark as not paid" : "Mark as paid")

                Button(action: onEdit) {
                    HStack {
                        AccountPicture(data: item.bill.displayPhotoData, type: item.bill.loan?.isLive == true ? item.bill.loan?.type : nil)
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(item.bill.name).font(.body).strikethrough(item.isPaid)
                                if item.bill.isImportant {
                                    Image(systemName: "exclamationmark.circle.fill").font(.caption).foregroundStyle(.orange)
                                }
                            }
                            Text(subtitle).font(.caption).foregroundStyle(item.isOverdue ? Theme.red : (item.isPaid ? Theme.green : Color.secondary))
                        }
                        Spacer()
                        Text(item.bill.amount, format: .appCurrency)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(item.isPaid ? Color.secondary : Color.primary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 8)
            .contextMenu {
                Button("Edit", systemImage: "pencil", action: onEdit)
                Button("Delete Bill", systemImage: "trash", role: .destructive) { onDelete(item.bill) }
            }
        }
    }

    private var subtitle: String {
        let day = item.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let tail = item.isPaid ? "Paid" : (item.isOverdue ? "Overdue" : item.bill.frequency.title)
        return "\(day) · \(tail)"
    }
}

// MARK: Calendar

private struct BillCalendar: View {
    @Binding var month: Date
    @Binding var selectedDay: Date?
    let items: [Bills.Occurrence]

    private var calendar: Calendar { .current }

    private var monthStart: Date { calendar.dateInterval(of: .month, for: month)?.start ?? month }

    private var isCurrentMonth: Bool { calendar.isDate(monthStart, equalTo: .now, toGranularity: .month) }

    /// Weekday names starting on the user's first weekday.
    private var weekdays: [String] {
        let names = calendar.shortWeekdaySymbols
        return (0..<7).map { names[($0 + calendar.firstWeekday - 1) % 7] }
    }

    /// Blanks before the 1st, then each day of the month.
    private var cells: [Date?] {
        let weekday = calendar.component(.weekday, from: monthStart)
        let blanks = (weekday - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        return Array(repeating: nil, count: blanks) + (0..<count).map { calendar.date(byAdding: .day, value: $0, to: monthStart) }
    }

    var body: some View {
        ReportCard(title: "Calendar") {
            VStack(spacing: 10) {
                HStack(spacing: 4) {
                    Text(monthStart, format: .dateTime.month(.wide).year())
                        .font(.title3.bold())
                    Spacer()
                    if !isCurrentMonth {
                        Button { goToToday() } label: {
                            Label("Today", systemImage: "arrow.uturn.backward")
                                .font(.callout.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                        .help("Back to this month")
                        .transition(.scale.combined(with: .opacity))
                    }
                    Button { step(-1) } label: { Image(systemName: "chevron.left") }
                        .help("Previous month")
                    Button { step(1) } label: { Image(systemName: "chevron.right") }
                        .help("Next month")
                }
                .buttonStyle(.borderless)
                .animation(.snappy(duration: 0.2), value: isCurrentMonth)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                    ForEach(weekdays, id: \.self) { name in
                        Text(name).font(.caption2).foregroundStyle(.secondary)
                    }
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                        if let day { dayCell(day) } else { Color.clear.frame(height: 40) }
                    }
                }
            }
        }
    }

    private func goToToday() {
        month = Calendar.current.startOfDay(for: .now)
        selectedDay = nil
    }

    private func step(_ value: Int) {
        month = calendar.date(byAdding: .month, value: value, to: monthStart) ?? month
        selectedDay = nil
    }

    private func dayCell(_ day: Date) -> some View {
        let due = items.filter { calendar.isDate($0.date, inSameDayAs: day) }
        let isToday = calendar.isDateInToday(day)
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        return Button {
            selectedDay = isSelected ? nil : day
        } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.callout.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isSelected ? Color.white : (isToday ? Color.accentColor : Color.primary))
                HStack(spacing: 2) {
                    ForEach(Array(due.prefix(3).enumerated()), id: \.offset) { _, item in
                        Circle().fill(dot(item)).frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor : (isToday ? Color.accentColor.opacity(0.12) : .clear))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func dot(_ item: Bills.Occurrence) -> Color {
        if item.isPaid { return Theme.green }
        return item.isOverdue ? Theme.red : .orange
    }
}

// MARK: Add / edit

struct BillEditView: View {
    let bill: Bill?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.name) private var allCategories: [Category]

    @State private var name: String
    @State private var amount: Decimal?
    @State private var frequency: BillFrequency
    @State private var dueDate: Date
    @State private var remindersOn: Bool
    @State private var isImportant: Bool
    @State private var remindDays: Int
    @State private var notes: String
    @State private var category: Category?
    @State private var photoData: Data?
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var confirmingDelete = false

    init(bill: Bill?, defaultDate: Date) {
        self.bill = bill
        _name = State(initialValue: bill?.name ?? "")
        _amount = State(initialValue: bill.map(\.amount))
        _frequency = State(initialValue: bill?.frequency ?? .monthly)
        _dueDate = State(initialValue: bill?.dueDate ?? defaultDate)
        _remindersOn = State(initialValue: bill?.remindersOn ?? true)
        _isImportant = State(initialValue: bill?.isImportant ?? false)
        _remindDays = State(initialValue: bill?.remindDaysBefore ?? 3)
        _notes = State(initialValue: bill?.notes ?? "")
        _photoData = State(initialValue: bill?.photoData)
        _category = State(initialValue: bill?.category)
    }

    /// A loan's bill uses the loan's photo until you pick one for the bill itself.
    private var inheritedPhoto: Data? {
        guard let loan = bill?.loan, loan.isLive else { return nil }
        return loan.photoData
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (amount ?? 0) != 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    FormTextField("Name", text: $name)
                    CurrencyField("Amount", value: $amount)
                    Picker("Repeats", selection: $frequency) {
                        ForEach(BillFrequency.allCases) { Text($0.title).tag($0) }
                    }
                    DatePicker(frequency == .once ? "Due date" : "First due", selection: $dueDate, displayedComponents: .date)
                    if bill?.loan == nil {
                        Picker("Category", selection: $category) {
                            CategoryOptions(categories: allCategories.live, only: .expense, keeping: category)
                        }
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if bill?.loan == nil {
                            Text("Pay this bill with Pay a Bill and it is recorded under this category, so it shows in your reports and budgets.")
                        }
                        if frequency != .once {
                            Text("Repeats from this date, so a bill first due on the 15th falls on the 15th every time.")
                        }
                    }
                }
                Section {
                    Toggle("Important bill", isOn: $isImportant)
                } footer: {
                    Text("Important bills are listed in the sidebar and raise a priority alert as the due date gets close.")
                }
                Section {
                    Toggle("Remind me", isOn: $remindersOn)
                    if remindersOn {
                        Stepper("\(remindDays) day\(remindDays == 1 ? "" : "s") before", value: $remindDays, in: 0...30)
                    }
                } footer: {
                    Text("Choose how many days ahead you want to be reminded. Reminders are planned for 9 AM.")
                }
                Section("Photo") {
                    AccountPicture(data: photoData ?? inheritedPhoto, type: bill?.loan?.isLive == true ? bill?.loan?.type : nil)
                        .frame(maxWidth: .infinity)
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    if photoData == nil, inheritedPhoto != nil, let loan = bill?.loan {
                        Text("Using the photo from \(loan.name). Choose a different one to replace it for this bill.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    PhotosPicker(selection: $pickedPhoto, matching: .images) {
                        Label(photoData == nil && inheritedPhoto == nil ? "Add Photo" : "Change Photo", systemImage: "photo")
                    }
                    if photoData != nil {
                        Button("Remove Photo", role: .destructive) { photoData = nil; pickedPhoto = nil }
                    }
                }
                Section("Notes") {
                    FormTextField("Notes", text: $notes, hint: "Add a note", axis: .vertical, showsLabel: false)
                        .lineLimit(1...4)
                }
                if bill != nil {
                    Section {
                        Button("Delete Bill", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .formStyle(.grouped)
            .onChange(of: pickedPhoto) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        photoData = AccountPhoto.compress(data)
                    }
                }
            }
            .navigationTitle(bill == nil ? "New Bill" : "Edit Bill")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
            .confirmationDialog("Delete this bill?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete Bill", role: .destructive) {
                    if let bill { modelContext.delete(bill) }
                    modelContext.saveNow()
                    dismiss()
                }
            } message: {
                Text("This removes every due date of the bill. Transactions you recorded are not affected.")
            }
        }
        .macSheetFrame(minHeight: 620)
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespaces)
        let value = abs(amount ?? 0)
        if let bill {
            bill.name = cleanName
            bill.amount = value
            bill.frequency = frequency
            // Moving the first date would orphan paid marks, so keep only those that still match a due date.
            bill.dueDate = Calendar.current.startOfDay(for: dueDate)
            bill.remindersOn = remindersOn
            bill.isImportant = isImportant
            bill.remindDaysBefore = remindDays
            bill.notes = notes
            bill.photoData = photoData
            if bill.loan == nil { bill.category = category }
            let far = Calendar.current.date(byAdding: .year, value: 5, to: .now)!
            let valid = Bills.dates(of: bill, from: .distantPast, through: far)
            bill.paidDates = bill.paidDates.filter { paid in valid.contains { Calendar.current.isDate($0, inSameDayAs: paid) } }
        } else {
            let created = Bill(name: cleanName, amount: value, frequency: frequency, dueDate: dueDate,
                               remindDaysBefore: remindDays, remindersOn: remindersOn, isImportant: isImportant, notes: notes)
            created.photoData = photoData
            created.category = category
            modelContext.insert(created)
        }
        modelContext.saveNow()
        Task { await BillNotifier.refresh(in: modelContext) }
        dismiss()
    }
}

// MARK: Priority alert

/// Lists important bills that are overdue or coming due soon. Shown on the Bills page and the home screen.
struct BillAlertBanner: View {
    @Query private var allBills: [Bill]

    var body: some View {
        let items = Bills.alerts(allBills.live)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Priority bills", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                ForEach(items) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.bill.name).font(.body.weight(.semibold))
                            Text(when(item))
                                .font(.caption)
                                .foregroundStyle(item.isOverdue ? Theme.red : Color.secondary)
                        }
                        Spacer()
                        Text(item.bill.amount, format: .appCurrency).font(.body.weight(.semibold))
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.5), lineWidth: 1))
        }
    }

    private func when(_ item: Bills.Occurrence) -> String { item.dueText }
}

extension Bills.Occurrence {
    /// "Due in 3 days · Oct 21", "Due today", "Overdue by 2 days".
    var dueText: String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: date).day ?? 0
        switch days {
        case ..<0: return "Overdue by \(-days) day\(days == -1 ? "" : "s")"
        case 0: return "Due today"
        case 1: return "Due tomorrow"
        default: return "Due in \(days) days · \(date.formatted(.dateTime.month(.abbreviated).day()))"
        }
    }
}

/// The Summary page's list of the next few important bills: overdue ones and those due in the next 20 days.
struct PriorityBillsCard: View {
    @Query private var allBills: [Bill]

    var body: some View {
        let items = Bills.priority(allBills.live)
        ReportPanel(title: "Priority Bills", summary: "Your important bills that are overdue or due in the next 20 days.",
                    headline: items.isEmpty ? nil : "\(items.count) bill\(items.count == 1 ? "" : "s")") {
            if items.isEmpty {
                Label("No priority bills due soon. Mark a bill Important on the Bills page to see it here.", systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider() }
                        HStack {
                            Image(systemName: item.isOverdue ? "exclamationmark.circle.fill" : "calendar")
                                .foregroundStyle(item.isOverdue ? Theme.red : Color.orange)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.bill.name).font(.body.weight(.semibold))
                                Text(item.dueText)
                                    .font(.caption)
                                    .foregroundStyle(item.isOverdue ? Theme.red : Color.secondary)
                            }
                            Spacer()
                            Text(item.bill.amount, format: .appCurrency).font(.body.weight(.semibold))
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }
}
