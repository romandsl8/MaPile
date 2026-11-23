import SwiftUI
import SwiftData

/// Demande de recherche d'un tome (ouvre l'onglet de recherche pré-rempli).
struct VolumeSearch: Identifiable {
    let id = UUID()
    let query: String
}

/// Carte « Saga » de la fiche : place du livre dans la série et ordre de lecture des tomes.
struct SeriesCard: View {
    @Bindable var book: Book
    @Query private var library: [Book]
    @State private var info: SeriesInfo?
    @State private var loading = true
    @State private var search: VolumeSearch?

    var body: some View {
        Group {
            if let info {
                onlineCard(info)
            } else if !book.seriesName.isEmpty, !loading {
                localCard
            } else if loading, !book.seriesName.isEmpty {
                SectionCard(title: "Saga", systemImage: "books.vertical.circle") {
                    HStack {
                        ProgressView()
                        Text("Recherche de l'ordre de lecture…").foregroundStyle(.secondary)
                    }
                }
            } else {
                // Rien à afficher (livre seul) : vue vide, mais présente pour lancer la recherche.
                Color.clear.frame(height: 0)
            }
        }
        .task(id: book.uuid) { await load() }
        .sheet(item: $search) { request in
            AddBookView(defaultStatus: .toRead, initialQuery: request.query)
        }
    }

    private func load() async {
        // Démo (captures) : livres fictifs, pas de recherche en ligne.
        if ProcessInfo.processInfo.arguments.contains("-demoData") {
            loading = false
            return
        }
        let found = await SeriesService.lookup(title: book.title, author: book.authorList.first ?? "")
        withAnimation {
            info = found
            loading = false
        }
        // Renseigne la série du livre si elle est vide (utile pour les piles « Par série »).
        if let found, book.seriesName.isEmpty {
            book.seriesName = found.name
            if let position = found.position { book.seriesIndex = position }
        }
    }

    // MARK: - Saga trouvée en ligne

    private func onlineCard(_ info: SeriesInfo) -> some View {
        SectionCard(title: "Saga : \(info.name)", systemImage: "books.vertical.circle") {
            if let position = info.position {
                Text(position == 1
                     ? "C'est le premier tome sur \(info.volumes.count). Bonne nouvelle : vous pouvez commencer par celui-ci !"
                     : "C'est le tome \(position) sur \(info.volumes.count). Ordre de lecture conseillé :")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(info.volumes.enumerated()), id: \.element.id) { index, volume in
                    volumeRow(number: index + 1, volume: volume, isCurrent: volume.id == info.currentID)
                    if index < info.volumes.count - 1 { Divider() }
                }
            }
            Text("Source : Wikidata")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func libraryMatch(_ title: String) -> Book? {
        let key = BookSearchService.normalize(title)
        guard key.count >= 3 else { return nil }
        return library.first { other in
            let otherKey = BookSearchService.normalize(other.title)
            return otherKey == key || (key.count >= 6 && (otherKey.hasPrefix(key) || key.hasPrefix(otherKey) && otherKey.count >= 6))
        }
    }

    private func volumeRow(number: Int, volume: SeriesVolume, isCurrent: Bool) -> some View {
        let owned: Book? = isCurrent ? book : libraryMatch(volume.title)
        return HStack(spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(isCurrent ? .white : .primary)
                .frame(width: 28, height: 28)
                .background(isCurrent ? Color.accentColor : Color(uiColor: .tertiarySystemFill), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(isCurrent ? book.title : volume.title)
                    .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if isCurrent {
                        Text("Ce livre")
                            .foregroundStyle(Color.accentColor)
                    } else if let owned {
                        Label(owned.status.longTitle, systemImage: owned.status.systemImage)
                    }
                    if let year = volume.year { Text(String(year)) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if owned == nil {
                Button {
                    search = VolumeSearch(query: "\(volume.title) \(book.authorList.first ?? "")")
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Chercher « \(volume.title) » pour l'ajouter")
            } else if owned?.status == .read {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Série saisie à la main (introuvable en ligne)

    private var localCard: some View {
        let key = BookSearchService.normalize(book.seriesName)
        let volumes = library.filter { BookSearchService.normalize($0.seriesName) == key }
            .sorted { ($0.seriesIndex == 0 ? Int.max : $0.seriesIndex) < ($1.seriesIndex == 0 ? Int.max : $1.seriesIndex) }
        return SectionCard(title: "Saga : \(book.seriesName)", systemImage: "books.vertical.circle") {
            if book.seriesIndex > 0 {
                Text("Tome \(book.seriesIndex). Vos tomes, dans l'ordre :")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(volumes) { volume in
                    HStack(spacing: 12) {
                        Text(volume.seriesIndex > 0 ? "\(volume.seriesIndex)" : "–")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(volume.uuid == book.uuid ? .white : .primary)
                            .frame(width: 28, height: 28)
                            .background(volume.uuid == book.uuid ? Color.accentColor : Color(uiColor: .tertiarySystemFill), in: .circle)
                        Text(volume.title)
                            .font(.subheadline)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                        Image(systemName: volume.status.systemImage)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
            Button("Chercher le tome suivant", systemImage: "magnifyingglass") {
                search = VolumeSearch(query: "\(book.seriesName) tome \(book.seriesIndex + 1)")
            }
            .font(.subheadline)
        }
    }
}
