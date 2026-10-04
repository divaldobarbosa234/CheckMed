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

    private var libraryAsset: String {
        if pose == .pointingDown {
            return "phil_thinking"
        }
        switch mood {
        case .sad, .skip:
            return "phil_sick"
        case .celebrate, .complete:
            return "phil_onboarding_05_healthy"
        case .idle:
            return smiling ? "phil_doctor_2d" : "phil_glasses"
        }
    }

    var body: some View {
        PhilLibraryImage(asset: libraryAsset, size: size)
        .accessibilityLabel("Cooper, the Conny Cooper companion")
    }
}

/// Real Phil artwork from the app asset library.
struct PhilLibraryImage: View {
    let asset: String
    var size: CGFloat

    var body: some View {
        Image(asset)
            .resizable()
            .interpolation(.high)
            .renderingMode(.original)
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
            .accessibilityHidden(true)
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
            .interpolation(.medium)
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
