import SwiftUI
import SwiftData

private func percentText(_ fraction: Double?) -> String? {
    fraction.map { ($0 >= 0 ? "+" : "") + $0.formatted(.percent.precision(.fractionLength(1))) }
}

/// The Holdings panel on an investment account's register.
struct HoldingsPanel: View {
    let account: Account
    @State private var sheet: HoldingSheet?

    var body: some View {
        let summary = HoldingsLedger.summary(for: account)
        let holdings = account.holdings.live.sorted { $0.marketValue > $1.marketValue }

        Panel(title: "Holdings") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 28) {
                    stat("Holdings Value", summary.marketValue)
                    stat("Cost Basis", summary.costBasis)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("UNREALIZED GAIN").font(.caption2).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Text(summary.gain, format: .appCurrency).foregroundStyle(summary.gain >= 0 ? Theme.green : Theme.red)
                            if let text = percentText(summary.gainFraction) { Text(text).foregroundStyle(.secondary) }
                        }
                    }
                    stat("Account Value", summary.accountValue)
                    if abs((summary.unallocated as NSDecimalNumber).doubleValue) >= 0.005 {
                        stat("Not In A Holding", summary.unallocated)
                    }
                    Spacer()
                    Button("Update Account Value…") { sheet = .accountValue }
                    Button("Add Holding…") { sheet = .add }
                }

                if holdings.isEmpty {
                    Text("No holdings yet. Add the funds or stocks in this account, or use Update Account Value to enter what it's worth today.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Grid(alignment: .trailing, horizontalSpacing: 18, verticalSpacing: 8) {
                        GridRow {
                            Text("Holding").gridColumnAlignment(.leading)
                            Text("Shares")
                            Text("Price")
                            Text("Value")
                            Text("Cost")
                            Text("Gain")
                            Text("")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Divider().gridCellUnsizedAxes(.horizontal)
                        ForEach(holdings) { holding in
                            if holding.isLive { row(holding) }
                        }
                    }
                    Text("Updating a price records the change as a gain or loss on the account.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .holdingSheets($sheet, account: account)
    }

    private func stat(_ title: String, _ amount: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(.caption2).foregroundStyle(.secondary)
            Text(amount, format: .appCurrency)
        }
    }

    private func row(_ holding: Holding) -> some View {
        GridRow {
            VStack(alignment: .leading, spacing: 1) {
                Text(holding.name)
                if !holding.symbol.isEmpty { Text(holding.symbol).font(.caption).foregroundStyle(.secondary) }
            }
            .gridColumnAlignment(.leading)
            Text(holding.shares, format: .number.precision(.fractionLength(0...6)))
            VStack(alignment: .trailing, spacing: 1) {
                Text(holding.price, format: .appCurrency)
                Text(holding.priceDate, format: .dateTime.month(.abbreviated).day()).font(.caption2).foregroundStyle(.secondary)
            }
            Text(holding.marketValue, format: .appCurrency)
            Text(holding.costBasis, format: .appCurrency).foregroundStyle(.secondary)
            VStack(alignment: .trailing, spacing: 1) {
                Text(holding.gain, format: .appCurrency)
                if let text = percentText(holding.gainFraction) { Text(text).font(.caption2) }
            }
            .foregroundStyle(holding.gain >= 0 ? Theme.green : Theme.red)
            HStack(spacing: 6) {
                Button("Update Price") { sheet = .price(holding) }
                Button("Edit") { sheet = .edit(holding) }
            }
            .controlSize(.small)
        }
    }
}

