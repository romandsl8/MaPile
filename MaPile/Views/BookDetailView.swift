import SwiftUI
import SwiftData

/// Fiche d'un livre : couverture, infos, note des lecteurs, ma note et mon avis.
struct BookDetailView: View {
    @Bindable var book: Book
    var onDelete: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @State private var showingFinish = false
    @State private var showingEdit = false
    @State private var showingShelves = false
    @State private var showingLend = false
    @State private var lendName = ""
    @State private var showingNextVolume = false
    @State private var confirmDelete = false
    @State private var summaryExpanded = false
    @State private var refreshing = false
    @State private var refreshMessage: String?
    @State private var availableWidth: CGFloat = 0

    /// Écran large (iPhone déplié, paysage) : deux colonnes.
    private var isWide: Bool { availableWidth >= 700 }

    var body: some View {
        ScrollView {
            Group {
                if isWide {
                    HStack(alignment: .top, spacing: 28) {
                        VStack(spacing: 20) {
                            header
                            actions
                        }
                        .frame(width: 290)
                        VStack(spacing: 20) {
                            sections
                        }
                        .padding(.top, 12)
                    }
                    .frame(maxWidth: 1040)
                } else {
                    VStack(spacing: 20) {
                        header
                        actions
                        sections
                    }
                    .frame(maxWidth: 680)
                }
            }
            .padding(.horizontal, isWide ? 28 : 16)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            availableWidth = width
        }
        .background(alignment: .top) { backdrop }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(isPresented: $showingFinish) { FinishBookSheet(book: book) }
        .sheet(isPresented: $showingEdit) { EditBookSheet(book: book) }
        .sheet(isPresented: $showingShelves) { AddToShelfSheet(book: book) }
        .sheet(isPresented: $showingNextVolume) {
            AddBookView(defaultStatus: .toRead, initialQuery: "\(book.seriesName) tome \(book.seriesIndex + 1)")
        }
        .alert("Prêter « \(book.title) »", isPresented: $showingLend) {
            TextField("Prêté à…", text: $lendName)
            Button("Annuler", role: .cancel) { lendName = "" }
            Button("Prêter") { lend() }
        } message: {
            Text("Un rappel vous sera envoyé dans 30 jours pour penser à le récupérer.")
        }
        .confirmationDialog("Supprimer « \(book.title) » ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                onDelete()
                context.delete(book)
            }
        }
        .alert(refreshMessage ?? "", isPresented: Binding(get: { refreshMessage != nil }, set: { if !$0 { refreshMessage = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .task {
            // Fiche jamais vérifiée, ancienne ou incomplète : vérification discrète
            // (note avec le plus d'avis, infos manquantes, meilleure couverture).
            if BookUpdater.needsAutoCheck(book) {
                await BookUpdater.check(book)
            }
            // Télécharge la couverture pour l'avoir hors connexion.
            if book.coverData == nil, let url = book.coverURL {
                book.coverData = await BookSearchService.downloadImage(url)
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var sections: some View {
        if book.status == .read { myOpinion }
        community
        if CommunityService.isEnabled { CommunityReviewsCard(book: book) }
        // Les avis peuvent dévoiler l'intrigue : affichés seulement une fois le livre lu.
        if book.status == .read { ReaderReviewsCard(book: book) }
        if !book.summary.isEmpty { summary }
        QuotesCard(book: book)
        if book.lentTo != nil { loanCard }
        purchase
        details
    }

    // MARK: - Prêt

    private var loanCard: some View {
        SectionCard(title: "Livre prêté", systemImage: "person.2") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("À \(book.lentTo ?? "")")
                        .font(.headline)
                    if let date = book.lentAt {
                        Text("Depuis le \(date.formatted(.dateTime.day().month(.wide).year()))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Rendu", systemImage: "arrow.uturn.backward") { returnBook() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
        }
    }

    private func lend() {
        let name = lendName.trimmingCharacters(in: .whitespaces)
        lendName = ""
        guard !name.isEmpty else { return }
        withAnimation {
            book.lentTo = name
            book.lentAt = .now
        }
        Task { await ReadingReminder.scheduleLoanReminder(for: book) }
    }

    private func returnBook() {
        ReadingReminder.cancelLoanReminder(for: book)
        withAnimation {
            book.lentTo = nil
            book.lentAt = nil
        }
    }

    private var purchase: some View {
        let links = PurchaseLinks.links(for: book)
        let paper = links.filter { $0.format == .paper }
        let ebook = links.filter { $0.format == .ebook }
        return SectionCard(title: "Acheter ce livre", systemImage: "bag") {
            purchaseRow("Papier", systemImage: "book.closed", links: paper)
            purchaseRow("Numérique (ePub)", systemImage: "ipad.and.iphone", links: ebook)
        }
    }

    private func purchaseRow(_ title: String, systemImage: String, links: [PurchaseLink]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(links) { link in
                            Link(destination: link.url) {
                                Label(link.store, systemImage: "arrow.up.right")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var backdrop: some View {
        CoverView(book: book, cornerRadius: 0)
            .frame(maxWidth: .infinity)
            .frame(height: 380)
            .clipped()
            .blur(radius: 40)
            .opacity(0.45)
            .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
            .ignoresSafeArea()
    }

    private var header: some View {
        VStack(spacing: 14) {
            CoverView(book: book, cornerRadius: 10)
                .frame(width: 170)
                .shadow(color: .black.opacity(0.3), radius: 16, y: 10)
                .padding(.top, 12)
            VStack(spacing: 6) {
                Text(book.title)
                    .font(.system(.title2, design: .serif).weight(.bold))
                    .multilineTextAlignment(.center)
                Text(book.displayAuthors)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if !book.seriesName.isEmpty {
                    Text(book.seriesIndex > 0 ? "\(book.seriesName) · Tome \(book.seriesIndex)" : book.seriesName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }
            }
            Label(statusLabel, systemImage: book.status.systemImage)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .glassEffect(.regular.tint(statusTint.opacity(0.35)))
        }
        .frame(maxWidth: .infinity)
    }

    private var statusLabel: String {
        switch book.status {
        case .toRead: "Dans ma PAL"
        case .reading:
            if book.pageCount > 0 { "En cours · page \(book.currentPage)/\(book.pageCount)" } else { "En cours" }
        case .read: "Lu"
        }
    }

    private var statusTint: Color {
        switch book.status {
        case .toRead: .orange
        case .reading: .blue
        case .read: .green
        }
    }

    private var actions: some View {
        let layout = isWide ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        return GlassEffectContainer(spacing: 12) {
            layout {
                if book.status == .toRead {
                    Button {
                        withAnimation { book.startReading() }
                    } label: {
                        Label("Commencer", systemImage: "book.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    Button {
                        showingFinish = true
                    } label: {
                        Label("J'ai fini !", systemImage: "checkmark.seal.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                } else if book.status == .reading {
                    Button {
                        showingFinish = true
                    } label: {
                        Label("J'ai fini !", systemImage: "checkmark.seal.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                } else {
                    Button {
                        withAnimation { book.moveToPile() }
                    } label: {
                        Label("Remettre en PAL", systemImage: "books.vertical")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
                if let url = book.infoURL {
                    Button {
                        openURL(url)
                    } label: {
                        Label("Avis en ligne", systemImage: "safari")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
            }
            .controlSize(.large)
        }
    }

    private var myOpinion: some View {
        SectionCard(title: "Mon avis", systemImage: "heart.text.square") {
            StarRatingPicker(rating: $book.myRating)
            TextField("Qu'avez-vous pensé de ce livre ?", text: $book.myReview, axis: .vertical)
                .lineLimit(3...12)
                .padding(12)
                .background(Color(uiColor: .tertiarySystemGroupedBackground), in: .rect(cornerRadius: 14))
            DatePicker("Terminé le",
                       selection: Binding(get: { book.dateFinished ?? .now }, set: { book.dateFinished = $0 }),
                       in: ...Date.now,
                       displayedComponents: .date)
        }
    }

    private var community: some View {
        SectionCard(title: "Note des lecteurs", systemImage: "person.2") {
            if let rating = book.communityRating {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(rating.frenchDecimal)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    VStack(alignment: .leading, spacing: 3) {
                        StarRatingDisplay(rating: rating, size: 15)
                        Text(ratingCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Aucune note de lecteurs trouvée pour ce livre.")
                    .foregroundStyle(.secondary)
            }
            Text("MaPile garde la note de la plateforme qui a le plus d'avis (Apple Books, Google Books ou Open Library). Touchez « Avis en ligne » pour les lire.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            HStack {
                Button {
                    Task { await refresh() }
                } label: {
                    if refreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Vérifier", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .disabled(refreshing)
                Spacer()
                if let checked = book.lastCheckedAt {
                    Text("Vérifiée \(checked.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var ratingCaption: String {
        var parts: [String] = []
        if let count = book.communityRatingsCount {
            parts.append("\(count) avis")
        }
        if let source = book.ratingSource { parts.append(source) }
        return parts.joined(separator: " · ")
    }

    private var summary: some View {
        SectionCard(title: "Résumé", systemImage: "text.alignleft") {
            Text(book.summary)
                .font(.body)
                .lineLimit(summaryExpanded ? nil : 7)
                .textSelection(.enabled)
            Button(summaryExpanded ? "Réduire" : "Lire la suite") {
                withAnimation(.smooth) { summaryExpanded.toggle() }
            }
            .font(.subheadline.weight(.semibold))
        }
    }

    private var details: some View {
        SectionCard(title: "Informations", systemImage: "info.circle") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                if book.pageCount > 0 { row("Pages", "\(book.pageCount)") }
                if let v = book.publisher, !v.isEmpty { row("Éditeur", v) }
                if let v = book.publishedDate, !v.isEmpty { row("Parution", v) }
                if !book.categories.isEmpty { row("Genres", book.categories) }
                if let v = book.isbn { row("ISBN", v) }
                row("Ajouté le", book.dateAdded.formatted(date: .long, time: .omitted))
            }
            .font(.subheadline)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }

    // MARK: - Barre d'outils

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Ajouter à une pile", systemImage: "square.stack") { showingShelves = true }
                if book.lentTo == nil {
                    Button("Prêter ce livre…", systemImage: "person.2.badge.gearshape") { showingLend = true }
                } else {
                    Button("Livre rendu", systemImage: "arrow.uturn.backward") { returnBook() }
                }
                if !book.seriesName.isEmpty {
                    Button("Chercher le tome suivant", systemImage: "forward.end") { showingNextVolume = true }
                }
                Button("Modifier les infos", systemImage: "pencil") { showingEdit = true }
                Button("Vérifier la note et la couverture", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await refresh() }
                }
                .disabled(refreshing)
                if book.status == .toRead {
                    Button("Commencer la lecture", systemImage: "book") {
                        withAnimation { book.startReading() }
                    }
                }
                if book.status != .read {
                    Button("J'ai fini ce livre", systemImage: "checkmark.seal") { showingFinish = true }
                }
                if book.status != .toRead {
                    Button("Remettre dans la PAL", systemImage: "books.vertical") {
                        withAnimation { book.moveToPile() }
                    }
                }
                Divider()
                Button("Supprimer", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } label: {
                if refreshing {
                    ProgressView()
                } else {
                    Label("Plus", systemImage: "ellipsis")
                }
            }
        }
    }

    private func refresh() async {
        refreshing = true
        defer { refreshing = false }
        switch await BookUpdater.check(book) {
        case .updated(let details):
            refreshMessage = "Fiche mise à jour\n\(details)"
        case .unchanged:
            refreshMessage = "Fiche déjà à jour : c'est la meilleure note et la meilleure couverture trouvées."
        case .notFound:
            refreshMessage = "Ce livre n'a pas été retrouvé exactement en ligne. Vérifiez son titre et son auteur avec « Modifier les infos »."
        }
    }
}

/// Feuille « J'ai fini ce livre » : date de fin, note et avis.
struct FinishBookSheet: View {
    @Bindable var book: Book
    @Environment(\.dismiss) private var dismiss
    @AppStorage("communityRulesAccepted") private var rulesAccepted = false
    @State private var date = Date.now
    @State private var rating = 0
    @State private var review = ""
    @State private var shareWithCommunity = false
    @State private var saving = false
    @State private var shareError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        CoverView(book: book, cornerRadius: 5).frame(width: 50)
                        VStack(alignment: .leading) {
                            Text(book.title).font(.headline)
                            Text(book.displayAuthors).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    DatePicker("Terminé le", selection: $date, in: ...Date.now, displayedComponents: .date)
                }
                Section("Ma note") {
                    StarRatingPicker(rating: $rating, size: 32)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                Section("Mon avis") {
                    TextField("Facultatif", text: $review, axis: .vertical)
                        .lineLimit(3...10)
                }
                if CommunityService.isEnabled {
                    Section {
                        // Décoché par défaut : rien n'est partagé sans action de l'utilisateur.
                        Toggle(isOn: $shareWithCommunity) {
                            Label("Partager anonymement dans « Les avis MaPile »", systemImage: "person.3")
                        }
                        .disabled(rating == 0)
                    } footer: {
                        if rating == 0 {
                            Text("Donnez une note pour pouvoir la partager.")
                        } else {
                            Text("Votre note et votre avis seront visibles par les autres lecteurs MaPile, sans votre nom. En partageant, vous acceptez les [règles de la communauté](https://romandsl8.github.io/mapile-site/regles.html). Vous pourrez retirer votre avis à tout moment.")
                        }
                    }
                }
            }
            .navigationTitle("Livre terminé 🎉")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Enregistrer", systemImage: "checkmark") {
                            Task { await save() }
                        }
                        .buttonStyle(.glassProminent)
                    }
                }
            }
            .onAppear {
                rating = book.myRating
                review = book.myReview
            }
            .alert(shareError ?? "", isPresented: Binding(get: { shareError != nil }, set: { if !$0 { shareError = nil; dismiss() } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Le livre est bien enregistré comme lu. Vous pourrez partager votre avis plus tard depuis sa fiche.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        let wasAlreadyRead = book.status == .read
        withAnimation {
            book.markAsRead(on: date)
            book.myRating = rating
            if !review.isEmpty { book.myReview = review }
        }
        // Livre terminé : vibration et pluie de confettis.
        if !wasAlreadyRead { NotificationCenter.default.post(name: .bookFinished, object: nil) }
        if shareWithCommunity && rating > 0 {
            saving = true
            rulesAccepted = true
            do {
                try await CommunityService.publish(book: book)
            } catch {
                saving = false
                shareError = error.localizedDescription
                return
            }
            saving = false
        }
        dismiss()
    }
}

/// Modification manuelle des informations d'un livre.
struct EditBookSheet: View {
    @Bindable var book: Book
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Livre") {
                    TextField("Titre", text: $book.title)
                    TextField("Auteur(s), séparés par des virgules", text: $book.authors)
                    TextField("Nombre de pages", value: $book.pageCount, format: .number)
                        .keyboardType(.numberPad)
                    TextField("Genres, séparés par des virgules", text: $book.categories)
                }
                Section {
                    TextField("Nom de la série (ex. Harry Potter)", text: $book.seriesName)
                    Stepper(value: $book.seriesIndex, in: 0...200) {
                        Text(book.seriesIndex == 0 ? "Numéro du tome : —" : "Tome \(book.seriesIndex)")
                    }
                } header: {
                    Text("Série ou saga")
                } footer: {
                    Text("Le menu « … » de la fiche proposera alors de chercher le tome suivant.")
                }
                Section("Édition") {
                    TextField("Éditeur", text: Binding(get: { book.publisher ?? "" }, set: { book.publisher = $0.isEmpty ? nil : $0 }))
                    TextField("Date de parution", text: Binding(get: { book.publishedDate ?? "" }, set: { book.publishedDate = $0.isEmpty ? nil : $0 }))
                    TextField("ISBN", text: Binding(get: { book.isbn ?? "" }, set: { book.isbn = $0.isEmpty ? nil : $0 }))
                        .keyboardType(.numberPad)
                }
                Section("Résumé") {
                    TextField("Résumé", text: $book.summary, axis: .vertical)
                        .lineLimit(4...20)
                }
            }
            .navigationTitle("Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK", systemImage: "checkmark") { dismiss() }
                        .buttonStyle(.glassProminent)
                }
            }
        }
    }
}
