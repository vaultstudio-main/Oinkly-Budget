import SwiftUI
import SwiftData
import PhotosUI

struct AccountEditView: View {
    /// Pass nil to create a new account.
    let account: Account?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var type: AccountType
    @State private var institution: String
    @State private var accountNumber: String
    @State private var routingNumber: String
    @State private var wireRouting: String
    @State private var digitalRouting: String
    @State private var loanPurpose: String
    @State private var vin: String
    @State private var originalLoanAmount: Decimal
    @State private var monthlyPayment: Decimal
    @State private var owedNow: Decimal
    @State private var interestRate: Decimal?
    @State private var creditLimit: Decimal
    @State private var cardBalance: Decimal
    @State private var hasDueDate: Bool
    @State private var isLease: Bool
    @State private var dueDate: Date
    @State private var hasPayoffDate: Bool
    @State private var payoffDate: Date
    @State private var hasStartDate: Bool
    @State private var startDate: Date
    @State private var photoData: Data?
    @State private var artworkTheme = 0
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var openingBalance: Decimal
    @State private var notes: String
    @State private var isPrimary: Bool

    init(account: Account?, initialType: AccountType = .checking) {
        self.account = account
        _name = State(initialValue: account?.name ?? "")
        _type = State(initialValue: account?.type ?? initialType)
        _institution = State(initialValue: account?.institution ?? "")
        _accountNumber = State(initialValue: account?.accountNumber ?? "")
        _routingNumber = State(initialValue: account?.achRouting ?? "")
        _wireRouting = State(initialValue: account?.wireRouting ?? "")
        _digitalRouting = State(initialValue: account?.digitalRouting ?? "")
        _loanPurpose = State(initialValue: account?.loanPurpose ?? "")
        _vin = State(initialValue: account?.vin ?? "")
        _originalLoanAmount = State(initialValue: account?.originalLoanAmount ?? 0)
        _monthlyPayment = State(initialValue: account?.monthlyPayment ?? 0)
        _owedNow = State(initialValue: abs(account?.openingBalance ?? 0))
        _interestRate = State(initialValue: (account?.interestRate ?? 0) > 0 ? Decimal(account?.interestRate ?? 0) : nil)
        _creditLimit = State(initialValue: account?.creditLimit ?? 0)
        _cardBalance = State(initialValue: abs(account?.openingBalance ?? 0))
        _hasDueDate = State(initialValue: account?.loanBill != nil)
        _isLease = State(initialValue: account?.isLease ?? false)
        _dueDate = State(initialValue: account?.loanBill?.dueDate ?? .now)
        _hasPayoffDate = State(initialValue: account?.payoffDate != nil)
        _hasStartDate = State(initialValue: account?.loanStartDate != nil)
        _startDate = State(initialValue: account?.loanStartDate ?? .now)
        _payoffDate = State(initialValue: account?.payoffDate ?? Calendar.current.date(byAdding: .year, value: 3, to: .now) ?? .now)
        _photoData = State(initialValue: account?.photoData)
        _artworkTheme = State(initialValue: account.map { ArtworkChoices.theme(for: $0) } ?? 0)
        // An account whose money began as a deposit shows that amount here.
        _openingBalance = State(initialValue: account.flatMap { OpeningDeposit.existing(in: $0)?.amount } ?? account?.openingBalance ?? 0)
        _notes = State(initialValue: account?.notes ?? "")
        _isPrimary = State(initialValue: account.map { PrimaryChecking.isPrimary($0) } ?? false)
    }

    private var isDebt: Bool { type.group.isLiability }
    /// An auto account chosen as a lease instead of a loan.
    private var leased: Bool { type == .autoLoan && isLease }

    /// One wide window with everything on it, so nothing scrolls: the account and its notes, the money, then the bank and the picture.
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(account == nil ? "New Account" : "Edit Account").font(.headline)
                Spacer()
                Label(isDebt ? "Debt: you owe this" : "Asset: you own this",
                      systemImage: isDebt ? "arrow.down.right.circle.fill" : "arrow.up.right.circle.fill")
                    .font(.callout)
                    .foregroundStyle(isDebt ? Theme.red : Theme.green)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                Form {
                    accountSection
                    notesSection
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
                Divider()
                Form { termsSection }
                    .formStyle(.grouped)
                    .scrollDisabled(true)
                Divider()
                Form {
                    bankSection
                    pictureSections
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
            }
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 10) {
                    Spacer()
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Save", action: save)
                        .keyboardShortcut(.defaultAction)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || limitProblem != nil || loanProblem != nil)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(.bar)
        }
        .background(Theme.background)
        .onChange(of: type) { _, new in
            // A new cash account starts out named for what it is.
            if new == .cash && name.trimmingCharacters(in: .whitespaces).isEmpty { name = "Cash on Hand" }
        }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    photoData = AccountPhoto.compress(data)
                }
            }
        }
        .screenFitted(width: 1180, height: 680)
    }

    // MARK: Columns

    @ViewBuilder
    private var accountSection: some View {
        Section("Account") {
            FormTextField("Name", text: $name)
                .onChange(of: name) { _, new in
                    if new.count > Account.maxNameLength { name = String(new.prefix(Account.maxNameLength)) }
                }
            Picker("Type", selection: $type) {
                ForEach(AccountGroup.setupOrder) { group in
                    Section(group.title) {
                        // Cash on Hand is built in, so it isn't offered again.
                        ForEach(group.accountTypes.filter { $0 != .cash || type == .cash }) { Text($0.title).tag($0) }
                    }
                }
            }
            .disabled(account?.isDefault == true)
            if type == .checking {
                Toggle("Primary checking account", isOn: $isPrimary)
                Text("Pinned to the top of the account list, under Cash on Hand. Only one account can be primary.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if type == .autoLoan {
                Picker("Financing", selection: $isLease) {
                    Text("Loan").tag(false)
                    Text("Lease").tag(true)
                }
                .pickerStyle(.segmented)
            }
            if type.group == .loans {
                FormTextField("What is this loan for?", text: $loanPurpose, hint: "e.g. 2021 Honda Civic")
            }
            if Account.typeHasVIN(type) {
                FormTextField("VIN", text: $vin, hint: "17 characters")
                    .onChange(of: vin) { _, new in
                        let clean = Account.cleanVIN(new)
                        if clean != new { vin = clean }
                    }
                if !vin.isEmpty && vin.count != Account.vinLength {
                    Text("A VIN has exactly 17 letters and numbers (no I, O or Q).")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private var notesSection: some View {
        Section("Notes") {
            FormTextField("Notes", text: $notes, hint: "Add a note", axis: .vertical, showsLabel: false)
                .lineLimit(3...5)
        }
    }

    /// The money: terms for a loan or lease, the limit and balance for a card, the opening balance for anything else.
    @ViewBuilder
    private var termsSection: some View {
        Section(type.group == .loans ? (leased ? "Lease Terms" : "Loan Terms") : (type.group == .creditCards ? "Card Terms" : "Balance")) {
            if type.group == .loans {
                amountRow(leased ? "Total lease cost" : "Original loan amount", $originalLoanAmount)
                amountRow("Monthly payment (required)", $monthlyPayment)
                amountRow("Amount owed now", $owedNow)
                if !leased { aprRow }
                DatePicker("Payment due date (required)", selection: $dueDate, displayedComponents: .date)
                Text("This \(leased ? "lease" : "loan") is added to Bills for the monthly payment, due on this day every month.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let loanProblem {
                    Label(loanProblem, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.orange)
                }
                Toggle(leased ? "Set the lease start date" : "Set the loan start date", isOn: $hasStartDate.animation())
                if hasStartDate {
                    DatePicker(leased ? "Lease start date" : "Loan start date", selection: $startDate, in: ...Date.now, displayedComponents: .date)
                }
                Toggle(leased ? "Set a lease end date" : "Set a maturity date", isOn: $hasPayoffDate.animation())
                if hasPayoffDate {
                    DatePicker(leased ? "Lease end date" : "Maturity date", selection: $payoffDate, in: Date.now..., displayedComponents: .date)
                }
            } else if type.group == .creditCards {
                aprRow
                amountRow("Credit limit", $creditLimit)
                amountRow("Current balance on card", $cardBalance)
                if let limitProblem {
                    Label(limitProblem, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.orange)
                }
                amountRow("Minimum payment", $monthlyPayment)
                Toggle("Set a payment due date", isOn: $hasDueDate.animation())
                if hasDueDate {
                    DatePicker("Payment due date", selection: $dueDate, displayedComponents: .date)
                    Text("This card is added to Bills for the minimum payment, due on this day every month.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text("What you owe on the card right now. Charges and payments you add change it from here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if type == .cash {
                Text("Cash on Hand starts at $0.00 and is filled by ATM withdrawals.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("Opening balance")
                    Spacer()
                    CurrencyField("Opening balance", amount: $openingBalance)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private var aprRow: some View {
        HStack {
            Text("Interest rate (APR)")
            Spacer()
            TextField("Interest rate", value: $interestRate, format: .number.precision(.fractionLength(0...3)), prompt: Text("0.00"))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
            Text("%").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var bankSection: some View {
        if type != .cash {
            Section(type.group == .loans ? (leased ? "Leasing Company" : "Lender") : "Bank Details") {
                FormTextField(type.group == .loans ? (leased ? "Leasing company" : "Lender") : "Institution", text: $institution)
                FormTextField(type.group == .creditCards ? "Card number" : "Account number", text: $accountNumber, hint: type.group == .creditCards ? "Up to 19 digits" : "Up to 17 digits")
                    .onChange(of: accountNumber) { _, new in
                        let clean = Account.digits(new, limit: Account.numberLimit(for: type))
                        if clean != new { accountNumber = clean }
                    }
                    .onChange(of: type) { _, new in
                        accountNumber = Account.digits(accountNumber, limit: Account.numberLimit(for: new))
                    }
                if type == .checking {
                    routingField("Routing number (ACH)", $routingNumber)
                    routingField("Wire transfer routing number", $wireRouting, letters: true)
                    routingField("Digital routing number", $digitalRouting)
                }
            }
        }
    }

    /// The picture on the side: a colour for the account's artwork, and for loans and assets a photo of the thing itself.
    @ViewBuilder
    private var pictureSections: some View {
        if type.group == .loans || type.group == .assets {
            Section("Photo") {
                AccountPicture(data: photoData, type: type, theme: artworkTheme)
                    .frame(maxWidth: .infinity)
                    .frame(height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                HStack {
                    PhotosPicker(selection: $pickedPhoto, matching: .images) {
                        Label(photoData == nil ? "Choose Photo" : "Change Photo", systemImage: "photo")
                    }
                    if photoData != nil {
                        Spacer()
                        Button("Remove Photo", role: .destructive) { photoData = nil; pickedPhoto = nil }
                    }
                }
            }
        }
        if photoData == nil || !(type.group == .loans || type.group == .assets) {
            Section("Picture Colour") {
                ArtworkThemePicker(type: type, theme: $artworkTheme)
            }
        }
    }


    private func amountRow(_ title: String, _ value: Binding<Decimal>) -> some View {
        HStack {
            Text(title)
            Spacer()
            CurrencyField(title, amount: value)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
        }
    }

    /// A routing number box that keeps to nine digits and says so when it is short.
    @ViewBuilder
    private func routingField(_ title: String, _ value: Binding<String>, letters: Bool = false) -> some View {
        FormTextField(title, text: value, hint: letters ? "9 letters or digits, optional" : "9 digits, optional")
            .onChange(of: value.wrappedValue) { _, new in
                let clean = letters ? Account.routingCharacters(new) : Account.digits(new, limit: Account.routingNumberLength)
                if clean != new { value.wrappedValue = clean }
            }
        if !value.wrappedValue.isEmpty && value.wrappedValue.count != Account.routingNumberLength {
            Text(letters ? "This number has exactly 9 characters." : "A routing number has exactly 9 digits.")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
    }

    /// Every loan and lease has to say what it costs each month. Its due date is always set, so the loan lands in Bills.
    private var loanProblem: String? {
        guard type.group == .loans else { return nil }
        return monthlyPayment > 0 ? nil : "Enter the monthly payment. It is required."
    }

    /// A card can't owe more than its credit limit, from the starting balance or once the limit is lowered.
    private var limitProblem: String? {
        guard type.group == .creditCards, creditLimit > 0 else { return nil }
        // A card already over its limit can still have its notes or name changed.
        if let account, account.creditLimit == abs(creditLimit), account.openingBalance == -abs(cardBalance) { return nil }
        let limit = abs(creditLimit)
        if abs(cardBalance) > limit { return "The balance can't be more than the credit limit." }
        if let account, account.isCreditCard {
            let owed = -(account.balance - account.openingBalance - abs(cardBalance))
            if owed > limit { return "With its transactions this card owes \(owed.formatted(.appCurrency)), more than this limit." }
        }
        return nil
    }

    private func save() {
        let target = account ?? Account(name: "", type: type)
        let previousArtworkKey = account.map { ArtworkChoices.key(for: $0) }
        let previousPaySourceKey = account.map { BillPaySources.key(for: $0) }
        target.name = String(name.trimmingCharacters(in: .whitespaces).prefix(Account.maxNameLength))
        target.type = type
        // Cash on hand has no bank details.
        target.institution = type == .cash ? "" : institution
        target.accountNumber = type == .cash ? "" : Account.digits(accountNumber, limit: Account.numberLimit(for: type))
        target.routingNumber = ""
        if type == .checking {
            target.achRouting = routingNumber
            target.wireRouting = wireRouting
            target.digitalRouting = digitalRouting
        }
        target.vin = Account.typeHasVIN(type) ? Account.cleanVIN(vin) : ""
        target.photoData = (type.group == .loans || type.group == .assets) ? photoData : nil
        target.loanPurpose = type.group == .loans ? loanPurpose.trimmingCharacters(in: .whitespaces) : ""
        if type.group == .loans {
            // Loans are stored as a negative balance: what you owe.
            target.openingBalance = -abs(owedNow)
            target.originalLoanAmount = abs(originalLoanAmount)
            target.monthlyPayment = abs(monthlyPayment)
            target.payoffDate = hasPayoffDate ? payoffDate : nil
            target.loanStartDate = hasStartDate ? startDate : nil
            target.interestRate = leased ? 0 : max((interestRate ?? 0).doubleValue, 0)
        } else {
            // A card's balance is money owed, so it is stored negative like a loan's.
            if type.group == .creditCards {
                target.openingBalance = -abs(cardBalance)
            } else if !OpeningDeposit.applies(to: type) {
                target.openingBalance = openingBalance
            } else if account != nil, OpeningDeposit.existing(in: target) == nil, target.openingBalance != 0 {
                // An account from before deposits: its starting balance stays a number until you change it.
                target.openingBalance = openingBalance
            }
            target.originalLoanAmount = 0
            target.monthlyPayment = type.group == .creditCards ? abs(monthlyPayment) : 0
            target.payoffDate = nil
            target.loanStartDate = nil
            target.interestRate = type.group == .creditCards ? max((interestRate ?? 0).doubleValue, 0) : 0
        }
        target.creditLimit = type.group == .creditCards ? abs(creditLimit) : 0
        target.isLease = type == .autoLoan && isLease
        target.notes = notes
        if account == nil { modelContext.insert(target) }
        // Money you own starts as a real deposit: payee Deposit, category Deposit, method Bank Deposit.
        if type.group != .loans && type.group != .creditCards && OpeningDeposit.applies(to: type) {
            let hasLegacy = account != nil && OpeningDeposit.existing(in: target) == nil && target.openingBalance != 0
            if !hasLegacy {
                // A starting balance below zero can't be a deposit, so it stays a number.
                if openingBalance < 0 { target.openingBalance = openingBalance; OpeningDeposit.set(0, for: target, in: modelContext) }
                else { target.openingBalance = 0; OpeningDeposit.set(openingBalance, for: target, in: modelContext) }
            }
        }
        LoanBill.sync(target, dueDate: type.group == .loans || (type.group == .creditCards && hasDueDate) ? dueDate : nil, in: modelContext)
        ArtworkChoices.set(artworkTheme, for: target, previousKey: previousArtworkKey, in: modelContext)
        // Bills that came out of this account, and the outlook's account choice, follow a rename.
        if let previousPaySourceKey {
            BillPaySources.accountChanged(from: previousPaySourceKey, to: BillPaySources.key(for: target), in: modelContext)
            MonthOutlook.accountChanged(from: previousPaySourceKey, to: BillPaySources.key(for: target))
        }
        modelContext.saveNow()
        if type == .checking && isPrimary {
            PrimaryChecking.set(target, in: modelContext)
        } else if target.isPrimaryChecking {
            PrimaryChecking.set(nil, in: modelContext)
        }
        modelContext.saveNow()
        dismiss()
    }
}
