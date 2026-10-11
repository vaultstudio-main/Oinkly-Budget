import Foundation
import SwiftData

/// A payment method you made yourself, such as "Employee Card" or "Venmo (shared)". It sits next to the built-in ones.
@Model
final class CustomPaymentMethod {
    var name: String = ""
    var symbol: String = "creditcard"
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .nullify, inverse: \Transaction.customMethod)
    var transactions: [Transaction] = []

    init(name: String, symbol: String = "creditcard") {
        self.name = name
        self.symbol = symbol
    }
}

/// One choice in a payment method dropdown: a built-in method or one of yours.
enum PaymentChoice: Hashable {
    case type(PaymentType)
    case custom(CustomPaymentMethod)

    var title: String {
        switch self {
        case .type(let type): type.title
        case .custom(let method): method.isLive ? method.name : ""
        }
    }

    var symbol: String {
        switch self {
        case .type(let type): type.symbol
        case .custom(let method): method.isLive ? method.symbol : "creditcard"
        }
    }

    var isCheck: Bool { self == .type(.check) }
}

extension Transaction {
    /// The method used, built-in or custom. Setting one clears the other.
    var paymentChoice: PaymentChoice? {
        get {
            // A transaction deleted a moment ago can still be on screen. Reading a deleted object is fatal.
            guard isLive else { return nil }
            if let paymentType { return .type(paymentType) }
            if let customMethod, customMethod.isLive { return .custom(customMethod) }
            return nil
        }
        set {
            guard isLive else { return }
            switch newValue {
            case .type(let type): paymentType = type; customMethod = nil
            case .custom(let method): paymentType = nil; customMethod = method
            case nil: paymentType = nil; customMethod = nil
            }
        }
    }

    /// Name of the method, or an empty string if none.
    var paymentTitle: String { paymentChoice?.title ?? "" }
}
