import Foundation

extension FormatStyle where Self == Decimal.FormatStyle.Currency {
    /// Currency style using the currency chosen in Settings (or the device's currency by default).
    static var appCurrency: Self {
        .currency(code: AppSettings.shared.effectiveCurrencyCode)
    }
}

import SwiftUI

/// Every dollar amount you type goes in one of these. An empty field always shows a grey "$0.00" (in your currency)
/// so it is clear what belongs there, and a field cleared or left at zero goes back to showing it.
struct CurrencyField: View {
    let title: String
    @Binding var value: Decimal?

    init(_ title: String, value: Binding<Decimal?>) {
        self.title = title
        _value = value
    }

    /// For amounts that can't be empty. Zero shows as the placeholder instead of as typed text.
    init(_ title: String, amount: Binding<Decimal>) {
        self.title = title
        _value = Binding(
            get: { amount.wrappedValue == 0 ? nil : amount.wrappedValue },
            set: { amount.wrappedValue = $0 ?? 0 }
        )
    }

    var body: some View {
        TextField(title, value: $value, format: .appCurrency, prompt: Text(Decimal(0), format: .appCurrency))
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
    }
}

/// A text field for forms. On the Mac a grouped form shows the title as a label and, with no prompt, again as the
/// placeholder, so the word appears twice. This shows it once: as the label, with `hint` (usually empty) as the placeholder.
/// Pass `showsLabel: false` under a section header that already names it. On iPhone and iPad the title is the placeholder.
struct FormTextField: View {
    let title: String
    @Binding var text: String
    var hint = ""
    var axis: Axis = .horizontal
    var showsLabel = true

    init(_ title: String, text: Binding<String>, hint: String = "", axis: Axis = .horizontal, showsLabel: Bool = true) {
        self.title = title
        _text = text
        self.hint = hint
        self.axis = axis
        self.showsLabel = showsLabel
    }

    var body: some View {
        #if os(macOS)
        if showsLabel {
            TextField(title, text: $text, prompt: Text(hint), axis: axis)
        } else {
            TextField(title, text: $text, prompt: Text(hint.isEmpty ? title : hint), axis: axis)
                .labelsHidden()
        }
        #else
        TextField(hint.isEmpty || showsLabel ? title : hint, text: $text, axis: axis)
        #endif
    }
}
