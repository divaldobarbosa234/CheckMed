import SwiftUI

struct PhilView: View {
    var size: CGFloat = 112
    var mood: CompanionMood = .idle

    var body: some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(CheckMedTheme.primaryShadow)
                .frame(width: 18, height: 22)
                .rotationEffect(.degrees(-18))
                .offset(x: size * 0.04, y: -size * 0.02)

            ZStack {
                RoundedRectangle(cornerRadius: size / 2.1, style: .continuous)
                    .fill(CheckMedTheme.primary)
                    .overlay(alignment: .bottom) {
                        Capsule()
                            .fill(CheckMedTheme.belly)
                            .frame(width: size * 0.62, height: size * 0.48)
                            .offset(y: -size * 0.08)
                    }

                HStack(spacing: size * 0.12) {
                    eye
                    eye
                }
                .offset(y: -size * 0.12)

                Triangle()
                    .fill(CheckMedTheme.beak)
                    .frame(width: 12, height: 8)
                    .offset(y: size * 0.02)

                HStack {
                    Capsule().fill(CheckMedTheme.cheek.opacity(0.85)).frame(width: 12, height: 8)
                    Spacer()
                    Capsule().fill(CheckMedTheme.cheek.opacity(0.85)).frame(width: 12, height: 8)
                }
                .padding(.horizontal, size * 0.16)
                .offset(y: size * 0.08)
            }
            .frame(width: size, height: size)
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(CheckMedTheme.primaryShadow)
                    .frame(height: 6)
            }
            .clipShape(RoundedRectangle(cornerRadius: size / 2.1, style: .continuous))
        }
        .frame(width: size, height: size * 1.12)
        .accessibilityLabel("Phil, the CheckMed companion")
        .phaseAnimator([0.0, -8.0], trigger: mood) { view, value in
            view
                .offset(y: value)
                .rotationEffect(.degrees(mood == .skip ? -8 : 0))
                .scaleEffect(mood == .celebrate || mood == .complete ? 1.06 : 1)
        } animation: { _ in
            .easeInOut(duration: mood == .celebrate ? 0.28 : 0.9)
        }
    }

    private var eye: some View {
        Circle()
            .fill(Color.white)
            .frame(width: max(10, size * 0.16), height: max(10, size * 0.16))
            .overlay {
                Circle()
                    .fill(CheckMedTheme.ink)
                    .frame(width: max(5, size * 0.07), height: max(5, size * 0.07))
            }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    PhilView(size: 148)
        .padding()
        .background(CheckMedTheme.background)
}
