import SwiftUI

/// Écran « Nouveautés » montré une fois aux lecteurs qui viennent de mettre l'app à jour.
enum WhatsNew {
    /// Version dont on présente les nouveautés (à changer à chaque mise à jour annoncée).
    static let version = "1.1"
    private static let seenKey = "whatsNewSeenVersion"

    struct Item: Identifiable {
        let id = UUID()
        let systemImage: String
        let color: Color
        let title: String
        let text: String
    }

    static let items: [Item] = [
        Item(systemImage: "sparkles", color: .purple, title: "Que lire ensuite ?",
             text: "3 idées selon votre envie (plot twist, romance, fantastique…), dans votre PAL ou parmi de nouveaux livres."),
        Item(systemImage: "books.vertical.circle", color: .orange, title: "Les sagas dans l'ordre",
             text: "Sur la fiche d'un livre, l'ordre de lecture des tomes et ceux qui vous manquent."),
        Item(systemImage: "person.crop.circle", color: .blue, title: "Auteur cliquable",
             text: "Touchez le nom d'un auteur pour voir ses autres livres et les ajouter."),
        Item(systemImage: "timer", color: .red, title: "Chrono et historique",
             text: "Chronométrez vos séances, gardez votre série de jours et retrouvez l'historique de chaque livre."),
        Item(systemImage: "square.stack.3d.up", color: .teal, title: "Piles et partage",
             text: "Créez vos piles (par auteur, genre, saga…) et partagez votre PAL ou vos lectures."),
        Item(systemImage: "bubble.left.and.text.bubble.right", color: .pink, title: "Les avis MaPile",
             text: "Notez et commentez vos livres, et lisez les avis anonymes des autres lecteurs."),
        Item(systemImage: "icloud", color: .cyan, title: "Et aussi",
             text: "Synchro iCloud, widgets, citations, badges, « Mon année MaPile », import Goodreads et Babelio."),
    ]

    /// À montrer : lecteur déjà installé (il a des livres) qui n'a pas encore vu ces nouveautés.
    /// Une nouvelle installation ne voit pas l'écran : tout est nouveau pour elle.
    @MainActor
    static func shouldShow(hasBooks: Bool) -> Bool {
        let defaults = UserDefaults.standard
        if ProcessInfo.processInfo.arguments.contains("-demoData") { return false }
        if defaults.string(forKey: seenKey) == version { return false }
        guard hasBooks else {
            markSeen()
            return false
        }
        return true
    }

    static func markSeen() {
        UserDefaults.standard.set(version, forKey: seenKey)
    }
}

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(spacing: 6) {
                        Text("Quoi de neuf ?")
                            .font(.largeTitle.weight(.bold))
                        Text("MaPile \(WhatsNew.version)")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                    .padding(.bottom, 6)

                    ForEach(WhatsNew.items) { item in
                        HStack(alignment: .top, spacing: 16) {
                            Image(systemName: item.systemImage)
                                .font(.title2)
                                .foregroundStyle(item.color)
                                .frame(width: 40)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title).font(.headline)
                                Text(item.text)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            Button {
                dismiss()
            } label: {
                Text("C'est parti !")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
            .frame(maxWidth: 560)
        }
        .onDisappear { WhatsNew.markSeen() }
    }
}
