import SwiftUI

/// Écran « Réglages et à propos » : rappel de lecture, confidentialité, sources et assistance.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ReadingReminder.enabledKey) private var reminderEnabled = false
    @AppStorage(ReadingReminder.hourKey) private var reminderHour = 21
    @AppStorage(ReadingReminder.minuteKey) private var reminderMinute = 0
    @State private var reminderDenied = false
    @AppStorage(CloudSync.enabledKey) private var syncEnabled = false
    @AppStorage(CloudSync.lastSyncKey) private var lastSync = 0.0
    @AppStorage(CloudSync.errorKey) private var syncError = ""

    private var syncSection: some View {
        Section {
            Toggle(isOn: Binding(get: { syncEnabled }, set: { newValue in
                syncEnabled = newValue
                if newValue { CloudSync.shared.start() } else { CloudSync.shared.stop() }
            })) {
                Label("Synchroniser avec iCloud", systemImage: "icloud")
            }
            if syncEnabled {
                if !syncError.isEmpty {
                    Label(syncError, systemImage: "exclamationmark.icloud")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                } else if lastSync > 0 {
                    LabeledContent("Dernière synchro",
                                   value: Date(timeIntervalSince1970: lastSync).formatted(.relative(presentation: .named)))
                }
                Button {
                    CloudSync.shared.syncNow()
                } label: {
                    Label("Synchroniser maintenant", systemImage: "arrow.triangle.2.circlepath")
                }
            }
        } header: {
            Text("iCloud")
        } footer: {
            Text("Retrouvez vos livres, piles, séances et citations sur tous vos appareils connectés au même compte iCloud. Activez l'option sur chacun d'eux. Les données restent dans votre iCloud privé : personne d'autre, pas même MaPile, ne peut les lire.")
        }
    }

    private var reminderTime: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: .now) ?? .now
        } set: { date in
            reminderHour = Calendar.current.component(.hour, from: date)
            reminderMinute = Calendar.current.component(.minute, from: date)
            Task { await ReadingReminder.scheduleDaily() }
        }
    }

    private var reminderSection: some View {
        Section {
            Toggle(isOn: Binding(get: { reminderEnabled }, set: { newValue in
                reminderEnabled = newValue
                Task {
                    if newValue {
                        let allowed = await ReadingReminder.scheduleDaily()
                        if !allowed {
                            reminderEnabled = false
                            reminderDenied = true
                        }
                    } else {
                        ReadingReminder.cancelDaily()
                    }
                }
            })) {
                Label("Rappel de lecture quotidien", systemImage: "bell.badge")
            }
            if reminderEnabled {
                DatePicker("Heure", selection: reminderTime, displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("Rappel")
        } footer: {
            Text(reminderDenied
                 ? "Les notifications sont désactivées pour MaPile. Autorisez-les dans Réglages › Notifications › MaPile."
                 : "Une notification douce chaque jour à l'heure choisie, pour garder votre série de lecture.")
        }
    }

    static let siteURL = URL(string: "https://mapile.pages.dev/")!
    static let privacyURL = URL(string: "https://mapile.pages.dev/confidentialite")!

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

                reminderSection

                syncSection

                DataSection()

                Section("Vos données") {
                    Label(syncEnabled
                          ? "Votre bibliothèque est enregistrée sur cet iPhone et dans votre iCloud privé."
                          : "Votre bibliothèque est enregistrée uniquement sur cet iPhone.", systemImage: "iphone")
                    Label("Aucun compte, aucune publicité, aucun suivi.", systemImage: "hand.raised")
                    if CommunityService.isEnabled {
                        Label("« Les avis MaPile » : seuls les avis que vous choisissez de partager sont publiés, anonymement, et vous pouvez les retirer à tout moment.", systemImage: "person.3")
                    }
                    Label("Les recherches de livres sont envoyées à Google Books, Open Library et Apple Books pour trouver les informations, sans données personnelles.", systemImage: "magnifyingglass")
                }

                Section {
                    Link(destination: URL(string: "https://books.google.com")!) {
                        Label("Google Books", systemImage: "book")
                    }
                    Link(destination: URL(string: "https://openlibrary.org")!) {
                        Label("Open Library (Internet Archive)", systemImage: "building.columns")
                    }
                    Link(destination: URL(string: "https://books.apple.com")!) {
                        Label("Apple Books", systemImage: "books.vertical")
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
                    if CommunityService.isEnabled {
                        Link(destination: URL(string: "https://mapile.pages.dev/regles")!) {
                            Label("Règles de la communauté", systemImage: "person.3")
                        }
                    }
                    Link(destination: Self.siteURL) {
                        Label("Assistance et contact", systemImage: "questionmark.circle")
                    }
                }
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK", systemImage: "checkmark") { dismiss() }
                }
            }
        }
    }
}
