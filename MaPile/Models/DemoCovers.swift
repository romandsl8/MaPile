import SwiftUI

/// Couvertures illustrées des livres fictifs de démonstration (captures d'écran de l'App Store).
/// Dessins originaux générés par l'app : aucune couverture d'éditeur n'est utilisée.
struct DemoCoverStyle {
    enum Layout { case sky, band, frame, sun, split }
    let symbol: String
    let colors: [Color]
    let accent: Color
    let layout: Layout
}

struct DemoCoverArt: View {
    let title: String
    let author: String
    let style: DemoCoverStyle

    private let size = CGSize(width: 600, height: 900)

    var body: some View {
        ZStack {
            background
            decoration
            VStack(spacing: 0) {
                content
            }
            .padding(46)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    // MARK: - Fond

    @ViewBuilder
    private var background: some View {
        switch style.layout {
        case .split:
            ZStack {
                style.colors[0]
                Path { p in
                    p.move(to: CGPoint(x: 0, y: size.height * 0.62))
                    p.addLine(to: CGPoint(x: size.width, y: size.height * 0.38))
                    p.addLine(to: CGPoint(x: size.width, y: size.height))
                    p.addLine(to: CGPoint(x: 0, y: size.height))
                    p.closeSubpath()
                }
                .fill(style.colors[1])
            }
        default:
            LinearGradient(colors: style.colors, startPoint: .top, endPoint: .bottom)
        }
    }

    // MARK: - Motifs

    @ViewBuilder
    private var decoration: some View {
        switch style.layout {
        case .sky:
            // Petites étoiles / particules.
            Canvas { context, canvasSize in
                var generator = SeededGenerator(seed: UInt64(title.unicodeScalars.reduce(0) { $0 + Int($1.value) }) + 7)
                for _ in 0..<70 {
                    let x = Double.random(in: 0...canvasSize.width, using: &generator)
                    let y = Double.random(in: 0...canvasSize.height * 0.7, using: &generator)
                    let r = Double.random(in: 1.5...4.5, using: &generator)
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                                 with: .color(.white.opacity(Double.random(in: 0.25...0.8, using: &generator))))
                }
            }
        case .sun:
            ZStack {
                Circle()
                    .fill(style.accent.opacity(0.9))
                    .frame(width: 330, height: 330)
                    .offset(y: -40)
                    .blur(radius: 1)
                mountains
            }
        case .frame:
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(style.accent, lineWidth: 5)
                .padding(26)
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(style.accent.opacity(0.6), lineWidth: 1.5)
                        .padding(40)
                }
        case .band:
            Rectangle()
                .fill(style.accent)
                .frame(height: 250)
                .offset(y: 150)
        case .split:
            EmptyView()
        }
    }

    private var mountains: some View {
        Path { p in
            let w = size.width, h = size.height
            p.move(to: CGPoint(x: 0, y: h * 0.72))
            p.addLine(to: CGPoint(x: w * 0.22, y: h * 0.56))
            p.addLine(to: CGPoint(x: w * 0.4, y: h * 0.66))
            p.addLine(to: CGPoint(x: w * 0.62, y: h * 0.5))
            p.addLine(to: CGPoint(x: w * 0.85, y: h * 0.64))
            p.addLine(to: CGPoint(x: w, y: h * 0.58))
            p.addLine(to: CGPoint(x: w, y: h))
            p.addLine(to: CGPoint(x: 0, y: h))
            p.closeSubpath()
        }
        .fill(.black.opacity(0.35))
    }

    // MARK: - Titre, auteur, illustration

    private var titleText: some View {
        Text(title)
            .font(.system(size: 62, weight: .bold, design: .serif))
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.6)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
    }

    private var authorText: some View {
        Text(author.uppercased())
            .font(.system(size: 26, weight: .semibold, design: .default))
            .tracking(5)
            .foregroundStyle(.white.opacity(0.9))
    }

    private var illustration: some View {
        Image(systemName: style.symbol)
            .resizable()
            .scaledToFit()
            .frame(width: 210, height: 210)
            .foregroundStyle(style.layout == .band ? .white : style.accent)
            .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
    }

    @ViewBuilder
    private var content: some View {
        switch style.layout {
        case .band:
            authorText
            Spacer()
            illustration.offset(y: -60)
            Spacer()
            titleText.padding(.bottom, 60)
        case .sun:
            titleText
            Spacer()
            authorText
        case .frame:
            Spacer(minLength: 20)
            titleText
            Spacer()
            illustration
            Spacer()
            authorText
            Spacer(minLength: 20)
        default:
            authorText
            Spacer()
            illustration
            Spacer()
            titleText
        }
    }
}

/// Générateur pseudo-aléatoire reproductible (mêmes étoiles à chaque capture).
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1 }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

enum DemoCovers {
    /// Dessine la couverture en JPEG.
    @MainActor
    static func render(title: String, author: String, style: DemoCoverStyle) -> Data? {
        let renderer = ImageRenderer(content: DemoCoverArt(title: title, author: author, style: style))
        renderer.scale = 1
        return renderer.uiImage?.jpegData(compressionQuality: 0.85)
    }
}
