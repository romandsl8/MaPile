import SwiftUI
import SwiftData

/// Chiffres clés d'une année de lecture.
struct YearSummary {
    let year: Int
    let books: [Book]
    let pages: Int
    let topMonth: (name: String, count: Int)?
    let topAuthor: (name: String, count: Int)?
    let topGenre: String?
    let favorite: Book?
    let longest: Book?
    let readingTime: TimeInterval
    let bestStreak: Int
    let averageRating: Double?

    init(year: Int, read: [Book], sessions: [ReadingSession]) {
        let calendar = Calendar.current
        self.year = year
        let books = read.filter { calendar.component(.year, from: $0.finishedOn) == year }
            .sorted { $0.finishedOn < $1.finishedOn }
        self.books = books
        var pages = 0
        for book in books { pages += book.pageCount }
        self.pages = pages

        var months: [Int: Int] = [:]
        for book in books { months[calendar.component(.month, from: book.finishedOn), default: 0] += 1 }
        if let best = months.max(by: { $0.value < $1.value }) {
            let name = calendar.standaloneMonthSymbols[best.key - 1]
            topMonth = (name, best.value)
        } else {
            topMonth = nil
        }

        var authors: [String: Int] = [:]
        var genres: [String: Int] = [:]
        for book in books {
            for author in book.authorList { authors[author, default: 0] += 1 }
            if let genre = book.genreList.first { genres[genre, default: 0] += 1 }
        }
        topAuthor = authors.max(by: { $0.value < $1.value }).map { ($0.key, $0.value) }
        topGenre = genres.max(by: { $0.value < $1.value })?.key

        favorite = books.filter { $0.myRating > 0 }.max { a, b in
            a.myRating == b.myRating ? a.finishedOn < b.finishedOn : a.myRating < b.myRating
        }
        longest = books.max { $0.pageCount < $1.pageCount }

        let yearSessions = sessions.filter { calendar.component(.year, from: $0.end) == year }
        var time: TimeInterval = 0
        for session in yearSessions { time += session.duration }
        readingTime = time
        bestStreak = ReadingStreak.best(days: ReadingStreak.readingDays(sessions: yearSessions, finished: books))

        let rated = books.filter { $0.myRating > 0 }
        averageRating = rated.isEmpty ? nil : Double(rated.reduce(0) { $0 + $1.myRating }) / Double(rated.count)
    }
}

/// Carte d'accès au récapitulatif, dans l'onglet Statistiques.
struct YearInReviewCard: View {
    let year: Int
    @Query(filter: #Predicate<Book> { $0.statusRaw == "read" }) private var read: [Book]
    @State private var showing = false

    var body: some View {
        let count = read.filter { Calendar.current.component(.year, from: $0.finishedOn) == year }.count
        Button {
            showing = true
        } label: {
            HStack(spacing: 14) {
                Text("✨").font(.system(size: 34))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mon année \(String(year)) en lecture")
                        .font(.headline)
                    Text(count > 0 ? "Votre récap à revivre et partager" : "Terminez un livre pour débloquer votre récap")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [Color.orange.opacity(0.25), Color.pink.opacity(0.2)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
        .fullScreenCover(isPresented: $showing) { YearInReviewView(year: year) }
    }
}

/// Récapitulatif plein écran, façon « stories » : une page par chiffre clé.
struct YearInReviewView: View {
    let year: Int
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Book> { $0.statusRaw == "read" }) private var read: [Book]
    @Query private var sessions: [ReadingSession]
    @State private var page = 0
    @State private var shareImage: Image?

    var body: some View {
        let summary = YearSummary(year: year, read: read, sessions: sessions)
        ZStack(alignment: .topTrailing) {
            TabView(selection: $page) {
                StoryPage(colors: [.orange, .pink], emoji: "📚",
                          title: "\(String(year)) en lecture",
                          big: "\(summary.books.count)",
                          caption: summary.books.count > 1 ? "livres terminés" : "livre terminé",
                          footnote: "\(summary.pages.formatted(.number.locale(Locale(identifier: "fr_FR")))) pages tournées")
                    .tag(0)
                if let month = summary.topMonth {
                    StoryPage(colors: [.purple, .indigo], emoji: "🗓️",
                              title: "Votre mois record",
                              big: month.name.capitalized,
                              caption: month.count > 1 ? "\(month.count) livres lus" : "1 livre lu",
                              footnote: nil)
                        .tag(1)
                }
                if let author = summary.topAuthor {
                    StoryPage(colors: [.teal, .blue], emoji: "✍️",
                              title: "Votre auteur de l'année",
                              big: author.name,
                              caption: author.count > 1 ? "\(author.count) livres" : "1 livre",
                              footnote: summary.topGenre.map { "Genre préféré : \($0)" })
                        .tag(2)
                }
                if let favorite = summary.favorite {
                    StoryPage(colors: [.red, .orange], emoji: "❤️",
                              title: "Votre coup de cœur",
                              big: favorite.title,
                              caption: favorite.displayAuthors,
                              footnote: String(repeating: "★", count: favorite.myRating),
                              cover: favorite)
                        .tag(3)
                }
                StoryPage(colors: [.green, .teal], emoji: "⏳",
                          title: "Votre rythme",
                          big: summary.readingTime > 0 ? ReadingStreak.formatDuration(summary.readingTime) : "\(summary.bestStreak) j",
                          caption: summary.readingTime > 0 ? "de lecture chronométrée" : "de série record",
                          footnote: summary.bestStreak > 0 ? "Série record : \(summary.bestStreak) jours d'affilée 🔥" : nil)
                    .tag(4)
                finalPage(summary).tag(5)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .ignoresSafeArea()

            Button("Fermer", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .padding()
        }
        .task {
            let renderer = ImageRenderer(content: YearShareCard(summary: summary))
            renderer.scale = 2
            if let ui = renderer.uiImage { shareImage = Image(uiImage: ui) }
        }
    }

    private func finalPage(_ summary: YearSummary) -> some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.95, green: 0.55, blue: 0.34), Color(red: 0.59, green: 0.2, blue: 0.36)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            VStack(spacing: 24) {
                YearShareCard(summary: summary)
                    .scaleEffect(0.42)
                    .frame(width: 302, height: 538)
                    .clipShape(.rect(cornerRadius: 18))
                    .shadow(radius: 20)
                if let shareImage {
                    ShareLink(item: shareImage, preview: SharePreview("Mon année \(String(summary.year)) en lecture", image: shareImage)) {
                        Label("Partager mon année", systemImage: "square.and.arrow.up")
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                }
            }
        }
    }
}

/// Une page de la story.
struct StoryPage: View {
    let colors: [Color]
    let emoji: String
    let title: String
    let big: String
    let caption: String
    let footnote: String?
    var cover: Book? = nil
    @State private var appeared = false

    var body: some View {
        ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                Text(emoji).font(.system(size: 64))
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                if let cover {
                    CoverView(book: cover, cornerRadius: 10)
                        .frame(width: 150)
                        .shadow(radius: 16)
                }
                Text(big)
                    .font(.system(size: cover == nil ? 64 : 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.4)
                    .lineLimit(3)
                Text(caption)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                if let footnote {
                    Text(footnote)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.top, 8)
                }
            }
            .padding(32)
            .scaleEffect(appeared ? 1 : 0.85)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear { withAnimation(.spring(duration: 0.6)) { appeared = true } }
        .onDisappear { appeared = false }
    }
}

/// Image de partage (format story 720 × 1280).
struct YearShareCard: View {
    let summary: YearSummary

    private var covers: [Book] { Array(summary.books.suffix(9).reversed()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("Mon année \(String(summary.year))\nen lecture")
                .font(.system(size: 58, weight: .heavy, design: .serif))
                .foregroundStyle(.white)
            HStack(spacing: 30) {
                stat("\(summary.books.count)", "livres")
                stat(summary.pages.formatted(.number.locale(Locale(identifier: "fr_FR"))), "pages")
                if let rating = summary.averageRating { stat(rating.frenchDecimal, "note moy.") }
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 14) {
                        ForEach(Array(covers.dropFirst(row * 3).prefix(3))) { book in
                            CoverView(data: book.coverData, url: nil, title: book.title, cornerRadius: 6)
                                .frame(width: 170)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            if let author = summary.topAuthor {
                Text("Auteur de l'année : \(author.name)")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            Text("📚 MaPile")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(54)
        .frame(width: 720, height: 1280, alignment: .topLeading)
        .background(LinearGradient(colors: [Color(red: 0.95, green: 0.55, blue: 0.34), Color(red: 0.59, green: 0.2, blue: 0.36)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 54, weight: .bold, design: .rounded))
            Text(label).font(.system(size: 22))
        }
        .foregroundStyle(.white)
    }
}
