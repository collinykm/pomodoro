import SwiftUI

// MARK: - Palette

/// Neo-brutalist palette: cream paper, hard black ink, and a few loud accent slabs.
enum Ink {
    static let paper   = Color(hex: 0xFFFBF0)
    static let black   = Color(hex: 0x111111)
    static let coral   = Color(hex: 0xFF6B6B)
    static let yellow  = Color(hex: 0xFFD93D)
    static let lavender = Color(hex: 0xB8A9F5)
    static let mint    = Color(hex: 0x9BE8C9)
    static let sky     = Color(hex: 0x8ED1FC)
    static let peach   = Color(hex: 0xFFB86B)
    static let pink    = Color(hex: 0xF8A5D1)
    static let lime    = Color(hex: 0xC8F26B)
    static let white   = Color.white
    static let muted   = Color(hex: 0x6B6B6B)

    /// Fixed-order categorical palette for subjects and charts. Assigned in order, never cycled.
    static let subjectPalette: [UInt32] = [
        0xFF6B6B, 0xFFD93D, 0xB8A9F5, 0x9BE8C9, 0x8ED1FC, 0xFFB86B, 0xF8A5D1, 0xC8F26B
    ]
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    init(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        let value = UInt32(s, radix: 16) ?? 0x111111
        self.init(hex: value)
    }
}

// MARK: - Typography

enum TypeStyle {
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .default)
    }
    static func heading(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .default)
    }
    static func label(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .bold, design: .default)
    }
    static func body(_ size: CGFloat = 14) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }
    static func mono(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .rounded).monospacedDigit()
    }
}

// MARK: - Backgrounds

/// The dotted paper grid behind every screen.
struct DotGrid: View {
    var spacing: CGFloat = 18
    var dot: CGFloat = 2
    var body: some View {
        Canvas { context, size in
            var x: CGFloat = spacing / 2
            while x < size.width {
                var y: CGFloat = spacing / 2
                while y < size.height {
                    let rect = CGRect(x: x - dot / 2, y: y - dot / 2, width: dot, height: dot)
                    context.fill(Path(ellipseIn: rect), with: .color(Ink.black.opacity(0.28)))
                    y += spacing
                }
                x += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

struct PaperBackground: View {
    var body: some View {
        ZStack {
            Ink.paper
            DotGrid()
        }
        .ignoresSafeArea()
    }
}

// MARK: - Brutal card

struct BrutalCard: ViewModifier {
    var fill: Color
    var border: CGFloat
    var shadow: CGFloat
    var rotation: Double

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    Rectangle()
                        .fill(Ink.black)
                        .offset(x: shadow, y: shadow)
                    Rectangle()
                        .fill(fill)
                        .overlay(Rectangle().stroke(Ink.black, lineWidth: border))
                }
            }
            .rotationEffect(.degrees(rotation))
    }
}

extension View {
    /// A flat slab with a hard black border and an offset solid shadow.
    func brutalCard(_ fill: Color = Ink.white, border: CGFloat = 3, shadow: CGFloat = 6, rotation: Double = 0) -> some View {
        modifier(BrutalCard(fill: fill, border: border, shadow: shadow, rotation: rotation))
    }
}

// MARK: - Buttons

struct BrutalButtonStyle: ButtonStyle {
    var fill: Color = Ink.coral
    var foreground: Color = Ink.black
    var shadow: CGFloat = 5
    var size: CGFloat = 13
    var horizontalPadding: CGFloat = 22
    var verticalPadding: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size, weight: .black))
            .textCase(.uppercase)
            .tracking(1.2)
            .foregroundStyle(foreground)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background {
                ZStack {
                    Rectangle()
                        .fill(Ink.black)
                        .offset(x: configuration.isPressed ? 0 : shadow,
                                y: configuration.isPressed ? 0 : shadow)
                    Rectangle()
                        .fill(fill)
                        .overlay(Rectangle().stroke(Ink.black, lineWidth: 3))
                }
            }
            .contentShape(Rectangle())
            .offset(x: configuration.isPressed ? shadow : 0, y: configuration.isPressed ? shadow : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

struct BrutalIconButtonStyle: ButtonStyle {
    var fill: Color = Ink.white
    var side: CGFloat = 40

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: side * 0.4, weight: .black))
            .foregroundStyle(Ink.black)
            .frame(width: side, height: side)
            .background {
                ZStack {
                    Rectangle().fill(Ink.black).offset(x: configuration.isPressed ? 0 : 4, y: configuration.isPressed ? 0 : 4)
                    Rectangle().fill(fill).overlay(Rectangle().stroke(Ink.black, lineWidth: 3))
                }
            }
            .contentShape(Rectangle())
            .offset(x: configuration.isPressed ? 4 : 0, y: configuration.isPressed ? 4 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

// MARK: - Small building blocks

/// A small uppercase label slab like the "SUPER FAST" tags in the mock.
struct Tag: View {
    var text: String
    var fill: Color = Ink.yellow
    var foreground: Color = Ink.black
    var rotation: Double = 0

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .black))
            .textCase(.uppercase)
            .tracking(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Rectangle().fill(fill))
            .overlay(Rectangle().stroke(Ink.black, lineWidth: 2.5))
            .rotationEffect(.degrees(rotation))
    }
}

/// Section heading with a coral bar on the left, as in the mock's description card.
struct SectionTitle: View {
    var text: String
    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Ink.coral).frame(width: 6, height: 22)
            Text(text)
                .font(TypeStyle.heading(18))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(Ink.black)
            Spacer()
        }
    }
}

/// The scrolling red marquee strip at the very top.
struct MarqueeBar: View {
    var items: [String]
    @State private var offset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let text = items.map { "  \($0)  ★" }.joined()
            HStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { _ in
                    Text(text)
                        .font(.system(size: 11, weight: .black))
                        .tracking(1.5)
                        .foregroundStyle(Ink.black)
                        .fixedSize()
                }
            }
            .offset(x: offset)
            .onAppear {
                withAnimation(.linear(duration: 40).repeatForever(autoreverses: false)) {
                    offset = -geo.size.width
                }
            }
        }
        .frame(height: 28)
        .background(Ink.coral)
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.black).frame(height: 3) }
        .clipped()
    }
}

/// A chunky progress bar with a hard border.
struct BrutalProgressBar: View {
    var progress: Double
    var fill: Color = Ink.coral
    var height: CGFloat = 22

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Ink.white)
                Rectangle()
                    .fill(fill)
                    .frame(width: max(0, min(1, progress)) * geo.size.width)
                    .animation(.linear(duration: 0.5), value: progress)
            }
            .overlay(Rectangle().stroke(Ink.black, lineWidth: 3))
        }
        .frame(height: height)
    }
}

// MARK: - Formatting helpers

enum Fmt {
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%02d:%02d", m, sec)
    }

    /// "2h 15m", "45m", "0m"
    static func duration(_ seconds: Int) -> String {
        let m = max(0, seconds) / 60
        let h = m / 60, rem = m % 60
        if h > 0 && rem > 0 { return "\(h)h \(rem)m" }
        if h > 0 { return "\(h)h" }
        return "\(rem)m"
    }

    static func hours(_ seconds: Int) -> Double {
        Double(seconds) / 3600
    }
}
