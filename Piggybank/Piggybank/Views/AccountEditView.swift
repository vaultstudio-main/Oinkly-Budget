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
        _openingBalance = State(initialValue: account?.openingBalance ?? 0)
        _notes = State(initialValue: account?.notes ?? "")
        _isPrimary = State(initialValue: account.map { PrimaryChecking.isPrimary($0, stored: PrimaryChecking.current) } ?? false)
    }

    private var isDebt: Bool { type.group.isLiability }
    /// An auto account chosen as a lease instead of a loan.
    private var leased: Bool { type == .autoLoan && isLease }

    var body: some View {
        NavigationStack {
            Form {
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
                        Text("Your main checking account is pinned to the top of the account list, under Cash on Hand, and marked Primary Checking. Only one account can be primary.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Kind")
                        Spacer()
                        HStack(spacing: 6) {
                            Image(systemName: isDebt ? "arrow.down.right.circle.fill" : "arrow.up.right.circle.fill")
                            Text(isDebt ? "Debt: you owe this" : "Asset: you own this")
                        }
                        .foregroundStyle(isDebt ? Color.red : Color.green)
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
                    if type.group == .loans {
                        amountRow(leased ? "Total lease cost" : "Original loan amount", $originalLoanAmount)
                        amountRow("Monthly payment", $monthlyPayment)
                        amountRow("Amount owed now", $owedNow)
                        if !leased {
                            HStack {
                                Text("Interest rate (APR)")
                                Spacer()
                                TextField("Interest rate", value: $interestRate, format: .number.precision(.fractionLength(0...3)), prompt: Text("0.00"))
                                    .labelsHidden()
                                    .multilineTextAlignment(.trailing)
                                Text("%").foregroundStyle(.secondary)
                            }
                        }
                        Toggle("Set a payment due date", isOn: $hasDueDate.animation())
                        if hasDueDate {
                            DatePicker("Payment due date", selection: $dueDate, displayedComponents: .date)
                            Text("This \(leased ? "lease" : "loan") is added to Bills for the monthly payment, due on this day every month.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Toggle(leased ? "Set the lease start date" : "Set the loan start date", isOn: $hasStartDate.animation())
                        if hasStartDate {
                            DatePicker(leased ? "Lease start date" : "Loan start date", selection: $startDate, in: ...Date.now, displayedComponents: .date)
                        }
                        Toggle(leased ? "Set a lease end date" : "Set a maturity date", isOn: $hasPayoffDate.animation())
                        if hasPayoffDate {
                            DatePicker(leased ? "Lease end date" : "Maturity date", selection: $payoffDate, in: Date.now..., displayedComponents: .date)
                        }
                    } else {
                        if type.group == .creditCards {
                            HStack {
                                Text("Interest rate (APR)")
                                Spacer()
                                TextField("Interest rate", value: $interestRate, format: .number.precision(.fractionLength(0...3)), prompt: Text("0.00"))
                                    .labelsHidden()
                                    .multilineTextAlignment(.trailing)
                                Text("%").foregroundStyle(.secondary)
                            }
                        }
                        if type.group == .creditCards {
                            amountRow("Credit limit", $creditLimit)
                            amountRow("Current balance on card", $cardBalance)
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

                if type.group == .loans || type.group == .assets {
                    Section("Photo") {
                        AccountPicture(data: photoData, type: type)
                            .frame(maxWidth: .infinity)
                            .frame(height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        if photoData == nil {
                            Text("This picture is used until you choose a photo.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        PhotosPicker(selection: $pickedPhoto, matching: .images) {
                            Label(photoData == nil ? "Choose Photo" : "Change Photo", systemImage: "photo")
                        }
                        if photoData != nil {
                            Button("Remove Photo", role: .destructive) { photoData = nil; pickedPhoto = nil }
                        }
                    }
                }

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

                Section("Notes") {
                    FormTextField("Notes", text: $notes, hint: "Add a note", axis: .vertical, showsLabel: false)
                        .lineLimit(3...6)
                }
            }
            .formStyle(.grouped)
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
            .navigationTitle(account == nil ? "New Account" : "Edit Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(minWidth: 460, minHeight: 600)
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

    private func save() {
        let target = account ?? Account(name: "", type: type)
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
            target.openingBalance = type.group == .creditCards ? -abs(cardBalance) : openingBalance
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
        LoanBill.sync(target, dueDate: (type.group == .loans || type.group == .creditCards) && hasDueDate ? dueDate : nil, in: modelContext)
        modelContext.saveNow()
        if type == .checking && isPrimary {
            PrimaryChecking.set(target)
        } else if PrimaryChecking.isStored(target, stored: PrimaryChecking.current) {
            PrimaryChecking.set(nil)
        }
        dismiss()
    }
}
