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
    @State private var loanPurpose: String
    @State private var vin: String
    @State private var originalLoanAmount: Decimal
    @State private var monthlyPayment: Decimal
    @State private var owedNow: Decimal
    @State private var hasPayoffDate: Bool
    @State private var payoffDate: Date
    @State private var photoData: Data?
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var openingBalance: Decimal
    @State private var notes: String

    init(account: Account?, initialType: AccountType = .checking) {
        self.account = account
        _name = State(initialValue: account?.name ?? "")
        _type = State(initialValue: account?.type ?? initialType)
        _institution = State(initialValue: account?.institution ?? "")
        _accountNumber = State(initialValue: account?.accountNumber ?? "")
        _routingNumber = State(initialValue: account?.routingNumber ?? "")
        _loanPurpose = State(initialValue: account?.loanPurpose ?? "")
        _vin = State(initialValue: account?.vin ?? "")
        _originalLoanAmount = State(initialValue: account?.originalLoanAmount ?? 0)
        _monthlyPayment = State(initialValue: account?.monthlyPayment ?? 0)
        _owedNow = State(initialValue: abs(account?.openingBalance ?? 0))
        _hasPayoffDate = State(initialValue: account?.payoffDate != nil)
        _payoffDate = State(initialValue: account?.payoffDate ?? Calendar.current.date(byAdding: .year, value: 3, to: .now) ?? .now)
        _photoData = State(initialValue: account?.photoData)
        _openingBalance = State(initialValue: account?.openingBalance ?? 0)
        _notes = State(initialValue: account?.notes ?? "")
    }

    private var isDebt: Bool { type.group.isLiability }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(AccountGroup.setupOrder) { group in
                            Section(group.title) {
                                ForEach(group.accountTypes) { Text($0.title).tag($0) }
                            }
                        }
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
                    if type.group == .loans {
                        TextField("What is this loan for? (e.g. 2021 Honda Civic)", text: $loanPurpose)
                    }
                    if Account.typeHasVIN(type) {
                        TextField("VIN (17 characters)", text: $vin)
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
                        amountRow("Original loan amount", $originalLoanAmount)
                        amountRow("Monthly payment", $monthlyPayment)
                        amountRow("Amount owed now", $owedNow)
                        Toggle("Set a payoff date", isOn: $hasPayoffDate.animation())
                        if hasPayoffDate {
                            DatePicker("Payoff date", selection: $payoffDate, in: Date.now..., displayedComponents: .date)
                        }
                    } else {
                        HStack {
                            Text("Opening balance")
                            Spacer()
                            TextField("", value: $openingBalance, format: .appCurrency)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                if type.group == .loans || type.group == .assets {
                    Section("Photo") {
                        if let image = AccountPhoto.image(from: photoData) {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        PhotosPicker(selection: $pickedPhoto, matching: .images) {
                            Label(photoData == nil ? "Choose Photo…" : "Change Photo…", systemImage: "photo")
                        }
                        if photoData != nil {
                            Button("Remove Photo", role: .destructive) { photoData = nil; pickedPhoto = nil }
                        }
                    }
                }

                Section("Bank Details") {
                    TextField("Institution", text: $institution)
                    TextField("Account number (up to 17 digits)", text: $accountNumber)
                        .onChange(of: accountNumber) { _, new in
                            let clean = Account.digits(new, limit: Account.maxAccountNumberLength)
                            if clean != new { accountNumber = clean }
                        }
                    TextField("Routing number (9 digits)", text: $routingNumber)
                        .onChange(of: routingNumber) { _, new in
                            let clean = Account.digits(new, limit: Account.routingNumberLength)
                            if clean != new { routingNumber = clean }
                        }
                    if !routingNumber.isEmpty && routingNumber.count != Account.routingNumberLength {
                        Text("A routing number has exactly 9 digits.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
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
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 600)
        #endif
    }

    private func amountRow(_ title: String, _ value: Binding<Decimal>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("", value: value, format: .appCurrency)
                .multilineTextAlignment(.trailing)
        }
    }

    private func save() {
        let target = account ?? Account(name: "", type: type)
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.type = type
        target.institution = institution
        target.accountNumber = Account.digits(accountNumber, limit: Account.maxAccountNumberLength)
        target.routingNumber = Account.digits(routingNumber, limit: Account.routingNumberLength)
        target.vin = Account.typeHasVIN(type) ? Account.cleanVIN(vin) : ""
        target.photoData = (type.group == .loans || type.group == .assets) ? photoData : nil
        target.loanPurpose = type.group == .loans ? loanPurpose.trimmingCharacters(in: .whitespaces) : ""
        if type.group == .loans {
            // Loans are stored as a negative balance: what you owe.
            target.openingBalance = -abs(owedNow)
            target.originalLoanAmount = abs(originalLoanAmount)
            target.monthlyPayment = abs(monthlyPayment)
            target.payoffDate = hasPayoffDate ? payoffDate : nil
        } else {
            target.openingBalance = openingBalance
            target.originalLoanAmount = 0
            target.monthlyPayment = 0
            target.payoffDate = nil
        }
        target.notes = notes
        if account == nil { modelContext.insert(target) }
        dismiss()
    }
}
