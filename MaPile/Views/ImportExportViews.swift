import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Section « Mes données » des réglages : import Goodreads / Babelio / CSV et export.
struct DataSection: View {
    @Query private var books: [Book]
    @State private var showingImporter = false
    @State private var imported: [LibraryCSV.ImportedBook] = []
    @State private var showingPreview = false
    @State private var exportURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        Section {
            Button("Importer (Goodreads, Babelio, tableur)", systemImage: "square.and.arrow.down") {
                showingImporter = true
            }
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Exporter ma bibliothèque (CSV)", systemImage: "square.and.arrow.up")
                }
            }
        } header: {
            Text("Mes données")
        } footer: {
            Text("Goodreads : Mes livres › Import and export › Export Library. Babelio : Mon profil › Exporter ma bibliothèque. L'export s'ouvre dans Excel, Numbers ou Google Sheets.")
        }
        .fileImporter(isPresented: $showingImporter,
                      allowedContentTypes: [.commaSeparatedText, .plainText, .text, .data]) { result in
            handleImport(result)
        }
        .sheet(isPresented: $showingPreview) {
            ImportPreviewSheet(items: imported)
        }
        .alert(errorMessage ?? "", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .task(id: books.count) { exportURL = LibraryCSV.exportFile(books: books) }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            errorMessage = "Impossible de lire ce fichier."
            return
        }
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        let items = LibraryCSV.importBooks(from: text)
        if items.isEmpty {
            errorMessage = "Aucun livre trouvé. Le fichier doit être un CSV avec au moins une colonne « Titre » (ou « Title »)."
        } else {
            imported = items
            showingPreview = true
        }
    }
}

/// Aperçu avant import : nombre de livres, doublons ignorés.
struct ImportPreviewSheet: View {
    let items: [LibraryCSV.ImportedBook]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var library: [Book]
    @State private var done = false
    @State private var addedCount = 0

    private func exists(_ item: LibraryCSV.ImportedBook) -> Bool {
        library.contains { book in
            if let isbn = item.isbn, book.isbn == isbn { return true }
            return BookSearchService.normalize(book.title) == BookSearchService.normalize(item.title)
                && BookSearchService.normalize(book.authorList.first ?? "") == BookSearchService.normalize(item.author)
        }
    }

    private var newItems: [LibraryCSV.ImportedBook] { items.filter { !exists($0) } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Livres dans le fichier", value: "\(items.count)")
                    LabeledContent("Déjà dans MaPile (ignorés)", value: "\(items.count - newItems.count)")
                    LabeledContent("À importer", value: "\(newItems.count)")
                } footer: {
                    Text("Les couvertures, résumés et notes se complètent ensuite automatiquement à l'ouverture de chaque fiche, ou d'un coup avec « Mettre à jour toute la bibliothèque » (menu ⚙︎ des onglets Lus et PAL).")
                }
                Section("Aperçu") {
                    ForEach(newItems.prefix(50)) { item in
                        VStack(alignment: .leading) {
                            Text(item.title).font(.headline)
                            Text("\(item.author) · \(item.status.longTitle)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Importer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importer", systemImage: "checkmark") { importAll() }
                        .buttonStyle(.glassProminent)
                        .disabled(newItems.isEmpty || done)
                }
            }
            .alert("\(addedCount) livres importés 🎉", isPresented: $done) {
                Button("OK") { dismiss() }
            }
        }
    }

    private func importAll() {
        var count = 0
        for item in newItems {
            let book = Book(title: item.title, authors: item.author, status: item.status)
            book.isbn = item.isbn
            book.myRating = item.rating
            book.myReview = item.review
            book.pageCount = item.pages
            book.seriesName = item.seriesName
            book.seriesIndex = item.seriesIndex
            if let added = item.dateAdded { book.dateAdded = added }
            if item.status == .read { book.dateFinished = item.dateRead ?? item.dateAdded ?? .now }
            if item.status == .reading { book.dateStarted = item.dateAdded ?? .now }
            context.insert(book)
            count += 1
        }
        try? context.save()
        addedCount = count
        done = true
    }
}
