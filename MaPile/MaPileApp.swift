import SwiftUI
import SwiftData

@main
struct MaPileApp: App {
    let container: ModelContainer

    init() {
        // « -demoData » : bibliothèque d'exemple en mémoire (captures d'écran automatiques).
        let demo = ProcessInfo.processInfo.arguments.contains("-demoData")
        // La bibliothèque reste sur l'iPhone : iCloud ne sert qu'aux « Avis MaPile » (base publique).
        let config = ModelConfiguration(isStoredInMemoryOnly: demo, cloudKitDatabase: .none)
        do {
            container = try ModelContainer(for: Book.self, Shelf.self, configurations: config)
        } catch {
            fatalError("Impossible d'ouvrir la base de données : \(error)")
        }
        if demo { DemoData.insert(into: container.mainContext) }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}

enum AppTab: String, Hashable {
    case reading, read, toRead, stats, search
}

/// Barre d'onglets Liquid Glass : En cours, Lus, PAL, Statistiques et le bouton de recherche séparé.
struct RootView: View {
    @SceneStorage("selectedTab") private var tab: AppTab = .reading
    @State private var importRequest: ShelfImportRequest?

    var body: some View {
        TabView(selection: $tab) {
            Tab("En cours", systemImage: "book", value: AppTab.reading) {
                ReadingView()
            }
            Tab("Lus", systemImage: "checkmark.seal", value: AppTab.read) {
                LibraryView(status: .read)
            }
            Tab("PAL", systemImage: "books.vertical", value: AppTab.toRead) {
                LibraryView(status: .toRead)
            }
            Tab("Statistiques", systemImage: "chart.bar.xaxis", value: AppTab.stats) {
                StatsView()
            }
            Tab("Ajouter", systemImage: "plus.magnifyingglass", value: AppTab.search, role: .search) {
                AddBookView(defaultStatus: .toRead, embedded: true)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .celebratesFinishedBooks()
        .onAppear {
            if let raw = UserDefaults.standard.string(forKey: "initialTab"), let initial = AppTab(rawValue: raw) {
                tab = initial
            }
        }
        // Lien de pile partagée (« mapile://pile#p=… ») : proposition d'import.
        .onOpenURL { url in
            if let payload = ShelfSharing.decode(url) {
                importRequest = ShelfImportRequest(payload: payload)
            }
        }
        .sheet(item: $importRequest) { request in
            ImportShelfSheet(payload: request.payload)
        }
    }
}
