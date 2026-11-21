import SwiftUI

/// Carte « Avis des lecteurs » sur la fiche d'un livre lu (avis publiés sur Apple Books).
struct ReaderReviewsCard: View {
    @Bindable var book: Book

    @State private var reviews: [BookSearchService.ReaderReview] = []
    @State private var loading = true
    @State private var showingAll = false

    var body: some View {
        SectionCard(title: "Avis des lecteurs", systemImage: "text.bubble") {
            if loading {
                HStack {
                    ProgressView()
                    Text("Recherche des avis…").foregroundStyle(.secondary)
                }
            } else if reviews.isEmpty {
                Text("Aucun avis écrit trouvé pour ce livre sur Apple Books.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(reviews.prefix(3)) { review in
                    ReviewRow(review: review, lineLimit: 5)
                    if review.id != reviews.prefix(3).last?.id { Divider() }
                }
                Button {
                    showingAll = true
                } label: {
                    Label("Voir tous les avis", systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
            Text("Avis publiés par les lecteurs d'Apple Books.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .task(id: book.appleBooksID) { await load() }
        .sheet(isPresented: $showingAll) {
            if let id = book.appleBooksID {
                AllReviewsView(appleBooksID: id, bookTitle: book.title, storeURL: book.infoURL)
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        if book.appleBooksID == nil {
            book.appleBooksID = await BookSearchService.findAppleBooksID(title: book.title, authors: book.authors)
        }
        guard let id = book.appleBooksID else {
            reviews = []
            return
        }
        reviews = await BookSearchService.appleBooksReviews(id: id)
    }
}

/// Liste complète des avis, triable par utilité ou date.
struct AllReviewsView: View {
    let appleBooksID: String
    let bookTitle: String
    let storeURL: URL?

    @Environment(\.dismiss) private var dismiss
    @State private var sort: BookSearchService.ReviewSort = .helpful
    @State private var reviews: [BookSearchService.ReaderReview] = []
    @State private var loading = true

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Trier", selection: $sort) {
                        ForEach(BookSearchService.ReviewSort.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }
                if loading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(reviews) { review in
                        ReviewRow(review: review, lineLimit: nil)
                            .padding(.vertical, 4)
                    }
                }
                Section {
                    if let storeURL, storeURL.host?.contains("apple.com") == true {
                        Link(destination: storeURL) {
                            Label("Ouvrir dans Apple Books", systemImage: "book")
                        }
                    }
                } footer: {
                    Text("Avis publiés par les lecteurs d'Apple Books. Ils peuvent révéler l'intrigue.")
                }
            }
            .navigationTitle(bookTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK", systemImage: "checkmark") { dismiss() }
                }
            }
            .task(id: sort) {
                loading = true
                reviews = await BookSearchService.appleBooksReviews(id: appleBooksID, sort: sort)
                loading = false
            }
        }
    }
}

private struct ReviewRow: View {
    let review: BookSearchService.ReaderReview
    let lineLimit: Int?
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                StarRatingDisplay(rating: Double(review.rating), size: 11)
                if !review.title.isEmpty {
                    Text(review.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
            }
            if !review.content.isEmpty {
                Text(review.content)
                    .font(.subheadline)
                    .lineLimit(expanded ? nil : lineLimit)
                    .onTapGesture { withAnimation(.smooth) { expanded.toggle() } }
            }
            HStack(spacing: 4) {
                Text(review.author)
                if let date = review.date {
                    Text("·")
                    Text(date, format: .dateTime.day().month(.abbreviated).year())
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
