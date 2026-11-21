import SwiftUI

/// Écran « À propos » : confidentialité, sources des informations et liens d'assistance.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    static let siteURL = URL(string: "https://romandsl8.github.io/mapile-site/")!
    static let privacyURL = URL(string: "https://romandsl8.github.io/mapile-site/confidentialite.html")!

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "books.vertical.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.accentColor.gradient)
                            .padding(18)
                            .glassEffect(.regular, in: .rect(cornerRadius: 24))
                        Text("MaPile")
                            .font(.system(.title, design: .serif).weight(.bold))
                        Text("Suivez vos lectures, simplement.")
                            .foregroundStyle(.secondary)
                        Text(version)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section("Vos données") {
                    Label("Votre bibliothèque est enregistrée uniquement sur cet iPhone.", systemImage: "iphone")
                    Label("Aucun compte, aucune publicité, aucun suivi.", systemImage: "hand.raised")
                    Label("Les recherches de livres sont envoyées à Google Books et Open Library pour trouver les informations, sans données personnelles.", systemImage: "magnifyingglass")
                }

                Section {
                    Link(destination: URL(string: "https://books.google.com")!) {
                        Label("Google Books", systemImage: "book")
                    }
                    Link(destination: URL(string: "https://openlibrary.org")!) {
                        Label("Open Library (Internet Archive)", systemImage: "building.columns")
                    }
                } header: {
                    Text("Sources des informations")
                } footer: {
                    Text("Couvertures, résumés et notes des lecteurs proviennent de ces services et restent la propriété de leurs auteurs et éditeurs.")
                }

                Section("Aide") {
                    Link(destination: Self.privacyURL) {
                        Label("Politique de confidentialité", systemImage: "lock.shield")
                    }
                    Link(destination: Self.siteURL) {
                        Label("Assistance et contact", systemImage: "questionmark.circle")
                    }
                }
            }
            .navigationTitle("À propos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK", systemImage: "checkmark") { dismiss() }
                }
            }
        }
    }
}
