import SwiftUI
import SwiftData

/// Onglet « En cours » : le ou les livres en train d'être lus, avec la page atteinte.
struct ReadingView: View {
    @Query(filter: #Predicate<Book> { $0.statusRaw == "reading" }, sort: \Book.dateAdded, order: .reverse)
    private var reading: [Book]
    @Query(filter: #Predicate<Book> { $0.statusRaw == "toRead" }, sort: \Book.dateAdded, order: .reverse)
    private var pile: [Book]

    @State private var path: [Book] = []
    @State private var showingPicker = false
    @State private var showingNextRead = false
    @State private var bookToFinish: Book?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if reading.isEmpty {
                    ContentUnavailableView {
                        Label("Aucune lecture en cours", systemImage: "book")
                    } description: {
                        Text("Choisissez un livre de votre PAL pour suivre la page à laquelle vous en êtes.")
                    } actions: {
                        Button {
                            showingPicker = true
                        } label: {
                            Label("Commencer un livre", systemImage: "plus")
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(pile.isEmpty)
                        Button {
                            showingNextRead = true
                        } label: {
                            Label("Que lire ensuite ?", systemImage: "sparkles")
                        }
                        .buttonStyle(.glass)
                        .disabled(pile.isEmpty)
                    }
                } else {
                    ScrollView {
                        StreakBanner()
                            .padding(.horizontal)
                            .padding(.top, 4)
                            .frame(maxWidth: 1100)
                            .frame(maxWidth: .infinity)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 20, alignment: .top)], spacing: 20) {
                            ForEach(reading) { book in
                                ReadingCard(book: book,
                                            onOpen: { path.append(book) },
                                            onFinish: { bookToFinish = book })
                            }
                        }
                        .padding()
                        .frame(maxWidth: 1100)
                        .frame(maxWidth: .infinity)
                    }
                    .background(Color(uiColor: .systemGroupedBackground))
                }
            }
            .navigationTitle("En cours")
            .navigationDestination(for: Book.self) { book in
                BookDetailView(book: book) {
                    if !path.isEmpty { path.removeLast() }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Que lire ensuite ?", systemImage: "sparkles") { showingNextRead = true }
                        .disabled(pile.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Commencer un livre", systemImage: "plus") { showingPicker = true }
                        .disabled(pile.isEmpty)
                }
            }
            .sheet(isPresented: $showingNextRead) { NextReadSheet() }
            .sheet(isPresented: $showingPicker) {
                StartReadingPicker(books: pile)
            }
            .sheet(item: $bookToFinish) { book in
                FinishBookSheet(book: book)
            }
        }
    }
}

/// Carte d'un livre en cours : couverture, progression et saisie de la page.
struct ReadingCard: View {
    @Bindable var book: Book
    var onOpen: () -> Void
    var onFinish: () -> Void

    private enum Field: Hashable { case page, total, chapter, chapterTotal }

    @Environment(\.modelContext) private var context
    @State private var pageText = ""
    @State private var totalText = ""
    @State private var chapterText = ""
    @State private var chapterTotalText = ""
    @FocusState private var focus: Field?
    @AppStorage(ActiveSession.bookKey) private var activeBookID = ""
    @AppStorage(ActiveSession.startKey) private var activeStart = 0.0
    @State private var showingEndSession = false
    @State private var confirmingCancel = false

    private var editingPage: Bool { focus != nil }

    private var isSessionRunning: Bool { activeBookID == book.uuid.uuidString && activeStart > 0 }

    /// Bouton « Je lis » / chrono de la séance en cours.
    @ViewBuilder
    private var sessionControl: some View {
        if isSessionRunning {
            HStack(spacing: 12) {
                Image(systemName: "timer")
                    .symbolEffect(.pulse)
                    .foregroundStyle(Color.accentColor)
                Text(timerInterval: Date(timeIntervalSince1970: activeStart)...Date.distantFuture, countsDown: false)
                    .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                Text("de lecture")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Annuler", systemImage: "xmark") { confirmingCancel = true }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .controlSize(.small)
                Button("Terminer", systemImage: "stop.fill") { showingEndSession = true }
                    .buttonStyle(.glassProminent)
                    .controlSize(.small)
            }
            .padding(12)
            .glassEffect(.regular.tint(Color.accentColor.opacity(0.15)), in: .rect(cornerRadius: 16))
            .confirmationDialog("Annuler cette séance ?", isPresented: $confirmingCancel, titleVisibility: .visible) {
                Button("Annuler la séance", role: .destructive) { cancelSession() }
                Button("Continuer à lire", role: .cancel) {}
            } message: {
                Text("Le chrono s'arrête et cette séance ne sera pas comptée dans vos statistiques.")
            }
        } else {
            Button {
                withAnimation(.snappy) { ActiveSession.begin(for: book) }
                WidgetBridge.startActivity(for: book)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } label: {
                Label("Je lis (lancer le chrono)", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                CoverView(book: book, cornerRadius: 8)
                    .frame(width: 100)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 5)
                    .onTapGesture(perform: onOpen)
                VStack(alignment: .leading, spacing: 6) {
                    Text(book.title)
                        .font(.system(.title3, design: .serif).weight(.bold))
                        .lineLimit(3)
                    Text(book.displayAuthors)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let start = book.dateStarted {
                        Text("Commencé le \(start.formatted(.dateTime.day().month(.wide)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    progressSummary
                }
            }

            if let progress = book.progress {
                ProgressView(value: progress)
                    .tint(Color.accentColor)
                    .scaleEffect(x: 1, y: 1.6, anchor: .center)
                    .animation(.smooth, value: progress)
            }

            sessionControl

            pageControls

            chapterControls

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button(action: onFinish) {
                        Label("J'ai fini !", systemImage: "checkmark.seal.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    Button {
                        withAnimation { book.moveToPile() }
                    } label: {
                        Label("Remettre en PAL", systemImage: "books.vertical")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
                .controlSize(.regular)
            }

            ReadingHistory(book: book)
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
        .sheet(isPresented: $showingEndSession) { EndSessionSheet(book: book) }
        .onAppear(perform: refreshTexts)
        .onChange(of: book.currentPage) { _, _ in if focus == nil { refreshTexts() } }
        .onChange(of: book.pageCount) { _, _ in if focus == nil { refreshTexts() } }
        .onChange(of: focus) { old, new in
            guard let old, old != new else { return }
            switch old {
            case .page: commitPage()
            case .total: commitTotal()
            case .chapter, .chapterTotal: commitChapters()
            }
        }
        .sensoryFeedback(.selection, trigger: book.currentPage)
    }

    @ViewBuilder
    private var progressSummary: some View {
        if let progress = book.progress {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Int((progress * 100).rounded())) %")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("\(max(book.pageCount - book.currentPage, 0)) pages restantes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let finish = book.estimatedFinish {
                    Text("Fin estimée : \(finish.formatted(.dateTime.day().month(.abbreviated)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text("Indiquez le nombre de pages du livre pour voir votre progression.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func numberField(_ placeholder: String, text: Binding<String>, field: Field, width: CGFloat, large: Bool = false) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(.numberPad)
            .focused($focus, equals: field)
            .font(large ? .system(.title3, design: .rounded).weight(.semibold) : .system(.body, design: .rounded).weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(width: width)
            .padding(.vertical, 6)
            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: .rect(cornerRadius: 10))
    }

    private var pageControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Page")
                    .font(.headline)
                numberField("0", text: $pageText, field: .page, width: 76, large: true)
                Text("sur")
                    .foregroundStyle(.secondary)
                numberField("total", text: $totalText, field: .total, width: 70)
                Spacer()
                if editingPage {
                    Button("OK") { focus = nil }
                        .buttonStyle(.glassProminent)
                        .controlSize(.small)
                }
            }
            Text("Liseuse : le total change avec la taille du texte ou l'orientation ? Modifiez-le, la progression suit.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            HStack(spacing: 8) {
                quickButton(-10)
                quickButton(-1)
                quickButton(+1)
                quickButton(+10)
                quickButton(+25)
            }
        }
    }

    private func quickButton(_ delta: Int) -> some View {
        Button(delta > 0 ? "+\(delta)" : "\(delta)") {
            setPage(book.currentPage + delta)
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .font(.subheadline.weight(.semibold).monospacedDigit())
        .frame(maxWidth: .infinity)
    }

    /// Chapitre atteint sur le nombre total de chapitres.
    private var chapterControls: some View {
        HStack(spacing: 10) {
            Text("Chapitre")
                .font(.headline)
            numberField("0", text: $chapterText, field: .chapter, width: 56)
            Text("sur")
                .foregroundStyle(.secondary)
            numberField("total", text: $chapterTotalText, field: .chapterTotal, width: 56)
            Spacer()
            Button("Chapitre précédent", systemImage: "minus") { setChapter(book.currentChapter - 1) }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .controlSize(.small)
                .disabled(book.currentChapter <= 0)
            Button("Chapitre suivant", systemImage: "plus") { setChapter(book.currentChapter + 1) }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .controlSize(.small)
        }
    }

    private func refreshTexts() {
        pageText = String(book.currentPage)
        totalText = book.pageCount > 0 ? String(book.pageCount) : ""
        chapterText = book.currentChapter > 0 ? String(book.currentChapter) : ""
        chapterTotalText = book.chapterCount > 0 ? String(book.chapterCount) : ""
    }

    private func commitPage() {
        let value = Int(pageText.filter(\.isNumber)) ?? book.currentPage
        setPage(value)
    }

    private func commitTotal() {
        let value = Int(totalText.filter(\.isNumber)) ?? 0
        if value > 0, value != book.pageCount {
            ReadingLog.rescale(book: book, from: book.pageCount, to: value, context: context)
            withAnimation(.snappy) {
                book.pageCount = value
                if book.currentPage > value { book.currentPage = value }
            }
        }
        refreshTexts()
    }

    private func commitChapters() {
        let total = Int(chapterTotalText.filter(\.isNumber)) ?? 0
        book.chapterCount = max(total, 0)
        setChapter(Int(chapterText.filter(\.isNumber)) ?? book.currentChapter)
    }

    private func setChapter(_ value: Int) {
        var chapter = max(value, 0)
        if book.chapterCount > 0 { chapter = min(chapter, book.chapterCount) }
        withAnimation(.snappy) { book.currentChapter = chapter }
        chapterText = chapter > 0 ? String(chapter) : ""
        chapterTotalText = book.chapterCount > 0 ? String(book.chapterCount) : ""
    }

    private func setPage(_ value: Int) {
        var page = max(value, 0)
        if book.pageCount > 0 { page = min(page, book.pageCount) }
        if book.dateStarted == nil { book.dateStarted = .now }
        let previous = book.currentPage
        withAnimation(.snappy) { book.currentPage = page }
        pageText = String(page)
        ReadingLog.recordManualProgress(book: book, from: previous, to: page, context: context)
    }

    private func cancelSession() {
        withAnimation(.snappy) { ActiveSession.clear() }
        WidgetBridge.endActivity()
    }
}

/// Historique des séances d'un livre : chronométrées ou saisies à la main.
struct ReadingHistory: View {
    let book: Book
    @Environment(\.modelContext) private var context
    @Query private var sessions: [ReadingSession]
    @State private var expanded = false

    init(book: Book) {
        self.book = book
        let id = book.uuid.uuidString
        _sessions = Query(filter: #Predicate<ReadingSession> { $0.bookID == id }, sort: \ReadingSession.end, order: .reverse)
    }

    var body: some View {
        if !sessions.isEmpty {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(spacing: 0) {
                    ForEach(sessions.prefix(30)) { session in
                        row(session)
                        if session.id != sessions.prefix(30).last?.id { Divider() }
                    }
                }
                .padding(.top, 6)
            } label: {
                let total = sessions.reduce(0) { $0 + $1.pagesRead }
                Label("Historique · \(total) pages en \(sessions.count) séance\(sessions.count > 1 ? "s" : "")",
                      systemImage: "clock.arrow.circlepath")
                    .font(.subheadline.weight(.semibold))
            }
            .tint(.primary)
        }
    }

    private func row(_ session: ReadingSession) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: session.isManual ? "pencil" : "timer")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.end.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.subheadline)
                Text(session.isManual ? "Saisie sans chrono" : ReadingStreak.formatDuration(session.duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("+\(session.pagesRead) p.")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                Text("p. \(session.startPage) → \(session.endPage)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .contentShape(.rect)
        .contextMenu {
            Button("Supprimer cette séance", systemImage: "trash", role: .destructive) {
                context.delete(session)
                try? context.save()
            }
        }
    }
}

/// Choix d'un livre de la PAL à commencer.
struct StartReadingPicker: View {
    let books: [Book]
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [Book] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return books }
        return books.filter { $0.title.localizedStandardContains(q) || $0.authors.localizedStandardContains(q) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { book in
                Button {
                    withAnimation { book.startReading() }
                    dismiss()
                } label: {
                    BookRow(book: book)
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $search, prompt: "Titre ou auteur")
            .navigationTitle("Commencer un livre")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer", systemImage: "xmark") { dismiss() }
                }
            }
            .overlay {
                if books.isEmpty {
                    ContentUnavailableView("Votre PAL est vide", systemImage: "books.vertical",
                                           description: Text("Ajoutez d'abord des livres à votre pile à lire."))
                }
            }
        }
    }
}

/// Fin d'une séance de lecture : durée et page atteinte.
struct EndSessionSheet: View {
    @Bindable var book: Book
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    @State private var total = 0
    @State private var confirmingCancel = false
    private let start = ActiveSession.start ?? .now
    private let recordedStartPage = ActiveSession.startPage

    /// Page de départ convertie si le nombre total de pages a changé pendant la séance.
    private var startPage: Int {
        guard book.pageCount > 0, total > 0, total != book.pageCount else { return recordedStartPage }
        return Int((Double(recordedStartPage) * Double(total) / Double(book.pageCount)).rounded())
    }

    private var duration: TimeInterval { Date.now.timeIntervalSince(start) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Durée", value: ReadingStreak.formatDuration(duration))
                    LabeledContent("Page de départ", value: "\(startPage)")
                }
                Section {
                    Stepper(value: $page, in: 0...max(total, max(page, startPage) + 1000)) {
                        Text("Page \(page)")
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                    }
                    HStack {
                        Text("Sur un total de")
                        Spacer()
                        TextField("pages", value: $total, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("pages")
                            .foregroundStyle(.secondary)
                    }
                    if page > startPage {
                        Text("\(page - startPage) pages lues pendant cette séance")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Page atteinte")
                } footer: {
                    Text("Sur une liseuse, le total change avec la taille du texte ou l'orientation : indiquez celui affiché.")
                }
                Section {
                    Button("Ne pas compter cette séance", systemImage: "xmark.circle", role: .destructive) {
                        confirmingCancel = true
                    }
                }
            }
            .confirmationDialog("Annuler cette séance ?", isPresented: $confirmingCancel, titleVisibility: .visible) {
                Button("Annuler la séance", role: .destructive) {
                    ActiveSession.clear()
                    WidgetBridge.endActivity()
                    dismiss()
                }
                Button("Garder", role: .cancel) {}
            } message: {
                Text("Le chrono s'arrête et cette séance ne sera pas comptée dans vos statistiques.")
            }
            .navigationTitle("Fin de la séance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Continuer à lire", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", systemImage: "checkmark") { save() }
                        .buttonStyle(.glassProminent)
                }
            }
            .onAppear {
                total = book.pageCount
                page = max(book.currentPage, recordedStartPage)
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        let session = ReadingSession(book: book, start: start, end: .now, startPage: startPage, endPage: page)
        context.insert(session)
        if book.dateStarted == nil { book.dateStarted = start }
        if total > 0, total != book.pageCount {
            ActiveSession.clear()
            ReadingLog.rescale(book: book, from: book.pageCount, to: total, context: context)
            book.pageCount = total
        }
        book.currentPage = book.pageCount > 0 ? min(page, book.pageCount) : page
        ActiveSession.clear()
        WidgetBridge.endActivity()
        try? context.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

/// Bandeau de motivation : série de jours de lecture et temps lu aujourd'hui.
struct StreakBanner: View {
    @Query private var sessions: [ReadingSession]
    @Query(filter: #Predicate<Book> { $0.statusRaw == "read" }) private var finished: [Book]

    static func title(for streak: Int) -> String {
        if streak > 1 { return "\(streak) jours de lecture d'affilée" }
        if streak == 1 { return "1 jour de lecture" }
        return "Lancez votre série !"
    }

    var body: some View {
        let days = ReadingStreak.readingDays(sessions: sessions, finished: finished)
        let streak = ReadingStreak.current(days: days)
        let best = ReadingStreak.best(days: days)
        let today = Calendar.current.startOfDay(for: .now)
        let todayTime = sessions.filter { $0.end >= today }.reduce(0.0) { $0 + $1.duration }
        HStack(spacing: 14) {
            Text(streak > 0 ? "🔥" : "📖")
                .font(.system(size: 34))
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.title(for: streak))
                    .font(.headline)
                Text("Aujourd'hui : \(ReadingStreak.formatDuration(todayTime)) · Record : \(best) jour\(best > 1 ? "s" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .glassEffect(.regular.tint(.orange.opacity(streak > 0 ? 0.2 : 0.05)), in: .rect(cornerRadius: 22))
    }
}
