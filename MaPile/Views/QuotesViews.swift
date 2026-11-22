import SwiftUI
import SwiftData
import VisionKit

/// Carte « Citations » sur la fiche d'un livre.
struct QuotesCard: View {
    let book: Book
    @Environment(\.modelContext) private var context
    @Query private var quotes: [Quote]
    @State private var showingEditor = false
    @State private var quoteToShare: Quote?

    init(book: Book) {
        self.book = book
        let id = book.uuid.uuidString
        _quotes = Query(filter: #Predicate<Quote> { $0.bookID == id }, sort: \Quote.createdAt, order: .reverse)
    }

    var body: some View {
        SectionCard(title: "Citations", systemImage: "quote.opening") {
            if quotes.isEmpty {
                Text("Gardez vos passages préférés : tapez-les ou photographiez la page pour sélectionner le texte.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(quotes) { quote in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("« \(quote.text) »")
                            .font(.system(.body, design: .serif).italic())
                            .textSelection(.enabled)
                        HStack {
                            if quote.page > 0 {
                                Text("Page \(quote.page)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Menu {
                                Button("Partager en image", systemImage: "square.and.arrow.up") { quoteToShare = quote }
                                Button("Supprimer", systemImage: "trash", role: .destructive) {
                                    withAnimation { context.delete(quote) }
                                }
                            } label: {
                                Label("Options", systemImage: "ellipsis")
                                    .labelStyle(.iconOnly)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28, height: 22)
                            }
                        }
                    }
                    if quote.id != quotes.last?.id { Divider() }
                }
            }
            Button("Ajouter une citation", systemImage: "plus") { showingEditor = true }
                .buttonStyle(.glass)
                .controlSize(.small)
        }
        .sheet(isPresented: $showingEditor) { QuoteEditorSheet(book: book) }
        .sheet(item: $quoteToShare) { quote in QuoteShareSheet(quote: quote, book: book) }
    }
}

/// Saisie d'une citation, au clavier ou en sélectionnant le texte d'une page photographiée.
struct QuoteEditorSheet: View {
    let book: Book
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var page: Int?
    @State private var showingScanner = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Le passage qui vous a marqué…", text: $text, axis: .vertical)
                        .lineLimit(4...14)
                    Button("Sélectionner le texte d'une page (caméra)", systemImage: "text.viewfinder") {
                        showingScanner = true
                    }
                    .disabled(!TextPageScanner.isAvailable)
                } footer: {
                    Text("Visez la page, puis touchez les lignes à ajouter : elles s'ajoutent au texte.")
                }
                Section("Page") {
                    TextField("Numéro de page (facultatif)", value: $page, format: .number)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle("Nouvelle citation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", systemImage: "checkmark") {
                        let quote = Quote(book: book, text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                          page: page ?? 0)
                        context.insert(quote)
                        try? context.save()
                        dismiss()
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { if book.currentPage > 0 { page = book.currentPage } }
            .sheet(isPresented: $showingScanner) {
                NavigationStack {
                    TextPageScanner { line in
                        let separator = text.isEmpty || text.hasSuffix(" ") ? "" : " "
                        text += separator + line
                    }
                    .ignoresSafeArea()
                    .overlay(alignment: .bottom) {
                        Text("Touchez les lignes à ajouter")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .glassEffect()
                            .padding(.bottom, 40)
                    }
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("OK", systemImage: "checkmark") { showingScanner = false }
                        }
                    }
                }
            }
        }
    }
}

/// Caméra « texte en direct » : chaque ligne touchée est renvoyée.
struct TextPageScanner: UIViewControllerRepresentable {
    var onText: (String) -> Void

    @MainActor static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.text(languages: ["fr-FR", "en-US"])],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        if !controller.isScanning { try? controller.startScanning() }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onText: onText) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onText: (String) -> Void
        init(onText: @escaping (String) -> Void) { self.onText = onText }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            if case .text(let text) = item {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onText(text.transcript.replacingOccurrences(of: "\n", with: " "))
            }
        }
    }
}

/// Partage d'une citation sous forme de jolie carte.
struct QuoteShareSheet: View {
    let quote: Quote
    let book: Book
    @Environment(\.dismiss) private var dismiss
    @State private var image: Image?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                QuoteCardImage(text: quote.text, title: book.title, author: book.displayAuthors)
                    .scaleEffect(0.45)
                    .frame(width: 324, height: 420)
                if let image {
                    ShareLink(item: image, preview: SharePreview("Citation de « \(book.title) »", image: image)) {
                        Label("Partager", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .padding(.horizontal)
                }
            }
            .navigationTitle("Partager la citation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer", systemImage: "xmark") { dismiss() }
                }
            }
            .task {
                let renderer = ImageRenderer(content: QuoteCardImage(text: quote.text, title: book.title, author: book.displayAuthors))
                renderer.scale = 2
                if let ui = renderer.uiImage { image = Image(uiImage: ui) }
            }
        }
    }
}

/// Carte de citation (format portrait, pour les stories et les réseaux).
struct QuoteCardImage: View {
    let text: String
    let title: String
    let author: String

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("“")
                .font(.system(size: 120, weight: .bold, design: .serif))
                .foregroundStyle(.white.opacity(0.5))
                .frame(height: 70)
            Text(text)
                .font(.system(size: 40, weight: .medium, design: .serif))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.4)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 28, weight: .bold))
                Text(author).font(.system(size: 24))
            }
            .foregroundStyle(.white.opacity(0.9))
            Text("📚 MaPile")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(60)
        .frame(width: 720, height: 930, alignment: .topLeading)
        .background(LinearGradient(colors: [Color(red: 0.95, green: 0.55, blue: 0.34), Color(red: 0.59, green: 0.2, blue: 0.36)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}
