import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PDFKit
import AppKit

/// Save an account's transactions for a period, either as a PDF statement to read or print, or as a CSV spreadsheet
/// (the layout the CSV import reads). They are two separate things with their own buttons: printing a statement is
/// not the same as exporting data.
struct ExportSheet: View {
    enum Kind: Identifiable {
        case pdf, csv
        /// Straight to a printer, through the macOS print window.
        case print
        var id: Self { self }
    }

    /// The account being saved. Nil lets the account be chosen in the sheet.
    let account: Account?
    let kind: Kind
    var startingMonth: Date = MonthFilter.start(of: .now)
    var startingAccountID: Account.ID?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.name) private var allAccounts: [Account]

    private enum Scope: String, CaseIterable, Identifiable {
        case month = "Month", year = "Year", dates = "Dates", all = "All"
        var id: Self { self }
    }

    @State private var scope = Scope.month
    @State private var month: Date
    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var from = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var to = Date.now
    @State private var paper = PaperSize.preferred
    @State private var accountID: Account.ID?
    @State private var errorMessage: String?

    init(account: Account?, kind: Kind = .pdf, startingMonth: Date = MonthFilter.start(of: .now), startingAccountID: Account.ID? = nil) {
        self.account = account
        self.kind = kind
        self.startingMonth = startingMonth
        self.startingAccountID = startingAccountID
        _month = State(initialValue: MonthFilter.start(of: startingMonth))
        _accountID = State(initialValue: startingAccountID)
    }

    private var accounts: [Account] { allAccounts.live }

    /// The account to export, or nil for every account.
    private var chosenAccount: Account? {
        account ?? accountID.flatMap { id in accounts.first { $0.id == id } }
    }

    private var transactionDates: (first: Date?, last: Date?) {
        if let chosenAccount { return modelContext.transactionDateRange(of: chosenAccount) }
        var oldest = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date)])
        oldest.fetchLimit = 1
        var newest = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        newest.fetchLimit = 1
        return ((try? modelContext.fetch(oldest))?.first?.date, (try? modelContext.fetch(newest))?.first?.date)
    }

    /// Every month from the latest back to the earliest, always including this month and the one being looked at.
    private var monthChoices: [Date] {
        let dates = transactionDates
        var range = MonthFilter.range(first: dates.first, last: dates.last)
        let looking = MonthFilter.start(of: startingMonth)
        range = min(range.lowerBound, looking)...max(range.upperBound, looking)
        var months: [Date] = []
        var cursor = range.upperBound
        while cursor >= range.lowerBound, months.count < 1200 {
            months.append(cursor)
            guard let previous = Calendar.current.date(byAdding: .month, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return months
    }

    private var yearChoices: [Int] {
        let dates = transactionDates
        let calendar = Calendar.current
        let current = calendar.component(.year, from: .now)
        let first = dates.first.map { calendar.component(.year, from: $0) } ?? current
        let last = dates.last.map { calendar.component(.year, from: $0) } ?? current
        return Array((min(first, current)...max(last, current)).reversed())
    }

    private var period: ExportPeriod {
        switch scope {
        case .month: .month(month)
        case .year: .year(year)
        case .dates: .dates(from: from, to: to)
        case .all: .all
        }
    }

    private var title: String {
        let name = chosenAccount?.name ?? "Transactions"
        switch kind {
        case .pdf: return "Print \(name) to PDF"
        case .csv: return "Export \(name) as CSV"
        case .print: return "Print \(name)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.title2.bold()).padding(.bottom, 4)
            Text(kind == .print
                 ? "Sends a statement to your printer. Choose the period and paper here, then pick the printer in the print window."
                 : kind == .pdf
                 ? "Saves a PDF statement you can read, keep or email. To print it on paper, use the Print button instead."
                 : "Saves these transactions as a spreadsheet (CSV) you can open in Numbers or Excel, or import again later.")
                .font(.callout).foregroundStyle(.secondary)
                .padding(.bottom, 14)

            Form {
                if account == nil {
                    Picker("Account", selection: $accountID) {
                        Text("All Accounts").tag(Account.ID?.none)
                        ForEach(accounts) { Text($0.name).tag(Optional($0.id)) }
                    }
                }

                Picker("Period", selection: $scope) {
                    ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                switch scope {
                case .month:
                    Picker("Month", selection: $month) {
                        ForEach(monthChoices, id: \.self) { Text($0.formatted(.dateTime.month(.wide).year())).tag($0) }
                    }
                case .year:
                    Picker("Year", selection: $year) {
                        ForEach(yearChoices, id: \.self) { Text(String($0)).tag($0) }
                    }
                case .dates:
                    DatePicker("From", selection: $from, displayedComponents: .date)
                    DatePicker("To", selection: $to, displayedComponents: .date)
                case .all:
                    Text("Every transaction\(chosenAccount.map { " in \($0.name)" } ?? "").")
                        .foregroundStyle(.secondary)
                }

                if kind != .csv {
                    Picker("Paper", selection: $paper) {
                        ForEach(PaperSize.allCases) { Text($0.title).tag($0) }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            if let errorMessage {
                Text(errorMessage).font(.callout).foregroundStyle(Theme.red).padding(.top, 6)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(kind == .print ? "Print…" : (kind == .pdf ? "Save PDF" : "Save CSV"), action: kind == .print ? printNow : export)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 12)
        }
        .padding(20)
        .frame(width: 460)
    }

    private func fileName(_ chosen: Account?, _ period: ExportPeriod) -> String {
        let base = [chosen?.name ?? "Transactions", period.label].joined(separator: " – ")
        let cleaned = base.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return cleaned + (kind == .pdf ? ".pdf" : ".csv")
    }

    /// Makes the statement as a PDF and hands it to the macOS print window, where the printer, copies and pages are chosen.
    private func printNow() {
        errorMessage = nil
        let statement = StatementBuilder.make(account: chosenAccount, period: period, in: modelContext)
        let data = StatementPDF.render(statement, paper: paper)
        guard !data.isEmpty, let document = PDFDocument(data: data) else {
            errorMessage = "Couldn't prepare the statement to print."
            return
        }
        let info = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo()
        info.paperSize = paper.size
        info.topMargin = 0; info.bottomMargin = 0; info.leftMargin = 0; info.rightMargin = 0
        guard let operation = document.printOperation(for: info, scalingMode: .pageScaleDownToFit, autoRotate: true) else {
            errorMessage = "Couldn't open the print window."
            return
        }
        operation.jobTitle = title
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        // The sheet closes first, so the print window isn't stacked on it.
        dismiss()
        DispatchQueue.main.async { operation.run() }
    }

    private func export() {
        errorMessage = nil
        let chosen = chosenAccount
        let period = period
        let name = fileName(chosen, period)
        func write(to url: URL) throws {
            let statement = StatementBuilder.make(account: chosen, period: period, in: modelContext)
            switch kind {
            case .pdf, .print:
                let data = StatementPDF.render(statement, paper: paper)
                guard !data.isEmpty else { throw CocoaError(.fileWriteUnknown) }
                try data.write(to: url, options: .atomic)
            case .csv:
                try TransactionCSV.text(for: statement.transactions).write(to: url, atomically: true, encoding: .utf8)
            }
        }
        do {
            // Straight into the default save location when there is one, else ask where.
            if let url = try DefaultSaveFolder.save(named: name, write) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
                dismiss()
                return
            }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [kind == .pdf ? .pdf : .commaSeparatedText]
            panel.nameFieldStringValue = name
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try write(to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            dismiss()
        } catch {
            errorMessage = "Couldn't save the file: \(error.localizedDescription)"
        }
    }
}
