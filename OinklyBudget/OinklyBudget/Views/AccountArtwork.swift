import SwiftUI

/// What an account (or bill) looks like when the user hasn't chosen a photo: a small flat illustration, drawn in code,
/// on a gradient that matches the account's group. Every account type has one so the app looks the same everywhere.
enum ArtworkKind {
    case bank, savings, wallet, card, medical, house, car, boat, graduation, loan, briefcase
    case chart, retirement, crypto, gem, box, bill
}

extension AccountType {
    var artworkKind: ArtworkKind {
        switch self {
        case .checking, .moneyMarket, .certificateOfDeposit: .bank
        case .savings: .savings
        case .cash, .paymentApp: .wallet
        case .prepaidCard, .creditCard, .storeCard: .card
        case .healthSavings, .flexSpending, .medicalDebt: .medical
        case .mortgage, .homeEquity, .realEstate: .house
        case .autoLoan, .vehicle: .car
        case .vehicleLoan: .boat
        case .studentLoan, .education529: .graduation
        case .loan, .personalLoan, .lineOfCredit, .otherDebt: .loan
        case .businessLoan, .businessAsset: .briefcase
        case .investment, .brokerage: .chart
        case .retirement401k, .traditionalIRA, .rothIRA, .pension, .annuity: .retirement
        case .crypto: .crypto
        case .valuables: .gem
        case .asset: .box
        }
    }
}

/// The default picture for an account type, or for a bill that has no account behind it.
struct AccountArtwork: View {
    private let kind: ArtworkKind
    private let colors: (top: Color, bottom: Color)

    init(type: AccountType) {
        kind = type.artworkKind
        colors = Self.palette(for: type.group)
    }

    /// A bill with no loan behind it.
    init() {
        kind = .bill
        colors = (Color(red: 0.98, green: 0.69, blue: 0.25), Color(red: 0.93, green: 0.40, blue: 0.20))
    }

    private static func palette(for group: AccountGroup) -> (top: Color, bottom: Color) {
        switch group {
        case .checkingSavings: (Color(red: 0.20, green: 0.74, blue: 0.72), Color(red: 0.13, green: 0.45, blue: 0.80))
        case .creditCards: (Color(red: 0.93, green: 0.45, blue: 0.67), Color(red: 0.46, green: 0.31, blue: 0.82))
        case .loans: (Color(red: 0.99, green: 0.62, blue: 0.30), Color(red: 0.88, green: 0.28, blue: 0.38))
        case .investments: (Color(red: 0.35, green: 0.80, blue: 0.45), Color(red: 0.10, green: 0.50, blue: 0.55))
        case .assets: (Color(red: 0.40, green: 0.70, blue: 0.98), Color(red: 0.28, green: 0.34, blue: 0.82))
        }
    }

    var body: some View {
        Canvas { context, size in
            let full = CGRect(origin: .zero, size: size)
            context.fill(Path(full), with: .linearGradient(
                Gradient(colors: [colors.top, colors.bottom]),
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: size.width, y: size.height)))

            // Soft circles for depth.
            let m = min(size.width, size.height)
            context.fill(Path(ellipseIn: CGRect(x: -0.25 * m, y: -0.30 * m, width: 0.9 * m, height: 0.9 * m)),
                         with: .color(.white.opacity(0.13)))
            context.fill(Path(ellipseIn: CGRect(x: size.width - 0.55 * m, y: size.height - 0.45 * m, width: 1.0 * m, height: 1.0 * m)),
                         with: .color(.white.opacity(0.10)))

            let side = m * 0.86
            let scene = Scene(origin: CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2), side: side)
            let deep = Color.black.opacity(0.32)
            // A soft shadow under the object.
            context.fill(Path(ellipseIn: scene.rect(0.2, 0.86, 0.6, 0.07)), with: .color(.black.opacity(0.16)))
            Self.draw(kind, in: context, scene: scene, deep: deep)
        }
        .accessibilityHidden(true)
    }

    // MARK: Drawing

    private struct Scene {
        let origin: CGPoint
        let side: CGFloat
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x * side, y: origin.y + y * side) }
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: origin.x + x * side, y: origin.y + y * side, width: w * side, height: h * side)
        }
        func polygon(_ points: [(CGFloat, CGFloat)]) -> Path {
            var path = Path()
            for (index, p) in points.enumerated() {
                index == 0 ? path.move(to: point(p.0, p.1)) : path.addLine(to: point(p.0, p.1))
            }
            path.closeSubpath()
            return path
        }
        func round(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat) -> Path {
            Path(roundedRect: rect(x, y, w, h), cornerRadius: radius * side)
        }
    }

    private static let white = Color.white
    private static let soft = Color.white.opacity(0.6)

    private static func symbol(_ text: String, in context: GraphicsContext, at p: CGPoint, size: CGFloat, color: Color) {
        context.draw(Text(text).font(.system(size: size, weight: .heavy, design: .rounded)).foregroundColor(color),
                     at: p, anchor: .center)
    }

    private static func draw(_ kind: ArtworkKind, in context: GraphicsContext, scene s: Scene, deep: Color) {
        switch kind {
        case .bank:
            context.fill(s.polygon([(0.08, 0.38), (0.5, 0.12), (0.92, 0.38)]), with: .color(white))
            context.fill(Path(ellipseIn: s.rect(0.45, 0.25, 0.10, 0.10)), with: .color(deep))
            for x in [0.17, 0.35, 0.53, 0.71] {
                context.fill(s.round(x, 0.45, 0.12, 0.34, 0.02), with: .color(white))
            }
            context.fill(s.round(0.10, 0.82, 0.80, 0.07, 0.02), with: .color(soft))

        case .savings:
            context.fill(s.polygon([(0.55, 0.30), (0.64, 0.16), (0.70, 0.36)]), with: .color(soft))
            context.fill(s.round(0.30, 0.74, 0.09, 0.13, 0.02), with: .color(soft))
            context.fill(s.round(0.58, 0.74, 0.09, 0.13, 0.02), with: .color(soft))
            context.fill(Path(ellipseIn: s.rect(0.14, 0.32, 0.66, 0.50)), with: .color(white))
            context.fill(s.round(0.76, 0.50, 0.14, 0.16, 0.04), with: .color(soft))
            context.fill(Path(ellipseIn: s.rect(0.64, 0.46, 0.05, 0.05)), with: .color(deep))
            context.fill(s.round(0.34, 0.37, 0.22, 0.035, 0.015), with: .color(deep))
            context.fill(Path(ellipseIn: s.rect(0.38, 0.08, 0.15, 0.15)), with: .color(white))
            symbol("$", in: context, at: s.point(0.455, 0.155), size: 0.11 * s.side, color: deep)

        case .wallet:
            context.fill(s.round(0.22, 0.14, 0.40, 0.22, 0.03), with: .color(soft))
            context.fill(s.round(0.12, 0.26, 0.76, 0.54, 0.07), with: .color(white))
            context.fill(s.round(0.60, 0.44, 0.28, 0.18, 0.05), with: .color(soft))
            context.fill(Path(ellipseIn: s.rect(0.67, 0.50, 0.06, 0.06)), with: .color(deep))

        case .card:
            var rotated = context
            let center = s.point(0.5, 0.5)
            rotated.translateBy(x: center.x, y: center.y)
            rotated.rotate(by: .degrees(-8))
            rotated.translateBy(x: -center.x, y: -center.y)
            rotated.fill(s.round(0.10, 0.24, 0.80, 0.52, 0.06), with: .color(white))
            rotated.fill(Path(s.rect(0.10, 0.36, 0.80, 0.10)), with: .color(deep))
            rotated.fill(s.round(0.18, 0.56, 0.16, 0.11, 0.02), with: .color(soft))
            rotated.fill(s.round(0.52, 0.60, 0.30, 0.04, 0.02), with: .color(soft))

        case .medical:
            context.fill(s.round(0.16, 0.16, 0.68, 0.68, 0.12), with: .color(white))
            context.fill(s.round(0.43, 0.28, 0.14, 0.44, 0.02), with: .color(deep))
            context.fill(s.round(0.28, 0.43, 0.44, 0.14, 0.02), with: .color(deep))

        case .house:
            context.fill(s.round(0.66, 0.18, 0.09, 0.2, 0.01), with: .color(soft))
            context.fill(s.round(0.20, 0.44, 0.60, 0.40, 0.02), with: .color(soft))
            context.fill(s.polygon([(0.08, 0.48), (0.5, 0.12), (0.92, 0.48)]), with: .color(white))
            context.fill(s.round(0.43, 0.60, 0.14, 0.24, 0.02), with: .color(deep))
            context.fill(s.round(0.27, 0.54, 0.10, 0.10, 0.015), with: .color(white))
            context.fill(s.round(0.63, 0.54, 0.10, 0.10, 0.015), with: .color(white))

        case .car:
            context.fill(s.polygon([(0.27, 0.52), (0.36, 0.30), (0.66, 0.30), (0.76, 0.52)]), with: .color(white))
            context.fill(s.polygon([(0.34, 0.49), (0.40, 0.35), (0.48, 0.35), (0.48, 0.49)]), with: .color(deep))
            context.fill(s.polygon([(0.52, 0.35), (0.62, 0.35), (0.69, 0.49), (0.52, 0.49)]), with: .color(deep))
            context.fill(s.round(0.08, 0.48, 0.84, 0.24, 0.08), with: .color(white))
            context.fill(s.round(0.80, 0.52, 0.08, 0.06, 0.02), with: .color(soft))
            for x in [0.28, 0.72] {
                context.fill(Path(ellipseIn: s.rect(x - 0.10, 0.62, 0.20, 0.20)), with: .color(deep))
                context.fill(Path(ellipseIn: s.rect(x - 0.045, 0.675, 0.09, 0.09)), with: .color(soft))
            }

        case .boat:
            context.fill(s.round(0.485, 0.12, 0.03, 0.52, 0.01), with: .color(white))
            context.fill(s.polygon([(0.53, 0.14), (0.53, 0.58), (0.84, 0.58)]), with: .color(white))
            context.fill(s.polygon([(0.47, 0.26), (0.47, 0.58), (0.20, 0.58)]), with: .color(soft))
            context.fill(s.polygon([(0.12, 0.62), (0.88, 0.62), (0.74, 0.78), (0.26, 0.78)]), with: .color(white))
            context.fill(s.round(0.16, 0.82, 0.30, 0.03, 0.015), with: .color(soft))
            context.fill(s.round(0.54, 0.82, 0.30, 0.03, 0.015), with: .color(soft))

        case .graduation:
            context.fill(s.polygon([(0.24, 0.50), (0.24, 0.68), (0.5, 0.80), (0.76, 0.68), (0.76, 0.50), (0.5, 0.62)]),
                         with: .color(soft))
            context.fill(s.polygon([(0.5, 0.20), (0.94, 0.42), (0.5, 0.64), (0.06, 0.42)]), with: .color(white))
            context.fill(s.round(0.855, 0.44, 0.022, 0.24, 0.01), with: .color(white))
            context.fill(Path(ellipseIn: s.rect(0.82, 0.66, 0.09, 0.09)), with: .color(white))

        case .loan:
            context.fill(s.round(0.24, 0.12, 0.46, 0.70, 0.05), with: .color(white))
            for (index, width) in [0.30, 0.30, 0.18].enumerated() {
                context.fill(s.round(0.32, 0.24 + CGFloat(index) * 0.11, width, 0.04, 0.02), with: .color(deep.opacity(0.7)))
            }
            context.fill(Path(ellipseIn: s.rect(0.50, 0.52, 0.36, 0.36)), with: .color(soft))
            context.fill(Path(ellipseIn: s.rect(0.53, 0.55, 0.30, 0.30)), with: .color(white))
            symbol("$", in: context, at: s.point(0.68, 0.70), size: 0.20 * s.side, color: deep)

        case .briefcase:
            var handle = Path()
            handle.addRoundedRect(in: s.rect(0.37, 0.18, 0.26, 0.2), cornerSize: CGSize(width: 0.04 * s.side, height: 0.04 * s.side))
            context.stroke(handle, with: .color(white), lineWidth: 0.05 * s.side)
            context.fill(s.round(0.12, 0.32, 0.76, 0.52, 0.06), with: .color(white))
            context.fill(Path(s.rect(0.12, 0.52, 0.76, 0.035)), with: .color(deep))
            context.fill(s.round(0.45, 0.48, 0.10, 0.11, 0.015), with: .color(soft))

        case .chart:
            let bars: [(CGFloat, CGFloat)] = [(0.14, 0.26), (0.34, 0.38), (0.54, 0.50), (0.74, 0.64)]
            for (index, bar) in bars.enumerated() {
                context.fill(s.round(bar.0, 0.82 - bar.1, 0.13, bar.1, 0.025), with: .color(index == 3 ? white : soft))
            }
            context.fill(s.round(0.08, 0.84, 0.84, 0.03, 0.015), with: .color(white))

        case .retirement:
            context.fill(Path(ellipseIn: s.rect(0.14, 0.76, 0.72, 0.12)), with: .color(soft))
            context.fill(s.round(0.485, 0.40, 0.03, 0.42, 0.01), with: .color(white))
            var canopy = context
            canopy.clip(to: Path(s.rect(0, 0, 1, 0.46)))
            canopy.fill(Path(ellipseIn: s.rect(0.12, 0.12, 0.76, 0.68)), with: .color(white))
            // Stripes cut into the canopy.
            for x in [0.31, 0.69] as [CGFloat] {
                canopy.fill(s.polygon([(0.5, 0.12), (x - 0.045, 0.46), (x + 0.045, 0.46)]), with: .color(deep.opacity(0.55)))
            }

        case .crypto:
            context.fill(Path(ellipseIn: s.rect(0.16, 0.16, 0.68, 0.68)), with: .color(white))
            context.stroke(Path(ellipseIn: s.rect(0.23, 0.23, 0.54, 0.54)), with: .color(deep.opacity(0.6)), lineWidth: 0.025 * s.side)
            symbol("₿", in: context, at: s.point(0.5, 0.51), size: 0.36 * s.side, color: deep)

        case .gem:
            let outline = s.polygon([(0.28, 0.26), (0.72, 0.26), (0.90, 0.44), (0.5, 0.86), (0.10, 0.44)])
            context.fill(outline, with: .color(white))
            for line in [[(0.10, 0.44), (0.90, 0.44)], [(0.38, 0.44), (0.5, 0.86), (0.62, 0.44)],
                         [(0.28, 0.26), (0.38, 0.44)], [(0.72, 0.26), (0.62, 0.44)], [(0.5, 0.26), (0.38, 0.44)],
                         [(0.5, 0.26), (0.62, 0.44)]] as [[(CGFloat, CGFloat)]] {
                var path = Path()
                for (index, p) in line.enumerated() {
                    index == 0 ? path.move(to: s.point(p.0, p.1)) : path.addLine(to: s.point(p.0, p.1))
                }
                context.stroke(path, with: .color(deep.opacity(0.55)), style: StrokeStyle(lineWidth: 0.02 * s.side, lineJoin: .round))
            }

        case .box:
            context.fill(s.polygon([(0.16, 0.34), (0.5, 0.52), (0.5, 0.86), (0.16, 0.68)]), with: .color(soft))
            context.fill(s.polygon([(0.5, 0.52), (0.84, 0.34), (0.84, 0.68), (0.5, 0.86)]), with: .color(white.opacity(0.82)))
            context.fill(s.polygon([(0.5, 0.14), (0.84, 0.34), (0.5, 0.52), (0.16, 0.34)]), with: .color(white))

        case .bill:
            context.fill(s.round(0.16, 0.20, 0.68, 0.62, 0.07), with: .color(white))
            context.fill(s.round(0.16, 0.20, 0.68, 0.17, 0.07), with: .color(soft))
            context.fill(Path(s.rect(0.16, 0.30, 0.68, 0.07)), with: .color(soft))
            context.fill(s.round(0.30, 0.12, 0.05, 0.14, 0.02), with: .color(white))
            context.fill(s.round(0.65, 0.12, 0.05, 0.14, 0.02), with: .color(white))
            symbol("$", in: context, at: s.point(0.5, 0.60), size: 0.28 * s.side, color: deep)
        }
    }
}

/// The user's photo if there is one, otherwise the account type's drawn picture. Fills whatever frame it is given,
/// so callers clip it.
struct AccountPicture: View {
    let data: Data?
    let type: AccountType?

    var body: some View {
        Group {
            if let image = AccountPhoto.image(from: data) {
                image.resizable().scaledToFill()
            } else if let type {
                AccountArtwork(type: type)
            } else {
                AccountArtwork()
            }
        }
        // A decoration. The account's name and type are read from the text beside it.
        .accessibilityHidden(true)
    }
}
