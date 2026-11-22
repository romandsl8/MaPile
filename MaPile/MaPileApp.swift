import SwiftUI
import SwiftData

/// Base de données partagée par l'app et par Siri / Raccourcis (App Intents).
@MainActor
enum MaPileStore {
    static let container: ModelContainer = {
        // « -demoData » : bibliothèque d'exemple en mémoire (captures d'écran automatiques).
        let demo = ProcessInfo.processInfo.arguments.contains("-demoData")
        // La bibliothèque reste sur l'iPhone : iCloud ne sert qu'aux « Avis MaPile » (base publique).
        let config = ModelConfiguration(isStoredInMemoryOnly: demo, cloudKitDatabase: .none)
        do {
            let container = try ModelContainer(for: Book.self, Shelf.self, ReadingSession.self, Quote.self, configurations: config)
            if demo { DemoData.insert(into: container.mainContext) }
            return container
        } catch {
            fatalError("Impossible d'ouvrir la base de données : \(error)")
        }
    }()
}

@main
struct MaPileApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .onAppear { ReadingReminder.refreshIfNeeded() }
        }
        .modelContainer(MaPileStore.container)
    }
}

enum AppTab: String, Hashable {
    case reading, read, toRead, stats, search
}

/// Barre d'onglets Liquid Glass : En cours, Lus, PAL, Statistiques et le bouton de recherche séparé.
struct RootView: View {
    @SceneStorage("selectedTab") private var tab: AppTab = .reading
    @State private var importRequest: ShelfImportRequest?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context

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
        // Widgets : mis à jour quand l'app passe en arrière-plan.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { WidgetBridge.refresh(context) }
            // Synchro iCloud (si activée) au retour dans l'app et en la quittant.
            if phase != .inactive { CloudSync.shared.syncNow() }
        }
        .task { CloudSync.shared.start() }
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
