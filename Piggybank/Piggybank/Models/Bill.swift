import Foundation
import SwiftData

/// A bill you expect to pay: what it is, how much, when it is first due and how often it repeats.
/// Bills are for planning and reminders; paying one is still a normal transaction in an account.
@Model
final class Bill {
    var name: String = ""
    /// Always positive.
    var amount: Decimal = 0
    /// Raw value of `BillFrequency`. Never rename those cases.
    var frequencyRaw: String = BillFrequency.monthly.rawValue
    /// The first due date. Later due dates are worked out from it.
    var dueDate: Date = Date.now
    /// How many days ahead a reminder should go out.
    var remindDaysBefore: Int = 3
    var remindersOn: Bool = true
    /// Important bills are listed in the Bills sidebar and raise an alert as the due date gets close.
    var isImportant: Bool = false
    var notes: String = ""
    /// The due dates (start of day) already marked paid.
    var paidDates: [Date] = []
    /// Where payments of this bill show up in reports, such as Phone & Internet. Optional.
    var category: Category?
    /// Set when a loan account created this bill from its payment due date.
    var loan: Account?
    /// A picture of the bill, such as the statement or what it is for. Kept out of the main database file.
    @Attribute(.externalStorage) var photoData: Data?
    /// Payments made with Pay a Bill. Cleared when a payment is deleted.
    @Relationship(deleteRule: .nullify, inverse: \Transaction.paidBill)
    var payments: [Transaction] = []
    var createdAt: Date = Date.now

    init(name: String, amount: Decimal, frequency: BillFrequency, dueDate: Date, remindDaysBefore: Int = 3, remindersOn: Bool = true, isImportant: Bool = false, notes: String = "") {
        self.name = name
        self.amount = amount
        self.frequencyRaw = frequency.rawValue
        self.dueDate = Calendar.current.startOfDay(for: dueDate)
        self.remindDaysBefore = remindDaysBefore
        self.remindersOn = remindersOn
        self.isImportant = isImportant
        self.notes = notes
    }

    /// The photo to show: the bill's own, or else the photo of the loan that created it.
    var displayPhotoData: Data? {
        if let photoData { return photoData }
        guard let loan, loan.isLive else { return nil }
        return loan.photoData
    }

    var frequency: BillFrequency {
        get { BillFrequency(rawValue: frequencyRaw) ?? .monthly }
        set { frequencyRaw = newValue.rawValue }
    }

    func isPaid(on day: Date, calendar: Calendar = .current) -> Bool {
        paidDates.contains { calendar.isDate($0, inSameDayAs: day) }
    }

    func setPaid(_ paid: Bool, on day: Date, calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: day)
        paidDates.removeAll { calendar.isDate($0, inSameDayAs: start) }
        if paid { paidDates.append(start) }
    }
}
