import SwiftUI

/// Rows for every payment method, grouped. Use inside a `Picker` whose selection is a `PaymentType?`.
struct PaymentTypeOptions: View {
    var body: some View {
        Text("None").tag(PaymentType?.none)
        ForEach(PaymentGroup.allCases) { group in
            Section(group.title) {
                ForEach(group.types) { type in
                    Label(type.title, systemImage: type.symbol).tag(Optional(type))
                }
            }
        }
    }
}
