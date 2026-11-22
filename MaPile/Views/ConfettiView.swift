import SwiftUI
import UIKit

extension Notification.Name {
    /// Envoyé quand un livre vient d'être marqué comme lu (confettis + vibration).
    static let bookFinished = Notification.Name("MaPileBookFinished")
}

/// Pluie de confettis qui tombe du haut de l'écran pendant environ 3 secondes.
struct ConfettiView: View {
    private struct Piece {
        let x: Double          // position de départ (0…1 de la largeur)
        let delay: Double      // décalage de départ (s)
        let speed: Double      // vitesse de chute (fraction de hauteur / s)
        let drift: Double      // balancement horizontal (points)
        let spin: Double       // rotation (tours / s)
        let size: CGSize
        let color: Color
        let round: Bool
    }

    private static let colors: [Color] = [.orange, .pink, .yellow, .green, .blue, .purple, .red, .teal]

    private static func makePieces() -> [Piece] {
        (0..<140).map { _ in
            Piece(x: Double.random(in: 0...1),
                  delay: Double.random(in: 0...0.8),
                  speed: Double.random(in: 0.35...0.6),
                  drift: Double.random(in: 10...40),
                  spin: Double.random(in: 0.5...2),
                  size: CGSize(width: Double.random(in: 6...11), height: Double.random(in: 9...16)),
                  color: Self.colors.randomElement() ?? .orange,
                  round: Bool.random() && Bool.random())
        }
    }

    // Tirés une seule fois : les confettis ne changent pas si l'écran se redessine.
    @State private var pieces: [Piece] = ConfettiView.makePieces()
    @State private var start = Date.now

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(start)
                for piece in pieces {
                    let t = elapsed - piece.delay
                    guard t > 0 else { continue }
                    let y = -20 + t * piece.speed * size.height
                    guard y < size.height + 20 else { continue }
                    let x = piece.x * size.width + sin(t * 3 + piece.x * 10) * piece.drift
                    var pieceContext = context
                    pieceContext.translateBy(x: x, y: y)
                    pieceContext.rotate(by: .radians(t * piece.spin * 2 * .pi))
                    let rect = CGRect(x: -piece.size.width / 2, y: -piece.size.height / 2,
                                      width: piece.size.width, height: piece.size.height)
                    let path = piece.round ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 2)
                    pieceContext.fill(path, with: .color(piece.color))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Affiche les confettis et fait vibrer l'iPhone à chaque livre terminé, au-dessus de toute l'app.
struct CelebrationOverlay: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var celebrationID: UUID?

    func body(content: Content) -> some View {
        content
            .overlay {
                if let celebrationID, !reduceMotion {
                    ConfettiView()
                        .id(celebrationID)
                        .transition(.opacity)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .bookFinished)) { _ in
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                let id = UUID()
                withAnimation { celebrationID = id }
                Task {
                    try? await Task.sleep(for: .seconds(3.8))
                    if celebrationID == id { withAnimation(.easeOut(duration: 0.6)) { celebrationID = nil } }
                }
            }
    }
}

extension View {
    func celebratesFinishedBooks() -> some View { modifier(CelebrationOverlay()) }
}
