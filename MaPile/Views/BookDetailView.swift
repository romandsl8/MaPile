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
    @State private var confirmDelete = false
    @State private var summaryExpanded = false
    @State private var refreshing = false
    @State private var refreshMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                actions
                if book.status == .read { myOpinion }
                community
                if !book.summary.isEmpty { summary }
                details
            }
            .frame(maxWidth: 680)
            .padding(.horizontal)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .background(alignment: .top) { backdrop }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(isPresented: $showingFinish) { FinishBookSheet(book: book) }
        .sheet(isPresented: $showingEdit) { EditBookSheet(book: book) }
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
            // Télécharge la couverture pour l'avoir hors connexion.
            if book.coverData == nil, let url = book.coverURL {
                book.coverData = await BookSearchService.downloadImage(url)
            }
        }
    }

    // MARK: - Sections

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
            }
            Label(book.status == .read ? "Lu" : "Dans ma PAL", systemImage: book.status.systemImage)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .glassEffect(.regular.tint(book.status == .read ? .green.opacity(0.35) : .orange.opacity(0.35)))
        }
        .frame(maxWidth: .infinity)
    }

    private var actions: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                if book.status == .toRead {
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
            Text("Les services gratuits fournissent la note moyenne, pas le texte des avis. Touchez « Avis en ligne » pour les lire.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
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
                Button("Modifier les infos", systemImage: "pencil") { showingEdit = true }
                Button("Actualiser depuis Internet", systemImage: "arrow.clockwise") {
                    Task { await refresh() }
                }
                .disabled(refreshing)
                if book.status == .toRead {
                    Button("J'ai fini ce livre", systemImage: "checkmark.seal") { showingFinish = true }
                } else {
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
        guard let result = await BookSearchService.bestMatch(title: book.title, authors: book.authors, isbn: book.isbn) else {
            refreshMessage = "Aucune information trouvée en ligne pour ce livre."
            return
        }
        let hadCover = book.coverURLString != nil
        book.apply(result, onlyMissing: true)
        if book.coverData == nil || !hadCover {
            book.coverData = await BookSearchService.downloadImage(book.coverURL)
        }
        refreshMessage = "Fiche mise à jour."
    }
}

/// Feuille « J'ai fini ce livre » : date de fin, note et avis.
struct FinishBookSheet: View {
    @Bindable var book: Book
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date.now
    @State private var rating = 0
    @State private var review = ""

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
            }
            .navigationTitle("Livre terminé 🎉")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", systemImage: "checkmark") {
                        withAnimation {
                            book.markAsRead(on: date)
                            book.myRating = rating
                            if !review.isEmpty { book.myReview = review }
                        }
                        dismiss()
                    }
                    .buttonStyle(.glassProminent)
                }
            }
            .onAppear {
                rating = book.myRating
                review = book.myReview
            }
        }
        .presentationDetents([.medium, .large])
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
