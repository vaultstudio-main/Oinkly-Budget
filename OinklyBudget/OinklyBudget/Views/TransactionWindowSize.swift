import SwiftUI

extension View {
    /// The one size shared by the windows where a transaction is entered and a receipt can be attached: a new transaction, a credit
    /// card charge, a cash transaction and Pay a Bill. They are alike on purpose: the form on the left and the receipt on the right,
    /// so the form seldom has to scroll.
    func transactionWindowFrame() -> some View {
        frame(width: 1000, height: 700)
    }
}
