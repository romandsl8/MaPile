import SwiftUI
import SwiftData

@main
struct MaPileApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: Book.self)
    }
}

enum AppTab: String, Hashable {
    case read, toRead, stats
}

/// Barre d'onglets Liquid Glass : Lus, PAL, Statistiques.
struct RootView: View {
    @SceneStorage("selectedTab") private var tab: AppTab = .read

    var body: some View {
        TabView(selection: $tab) {
            Tab("Lus", systemImage: "checkmark.seal", value: AppTab.read) {
                LibraryView(status: .read)
            }
            Tab("PAL", systemImage: "books.vertical", value: AppTab.toRead) {
                LibraryView(status: .toRead)
            }
            Tab("Statistiques", systemImage: "chart.bar.xaxis", value: AppTab.stats) {
                StatsView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
