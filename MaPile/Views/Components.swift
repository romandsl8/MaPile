import SwiftUI

/// Couverture d'un livre : image enregistrée, sinon image en ligne, sinon couverture générée.
struct CoverView: View {
    var data: Data?
    var url: URL?
    var title: String
    var cornerRadius: CGFloat = 8

    var body: some View {
        Color.clear
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay {
                if let data, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if let url {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            GeneratedCover(title: title)
                        }
                    }
                } else {
                    GeneratedCover(title: title)
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}

extension CoverView {
    init(book: Book, cornerRadius: CGFloat = 8) {
        self.init(data: book.coverData, url: book.coverURL, title: book.title, cornerRadius: cornerRadius)
    }
}

private struct GeneratedCover: View {
    let title: String

    private var hue: Double {
        let sum = title.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Double(sum % 360) / 360
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hue: hue, saturation: 0.45, brightness: 0.75),
                         Color(hue: hue, saturation: 0.6, brightness: 0.45)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(title)
                .font(.system(.caption, design: .serif).weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.6)
                .padding(6)
        }
    }
}

/// Étoiles modifiables (0 à 5). Toucher l'étoile déjà choisie remet la note à zéro.
struct StarRatingPicker: View {
    @Binding var rating: Int
    var size: CGFloat = 28

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    withAnimation(.snappy) { rating = (rating == value) ? 0 : value }
                } label: {
                    Image(systemName: value <= rating ? "star.fill" : "star")
                        .font(.system(size: size))
                        .foregroundStyle(value <= rating ? Color.yellow : Color.secondary.opacity(0.5))
                        .symbolEffect(.bounce, value: rating == value)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(value) étoile\(value > 1 ? "s" : "")")
            }
        }
        .sensoryFeedback(.selection, trigger: rating)
    }
}

/// Étoiles en lecture seule, avec demi-étoiles.
struct StarRatingDisplay: View {
    var rating: Double
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { i in
                let value = Double(i)
                Image(systemName: rating >= value ? "star.fill" : (rating >= value - 0.5 ? "star.leadinghalf.filled" : "star"))
                    .font(.system(size: size))
                    .foregroundStyle(.yellow)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(String(format: "%.1f sur 5", rating))
    }
}

/// Carte de contenu sobre (fond groupé), utilisée dans les fiches et les statistiques.
struct SectionCard<Content: View>: View {
    var title: String?
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                if let systemImage {
                    Label(title, systemImage: systemImage).font(.headline)
                } else {
                    Text(title).font(.headline)
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
    }
}

extension Double {
    var frenchDecimal: String {
        formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "fr_FR")))
    }
}
