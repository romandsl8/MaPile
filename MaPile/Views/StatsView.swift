import SwiftUI
import SwiftData
import Charts

/// Périodes proposées dans l'onglet Statistiques.
enum StatsPeriod: String, CaseIterable, Identifiable {
    case day, week, month, quarter, year, all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day: "Jour"
        case .week: "Semaine"
        case .month: "Mois"
        case .quarter: "Trim."
        case .year: "Année"
        case .all: "Tout"
        }
    }

    /// Découpage des graphiques pour cette période (nil = pas de graphique, on liste les livres).
    var bucket: Calendar.Component? {
        switch self {
        case .day: nil
        case .week, .month: .day
        case .quarter: .weekOfYear
        case .year: .month
        case .all: .year
        }
    }
}

/// Statistiques calculées à partir des livres enregistrés dans MaPile.
struct StatsView: View {
    @Query(filter: #Predicate<Book> { $0.statusRaw == "read" }) private var readBooks: [Book]
    @Query(filter: #Predicate<Book> { $0.statusRaw == "toRead" }) private var pileBooks: [Book]
    @Query private var sessions: [ReadingSession]
    @AppStorage("statsPeriod") private var periodRaw = StatsPeriod.year.rawValue
    @State private var anchor = Date.now
    @AppStorage("yearlyGoal") private var goal = 20
    @State private var showingAbout = false

    private let calendar = Calendar.current

    private var period: StatsPeriod { StatsPeriod(rawValue: periodRaw) ?? .year }

    // MARK: - Période affichée

    private var earliestDate: Date {
        var earliest = Date.now
        for book in readBooks where book.finishedOn < earliest { earliest = book.finishedOn }
        return earliest
    }

    private var interval: DateInterval {
        let fallback = DateInterval(start: calendar.startOfDay(for: anchor), duration: 86_400)
        switch period {
        case .day:
            return calendar.dateInterval(of: .day, for: anchor) ?? fallback
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: anchor) ?? fallback
        case .month:
            return calendar.dateInterval(of: .month, for: anchor) ?? fallback
        case .quarter:
            let month: Int = calendar.component(.month, from: anchor)
            var start = DateComponents()
            start.year = calendar.component(.year, from: anchor)
            start.month = ((month - 1) / 3) * 3 + 1
            start.day = 1
            guard let begin = calendar.date(from: start),
                  let end = calendar.date(byAdding: .month, value: 3, to: begin) else { return fallback }
            return DateInterval(start: begin, end: end)
        case .year:
            return calendar.dateInterval(of: .year, for: anchor) ?? fallback
        case .all:
            let begin = calendar.dateInterval(of: .year, for: earliestDate)?.start ?? earliestDate
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) ?? .now
            return DateInterval(start: begin, end: max(end, begin.addingTimeInterval(1)))
        }
    }

    private var periodTitle: String {
        let start = interval.start
        switch period {
        case .day:
            return anchor.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
        case .week:
            return "Semaine du " + start.formatted(.dateTime.day().month(.wide))
        case .month:
            return anchor.formatted(.dateTime.month(.wide).year())
        case .quarter:
            let quarter: Int = (calendar.component(.month, from: start) - 1) / 3 + 1
            return "\(quarter)e trimestre \(calendar.component(.year, from: start))"
        case .year:
            return String(calendar.component(.year, from: anchor))
        case .all:
            return "Depuis le début"
        }
    }

    private func shift(_ direction: Int) {
        let component: Calendar.Component
        var value = direction
        switch period {
        case .day: component = .day
        case .week: component = .weekOfYear
        case .month: component = .month
        case .quarter: component = .month; value = direction * 3
        case .year: component = .year
        case .all: return
        }
        if let date = calendar.date(byAdding: component, value: value, to: anchor) {
            withAnimation(.snappy) { anchor = min(date, .now) }
        }
    }

    private var canGoForward: Bool { period != .all && interval.end <= .now }

    // MARK: - Données

    private var periodBooks: [Book] {
        let range = interval
        var result: [Book] = []
        for book in readBooks where book.finishedOn >= range.start && book.finishedOn < range.end {
            result.append(book)
        }
        result.sort { $0.finishedOn > $1.finishedOn }
        return result
    }

    private var pages: Int {
        var total = 0
        for book in periodBooks { total += book.pageCount }
        return total
    }

    private var averageRating: Double? {
        var sum = 0
        var count = 0
        for book in periodBooks where book.myRating > 0 {
            sum += book.myRating
            count += 1
        }
        guard count > 0 else { return nil }
        return Double(sum) / Double(count)
    }

    private var averagePages: Int? {
        var sum = 0
        var count = 0
        for book in periodBooks where book.pageCount > 0 {
            sum += book.pageCount
            count += 1
        }
        guard count > 0 else { return nil }
        return sum / count
    }

    private struct BucketStat: Identifiable {
        let date: Date
        let books: Int
        let pages: Int
        var id: Date { date }
    }

    private var buckets: [BucketStat] {
        guard let unit = period.bucket else { return [] }
        var books: [Date: Int] = [:]
        var pageCounts: [Date: Int] = [:]
        for book in periodBooks {
            guard let start = calendar.dateInterval(of: unit, for: book.finishedOn)?.start else { continue }
            books[start, default: 0] += 1
            pageCounts[start, default: 0] += book.pageCount
        }
        var result: [BucketStat] = []
        var cursor: Date = calendar.dateInterval(of: unit, for: interval.start)?.start ?? interval.start
        var guardCount = 0
        while cursor < interval.end && guardCount < 400 {
            result.append(BucketStat(date: cursor, books: books[cursor] ?? 0, pages: pageCounts[cursor] ?? 0))
            guard let next = calendar.date(byAdding: unit, value: 1, to: cursor) else { break }
            cursor = next
            guardCount += 1
        }
        return result
    }

    private struct NamedCount: Identifiable {
        let name: String
        let count: Int
        var id: String { name }
    }

    private static func ranked(_ counts: [String: Int]) -> [NamedCount] {
        var items: [NamedCount] = []
        for (name, count) in counts { items.append(NamedCount(name: name, count: count)) }
        items.sort { (a: NamedCount, b: NamedCount) -> Bool in
            if a.count != b.count { return a.count > b.count }
            return a.name < b.name
        }
        return items
    }

    private var topAuthors: [NamedCount] {
        var counts: [String: Int] = [:]
        for book in periodBooks {
            for author in book.authorList { counts[author, default: 0] += 1 }
        }
        return Array(Self.ranked(counts).prefix(5))
    }

    private var genres: [NamedCount] {
        var counts: [String: Int] = [:]
        for book in periodBooks {
            let genre: String = book.genreList.first ?? "Non classé"
            counts[genre, default: 0] += 1
        }
        let sorted = Self.ranked(counts)
        guard sorted.count > 5 else { return sorted }
        var others = 0
        for item in sorted.dropFirst(5) { others += item.count }
        var result = Array(sorted.prefix(5))
        result.append(NamedCount(name: "Autres", count: others))
        return result
    }

    private var ratingDistribution: [NamedCount] {
        var result: [NamedCount] = []
        for stars in 1...5 {
            var count = 0
            for book in periodBooks where book.myRating == stars { count += 1 }
            result.append(NamedCount(name: String(repeating: "★", count: stars), count: count))
        }
        return result
    }

    // MARK: - Objectif annuel (année de la période affichée)

    private var goalYear: Int { calendar.component(.year, from: anchor) }

    private var goalYearCount: Int {
        var count = 0
        for book in readBooks where calendar.component(.year, from: book.finishedOn) == goalYear { count += 1 }
        return count
    }

    private var isCurrentYear: Bool { goalYear == calendar.component(.year, from: .now) }

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
                VStack(spacing: 16) {
                    periodSelector
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16, alignment: .top)],
                              spacing: 16) {
                        keyFigures
                        readingTimeCard
                        if periodBooks.isEmpty {
                            SectionCard {
                                ContentUnavailableView("Aucun livre terminé",
                                                       systemImage: "chart.bar",
                                                       description: Text("Aucune lecture terminée sur cette période."))
                            }
                        } else {
                            if period.bucket != nil {
                                booksChart
                                pagesChart
                            }
                            finishedBooksCard
                            if !topAuthors.isEmpty { authorsCard }
                            genresCard
                            if periodBooks.contains(where: { $0.myRating > 0 }) { ratingsCard }
                        }
                        goalCard
                        YearInReviewCard(year: goalYear)
                        BadgesCard()
                    }
                }
                .padding()
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Statistiques")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Réglages et à propos", systemImage: "gearshape") { showingAbout = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Aujourd'hui", systemImage: "calendar") {
                        withAnimation(.snappy) { anchor = .now }
                    }
                }
            }
            .sheet(isPresented: $showingAbout) { AboutView() }
        }
    }

    private var periodSelector: some View {
        VStack(spacing: 12) {
            Picker("Période", selection: Binding(get: { periodRaw }, set: { newValue in
                withAnimation(.snappy) {
                    periodRaw = newValue
                    anchor = .now
                }
            })) {
                ForEach(StatsPeriod.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button("Période précédente", systemImage: "chevron.left") { shift(-1) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass)
                        .disabled(period == .all)
                    Text(periodTitle)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .contentTransition(.numericText())
                    Button("Période suivante", systemImage: "chevron.right") { shift(1) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass)
                        .disabled(!canGoForward)
                }
            }
        }
        .frame(maxWidth: 640)
    }

    private var keyFigures: some View {
        SectionCard(title: "En bref", systemImage: "sparkles") {
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    figure("\(periodBooks.count)", periodBooks.count > 1 ? "livres lus" : "livre lu", "book.closed")
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

    // MARK: - Temps de lecture (séances chronométrées)

    private var periodSessions: [ReadingSession] {
        let range = interval
        var result: [ReadingSession] = []
        for session in sessions where session.end >= range.start && session.end < range.end { result.append(session) }
        return result
    }

    private var readingTimeCard: some View {
        let list = periodSessions
        var seconds: TimeInterval = 0
        var timedPages = 0
        var pagesRead = 0
        for session in list {
            pagesRead += session.pagesRead
            if !session.isManual {
                seconds += session.duration
                timedPages += session.pagesRead
            }
        }
        // La vitesse ne se calcule que sur les séances chronométrées.
        let speed: String = seconds >= 60 ? String(Int((Double(timedPages) / (seconds / 3600)).rounded())) : "–"
        let days = ReadingStreak.readingDays(sessions: sessions, finished: readBooks)
        let streak = ReadingStreak.current(days: days)
        let best = ReadingStreak.best(days: days)
        return SectionCard(title: "Pages et temps de lecture", systemImage: "timer") {
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    figure("\(pagesRead)", "pages lues", "doc.text")
                    figure(ReadingStreak.formatDuration(seconds), "chronométrées", "clock")
                }
                GridRow {
                    figure(speed, "pages / heure", "speedometer")
                    figure("\(list.count)", list.count > 1 ? "séances" : "séance", "list.bullet")
                }
                GridRow {
                    figure("\(streak) 🔥", "jours d'affilée", "flame")
                    figure("\(best)", "jours (record)", "trophy")
                }
            }
            if list.isEmpty {
                Text("Indiquez votre page dans l'onglet En cours (avec ou sans le chrono « Je lis ») pour suivre vos pages lues.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    // MARK: - Graphiques

    private var chartTitleSuffix: String {
        switch period {
        case .week, .month: "par jour"
        case .quarter: "par semaine"
        case .year: "par mois"
        case .all: "par année"
        case .day: ""
        }
    }

    private var axisStride: (Calendar.Component, Int) {
        switch period {
        case .week: (.day, 1)
        case .month: (.day, 5)
        case .quarter: (.weekOfYear, 2)
        case .year: (.month, 1)
        case .all: (.year, 1)
        case .day: (.day, 1)
        }
    }

    private var axisFormat: Date.FormatStyle {
        switch period {
        case .week: .dateTime.weekday(.narrow)
        case .month: .dateTime.day()
        case .quarter: .dateTime.day().month(.abbreviated)
        case .year: .dateTime.month(.narrow)
        case .all, .day: .dateTime.year()
        }
    }

    private var booksChart: some View {
        let unit: Calendar.Component = period.bucket ?? .day
        let stride = axisStride
        let format = axisFormat
        return SectionCard(title: "Livres \(chartTitleSuffix)", systemImage: "chart.bar") {
            Chart(buckets) { item in
                BarMark(x: .value("Période", item.date, unit: unit),
                        y: .value("Livres", item.books))
                    .foregroundStyle(Color.accentColor.gradient)
                    .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: stride.0, count: stride.1)) { _ in
                    AxisValueLabel(format: format, centered: true)
                }
            }
            .chartYAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
            .frame(height: 200)
        }
    }

    private var pagesChart: some View {
        let unit: Calendar.Component = period.bucket ?? .day
        let stride = axisStride
        let format = axisFormat
        return SectionCard(title: "Pages \(chartTitleSuffix)", systemImage: "doc.plaintext") {
            Chart(buckets) { item in
                BarMark(x: .value("Période", item.date, unit: unit),
                        y: .value("Pages", item.pages))
                    .foregroundStyle(Color.accentColor.opacity(0.55).gradient)
                    .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: stride.0, count: stride.1)) { _ in
                    AxisValueLabel(format: format, centered: true)
                }
            }
            .chartYAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
            .frame(height: 200)
        }
    }

    private var finishedBooksCard: some View {
        SectionCard(title: "Livres terminés", systemImage: "checkmark.seal") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(periodBooks.prefix(40)) { book in
                        VStack(alignment: .leading, spacing: 4) {
                            CoverView(book: book, cornerRadius: 5)
                                .frame(width: 70)
                                .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
                            Text(book.finishedOn, format: .dateTime.day().month(.abbreviated))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
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

    private var goalCard: some View {
        SectionCard(title: "Objectif \(String(goalYear))", systemImage: "target") {
            HStack(spacing: 20) {
                ZStack {
                    Circle().stroke(Color.accentColor.opacity(0.15), lineWidth: 14)
                    Circle()
                        .trim(from: 0, to: goalProgress)
                        .stroke(Color.accentColor.gradient, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.smooth, value: goalYearCount)
                    VStack(spacing: 0) {
                        Text("\(goalYearCount)")
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

    private var goalProgress: Double {
        let done = Double(goalYearCount)
        let target = Double(max(goal, 1))
        return min(done / target, 1.0)
    }

    private func plural(_ n: Int, _ word: String) -> String {
        n > 1 ? "\(n) \(word)s" : "\(n) \(word)"
    }

    private var goalMessage: String {
        let count: Int = goalYearCount
        if count >= goal { return "Objectif atteint, bravo ! 🎉" }
        if !isCurrentYear { return plural(count, "livre") + " lu(s) cette année-là." }
        let diff: Double = Double(count) - expectedToday
        if diff >= 0.5 {
            let ahead = Int(diff.rounded())
            return "En avance de " + plural(ahead, "livre") + " sur le rythme prévu."
        }
        if diff <= -0.5 {
            return "Encore " + plural(goal - count, "livre") + " à lire, un peu de retard sur le rythme."
        }
        return "Pile dans les temps !"
    }
}
