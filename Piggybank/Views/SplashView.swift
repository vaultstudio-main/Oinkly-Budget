import SwiftUI

enum Brand {
    static let gradient = LinearGradient(
        colors: [Color(red: 0.16, green: 0.78, blue: 0.62), Color(red: 0.10, green: 0.38, blue: 0.78)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// Full-screen launch splash shown on iPhone and iPad. The Mac has its own boot window.
struct SplashView: View {
    @State private var appeared = false

    var body: some View {
        ZStack {
            Brand.gradient
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image("BootPig")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 150)
                    .shadow(color: .black.opacity(0.2), radius: 20, y: 10)

                Text("Piggybank Financial")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)

                Text("MOBILE")
                    .font(.title3.weight(.medium))
                    .tracking(6)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .scaleEffect(appeared ? 1 : 0.85)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.8)) { appeared = true }
        }
    }
}

#Preview {
    SplashView()
}
