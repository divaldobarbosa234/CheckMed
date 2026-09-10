import SwiftUI

enum PhilPose: Equatable {
    case idle
    case pointingDown
}

struct PhilView: View {
    var size: CGFloat = 112
    var mood: CompanionMood = .idle
    var pose: PhilPose = .idle
    var smiling = false

    private var showSmile: Bool { (smiling || pose == .pointingDown) && mood != .sad }
    private var isSad: Bool { mood == .sad }

    var body: some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(CheckMedTheme.beak)
                .frame(width: 18, height: 22)
                .rotationEffect(.degrees(-18))
                .offset(x: size * 0.04, y: -size * 0.02)

            ZStack {
                RoundedRectangle(cornerRadius: size / 2.1, style: .continuous)
                    .fill(CheckMedTheme.philYellow)
                    .overlay(alignment: .bottom) {
                        Capsule()
                            .fill(CheckMedTheme.belly)
                            .frame(width: size * 0.62, height: size * 0.48)
                            .offset(y: -size * 0.08)
                    }

                HStack(spacing: size * 0.12) {
                    eye(lookDown: pose == .pointingDown || isSad)
                    eye(lookDown: pose == .pointingDown || isSad)
                }
                .offset(y: -size * 0.12)

                if isSad {
                    HStack(spacing: size * 0.14) {
                        Capsule()
                            .fill(CheckMedTheme.ink.opacity(0.55))
                            .frame(width: size * 0.16, height: max(2, size * 0.028))
                            .rotationEffect(.degrees(18))
                        Capsule()
                            .fill(CheckMedTheme.ink.opacity(0.55))
                            .frame(width: size * 0.16, height: max(2, size * 0.028))
                            .rotationEffect(.degrees(-18))
                    }
                    .offset(y: -size * 0.24)
                }

                Triangle()
                    .fill(CheckMedTheme.beak)
                    .frame(width: 12, height: 8)
                    .offset(y: size * 0.02)

                HStack {
                    Capsule().fill(CheckMedTheme.cheek.opacity(isSad ? 0.4 : 0.85)).frame(width: 12, height: 8)
                    Spacer()
                    Capsule().fill(CheckMedTheme.cheek.opacity(isSad ? 0.4 : 0.85)).frame(width: 12, height: 8)
                }
                .padding(.horizontal, size * 0.16)
                .offset(y: size * 0.08)

                if showSmile {
                    SmileArc()
                        .stroke(CheckMedTheme.ink.opacity(0.72), style: StrokeStyle(lineWidth: max(2, size * 0.028), lineCap: .round))
                        .frame(width: size * 0.22, height: size * 0.1)
                        .offset(y: size * 0.16)
                } else if isSad {
                    FrownArc()
                        .stroke(CheckMedTheme.ink.opacity(0.72), style: StrokeStyle(lineWidth: max(2, size * 0.028), lineCap: .round))
                        .frame(width: size * 0.2, height: size * 0.1)
                        .offset(y: size * 0.18)
                }
            }
            .frame(width: size, height: size)
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(CheckMedTheme.beak)
                    .frame(height: 6)
            }
            .clipShape(RoundedRectangle(cornerRadius: size / 2.1, style: .continuous))

            if pose == .pointingDown {
                pointingArm
            }
        }
        .frame(width: pose == .pointingDown ? size * 1.22 : size, height: size * 1.16)
        .rotationEffect(.degrees(pose == .pointingDown ? 6 : (isSad ? -5 : 0)))
        .accessibilityLabel("Phil, the CheckMed companion")
    }

    private var pointingArm: some View {
        Capsule(style: .continuous)
            .fill(CheckMedTheme.philYellow)
            .frame(width: size * 0.16, height: size * 0.42)
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(CheckMedTheme.beak)
                    .frame(width: size * 0.16, height: size * 0.12)
            }
            .rotationEffect(.degrees(42))
            .offset(x: size * 0.46, y: size * 0.62)
            .accessibilityHidden(true)
    }

    private func eye(lookDown: Bool) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: max(10, size * 0.16), height: max(10, size * 0.16))
            .overlay {
                Circle()
                    .fill(CheckMedTheme.ink)
                    .frame(width: max(5, size * 0.07), height: max(5, size * 0.07))
                    .offset(y: lookDown ? max(2, size * 0.02) : 0)
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

private struct SmileArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.15),
            radius: rect.width / 2,
            startAngle: .degrees(22),
            endAngle: .degrees(158),
            clockwise: false
        )
        return path
    }
}

private struct FrownArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.05),
            radius: rect.width / 2,
            startAngle: .degrees(200),
            endAngle: .degrees(340),
            clockwise: false
        )
        return path
    }
}

/// Phil with glasses — transparent PNG, no frame, sized to sit on the pastel canvas.
struct PhilGlassesImage: View {
    var size: CGFloat = 80

    var body: some View {
        Image("phil_glasses")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// 2D doctor Phil — transparent PNG, no clip, stroke, or shadow.
struct PhilDoctor2DImage: View {
    var size: CGFloat = 80

    var body: some View {
        Image("phil_doctor_2d")
            .resizable()
            .interpolation(.high)
            .renderingMode(.original)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Phil thinking — transparent PNG, no clip, stroke, or shadow.
struct PhilThinkingImage: View {
    var size: CGFloat = 44

    var body: some View {
        Image("phil_thinking")
            .resizable()
            .interpolation(.high)
            .renderingMode(.original)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
/// Phil reading a book — transparent PNG, no clip, stroke, or shadow.
struct PhilReadingImage: View {
    var size: CGFloat = 112

    var body: some View {
        Image("phil_reading")
            .resizable()
            .interpolation(.high)
            .renderingMode(.original)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 24) {
        PhilView(size: 148)
        PhilView(size: 148, pose: .pointingDown, smiling: true)
    }
    .padding()
    .background(CheckMedTheme.background)
}
