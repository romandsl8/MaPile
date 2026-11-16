import SwiftUI
import SwiftData
import Charts

/// Statistiques calculées à partir des livres enregistrés dans MaPile.
struct StatsView: View {
    @Query(filter: #Predicate<Book> { $0.statusRaw == "read" }) private var readBooks: [Book]
    @Query(filter: #Predicate<Book> { $0.statusRaw == "toRead" }) private var pileBooks: [Book]
    @State private var year = Calendar.current.component(.year, from: .now)
    @AppStorage("yearlyGoal") private var goal = 20

    private let calendar = Calendar.current

    // MARK: - Données

    private var yearBooks: [Book] {
        readBooks.filter { calendar.component(.year, from: $0.finishedOn) == year }
    }

    private var availableYears: [Int] {
        var years = Set(readBooks.map { calendar.component(.year, from: $0.finishedOn) })
        years.insert(calendar.component(.year, from: .now))
        return years.sorted(by: >)
    }

    private var pages: Int { yearBooks.reduce(0) { $0 + $1.pageCount } }

    private var averageRating: Double? {
        let rated = yearBooks.filter { $0.myRating > 0 }
        guard !rated.isEmpty else { return nil }
        return Double(rated.reduce(0) { $0 + $1.myRating }) / Double(rated.count)
    }

    private var averagePages: Int? {
        let withPages = yearBooks.filter { $0.pageCount > 0 }
        guard !withPages.isEmpty else { return nil }
        return withPages.reduce(0) { $0 + $1.pageCount } / withPages.count
    }

    private struct MonthStat: Identifiable {
        let date: Date
        let books: Int
        let pages: Int
        var id: Date { date }
    }

    private var monthly: [MonthStat] {
        (1...12).compactMap { month -> MonthStat? in
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return nil }
            let books = yearBooks.filter { calendar.component(.month, from: $0.finishedOn) == month }
            return MonthStat(date: date, books: books.count, pages: books.reduce(0) { $0 + $1.pageCount })
        }
    }

    private struct NamedCount: Identifiable {
        let name: String
        let count: Int
        var id: String { name }
    }

    private var perYear: [NamedCount] {
        let grouped = Dictionary(grouping: readBooks) { calendar.component(.year, from: $0.finishedOn) }
        return grouped.keys.sorted().map { NamedCount(name: String($0), count: grouped[$0]?.count ?? 0) }
    }

    private var topAuthors: [NamedCount] {
        var counts: [String: Int] = [:]
        for book in yearBooks {
            for author in book.authorList { counts[author, default: 0] += 1 }
        }
        return counts.map { NamedCount(name: $0.key, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
            .prefix(5)
            .map { $0 }
    }

    private var genres: [NamedCount] {
        var counts: [String: Int] = [:]
        for book in yearBooks {
            let genre = book.genreList.first ?? "Non classé"
            counts[genre, default: 0] += 1
        }
        let sorted = counts.map { NamedCount(name: $0.key, count: $0.value) }.sorted { $0.count > $1.count }
        guard sorted.count > 5 else { return sorted }
        let others = sorted.dropFirst(5).reduce(0) { $0 + $1.count }
        return Array(sorted.prefix(5)) + [NamedCount(name: "Autres", count: others)]
    }

    private var ratingDistribution: [NamedCount] {
        (1...5).map { stars in
            NamedCount(name: String(repeating: "★", count: stars),
                       count: yearBooks.filter { $0.myRating == stars }.count)
        }
    }

    private var isCurrentYear: Bool { year == calendar.component(.year, from: .now) }

    /// Nombre de livres qu'il faudrait avoir lus aujourd'hui pour tenir l'objectif.
    private var expectedToday: Double {
        guard isCurrentYear,
              let dayOfYear = calendar.ordinality(of: .day, in: .year, for: .now),
              let range = calendar.range(of: .day, in: .year, for: .now) else { return Double(goal) }
        return Double(goal) * Double(dayOfYear) / Double(range.count)
    }

    // MARK: - Vue

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16, alignment: .top)],
                          spacing: 16) {
                    goalCard
                    keyFigures
                    if yearBooks.isEmpty {
                        SectionCard {
                            ContentUnavailableView("Pas encore de lecture en \(String(year))",
                                                   systemImage: "chart.bar",
                                                   description: Text("Marquez des livres comme lus pour voir vos statistiques."))
                        }
                    } else {
                        booksPerMonth
                        pagesPerMonth
                        if !topAuthors.isEmpty { authorsCard }
                        genresCard
                        if yearBooks.contains(where: { $0.myRating > 0 }) { ratingsCard }
                    }
                    if perYear.count > 1 { perYearCard }
                }
                .padding()
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Statistiques")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Année", selection: $year) {
                            ForEach(availableYears, id: \.self) { Text(String($0)).tag($0) }
                        }
                    } label: {
                        Label(String(year), systemImage: "calendar")
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
        }
    }

    private var goalCard: some View {
        SectionCard(title: "Objectif \(String(year))", systemImage: "target") {
            HStack(spacing: 20) {
                ZStack {
                    Circle().stroke(Color.accentColor.opacity(0.15), lineWidth: 14)
                    Circle()
                        .trim(from: 0, to: min(Double(yearBooks.count) / Double(max(goal, 1)), 1))
                        .stroke(Color.accentColor.gradient, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.smooth, value: yearBooks.count)
                    VStack(spacing: 0) {
                        Text("\(yearBooks.count)")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("sur \(goal)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 110, height: 110)

                VStack(alignment: .leading, spacing: 10) {
                    Text(goalMessage)
                        .font(.subheadline)
                    Stepper("Objectif : \(goal) livres", value: $goal, in: 1...365)
                        .font(.subheadline)
                }
            }
        }
    }

    private var goalMessage: String {
        let count = yearBooks.count
        if count >= goal { return "Objectif atteint, bravo ! 🎉" }
        guard isCurrentYear else { return "\(count) livre\(count > 1 ? "s" : "") lu\(count > 1 ? "s" : "") cette année-là." }
        let diff = Double(count) - expectedToday
        if diff >= 0.5 { return "En avance de \(Int(diff.rounded())) livre\(diff >= 1.5 ? "s" : "") sur le rythme prévu." }
        if diff <= -0.5 { return "Encore \(goal - count) livre\(goal - count > 1 ? "s" : "") à lire, un peu de retard sur le rythme." }
        return "Pile dans les temps !"
    }

    private var keyFigures: some View {
        SectionCard(title: "En bref", systemImage: "sparkles") {
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    figure("\(yearBooks.count)", "livres lus", "book.closed")
                    figure(pages.formatted(.number.locale(Locale(identifier: "fr_FR"))), "pages", "doc.plaintext")
                }
                GridRow {
                    figure(averageRating.map { $0.frenchDecimal } ?? "–", "note moyenne", "star")
                    figure(averagePages.map { String($0) } ?? "–", "pages / livre", "ruler")
                }
                GridRow {
                    figure("\(pileBooks.count)", "dans la PAL", "books.vertical")
                    figure("\(readBooks.count)", "lus au total", "checkmark.seal")
                }
            }
        }
    }

    private func figure(_ value: String, _ label: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }

    private var booksPerMonth: some View {
        SectionCard(title: "Livres par mois", systemImage: "chart.bar") {
            Chart(monthly) { item in
                BarMark(x: .value("Mois", item.date, unit: .month),
                        y: .value("Livres", item.books))
                    .foregroundStyle(Color.accentColor.gradient)
                    .cornerRadius(5)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
                }
            }
            .chartYAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
            .frame(height: 200)
        }
    }

    private var pagesPerMonth: some View {
        SectionCard(title: "Pages par mois", systemImage: "doc.plaintext") {
            Chart(monthly) { item in
                AreaMark(x: .value("Mois", item.date, unit: .month),
                         y: .value("Pages", item.pages))
                    .foregroundStyle(Color.accentColor.opacity(0.2).gradient)
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Mois", item.date, unit: .month),
                         y: .value("Pages", item.pages))
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.catmullRom)
                    .symbol(.circle)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
                }
            }
            .frame(height: 200)
        }
    }

    private var authorsCard: some View {
        SectionCard(title: "Auteurs les plus lus", systemImage: "person.crop.rectangle.stack") {
            Chart(topAuthors) { item in
                BarMark(x: .value("Livres", item.count),
                        y: .value("Auteur", item.name))
                    .foregroundStyle(Color.accentColor.gradient)
                    .cornerRadius(5)
                    .annotation(position: .trailing) {
                        Text("\(item.count)").font(.caption).foregroundStyle(.secondary)
                    }
            }
            .chartXAxis(.hidden)
            .frame(height: CGFloat(topAuthors.count) * 38 + 10)
        }
    }

    private var genresCard: some View {
        SectionCard(title: "Genres", systemImage: "theatermasks") {
            Chart(genres) { item in
                SectorMark(angle: .value("Livres", item.count),
                           innerRadius: .ratio(0.6),
                           angularInset: 2)
                    .cornerRadius(4)
                    .foregroundStyle(by: .value("Genre", item.name))
            }
            .chartLegend(position: .trailing, alignment: .center)
            .frame(height: 190)
        }
    }

    private var ratingsCard: some View {
        SectionCard(title: "Mes notes", systemImage: "star") {
            Chart(ratingDistribution) { item in
                BarMark(x: .value("Note", item.name),
                        y: .value("Livres", item.count))
                    .foregroundStyle(Color.yellow.gradient)
                    .cornerRadius(5)
            }
            .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
            .frame(height: 160)
        }
    }

    private var perYearCard: some View {
        SectionCard(title: "Livres par année", systemImage: "calendar") {
            Chart(perYear) { item in
                BarMark(x: .value("Année", item.name),
                        y: .value("Livres", item.count))
                    .foregroundStyle(item.name == String(year) ? Color.accentColor.gradient : Color.secondary.opacity(0.4).gradient)
                    .cornerRadius(5)
                    .annotation(position: .top) {
                        Text("\(item.count)").font(.caption2).foregroundStyle(.secondary)
                    }
            }
            .frame(height: 180)
        }
    }
}
