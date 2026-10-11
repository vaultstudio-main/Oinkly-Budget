import SwiftUI
import SwiftData

/// Rows for every payment method: your own first, then the built-in ones grouped. Use inside a `Picker` whose
/// selection is a `PaymentChoice?`.
struct PaymentTypeOptions: View {
    @Query(sort: \CustomPaymentMethod.name) private var allCustom: [CustomPaymentMethod]

    /// Keeps a method that was since deleted from vanishing out of the picker for a transaction that still shows it.
    var keeping: PaymentChoice?

    var body: some View {
        Text("None").tag(PaymentChoice?.none)
        let mine = allCustom.live
        if !mine.isEmpty {
            Section("My Payment Methods") {
                ForEach(mine) { method in
                    Label(method.name, systemImage: method.symbol).tag(Optional(PaymentChoice.custom(method)))
                }
            }
        }
        ForEach(PaymentGroup.allCases) { group in
            Section(group.title) {
                ForEach(group.types) { type in
                    Label(type.title, systemImage: type.symbol).tag(Optional(PaymentChoice.type(type)))
                }
            }
        }
    }
}
