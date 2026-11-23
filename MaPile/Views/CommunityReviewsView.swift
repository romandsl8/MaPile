import SwiftUI

/// Carte « Les avis MaPile » : notes et avis publiés anonymement par les utilisateurs de MaPile.
struct CommunityReviewsCard: View {
    @Bindable var book: Book

    @AppStorage("communityRulesAccepted") private var rulesAccepted = false
    @State private var reviews: [CommunityService.Review] = []
    @State private var loading = true
    @State private var working = false
    @State private var message: String?
    @State private var showingRules = false
    @State private var showingAll = false
    @State private var reviewToReport: CommunityService.Review?
    @State private var showSpoilers = false

    private var others: [CommunityService.Review] { reviews.filter { !$0.isMine } }
    private var average: Double? {
        guard !reviews.isEmpty else { return nil }
        return Double(reviews.reduce(0) { $0 + $1.rating }) / Double(reviews.count)
    }
    private var isRead: Bool { book.status == .read }

    var body: some View {
        SectionCard(title: "Les avis MaPile", systemImage: "person.3") {
            if loading {
                HStack { ProgressView(); Text("Chargement…").foregroundStyle(.secondary) }
            } else if let average {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(average.frenchDecimal)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    VStack(alignment: .leading, spacing: 3) {
                        StarRatingDisplay(rating: average, size: 14)
                        Text(reviews.count > 1 ? "\(reviews.count) lecteurs MaPile" : "1 lecteur MaPile")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(isRead ? "Soyez le premier lecteur MaPile à partager une note sur ce livre."
                            : "Aucun lecteur MaPile n'a encore noté ce livre.")
                    .foregroundStyle(.secondary)
            }

            if isRead {
                reviewList
                shareControls
            } else if reviews.contains(where: { !$0.text.isEmpty }) {
                if showSpoilers {
                    reviewList
                } else {
                    Text("Les commentaires sont masqués tant que vous n'avez pas lu le livre : ils peuvent dévoiler l'intrigue.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        withAnimation { showSpoilers = true }
                    } label: {
                        Label("Afficher les commentaires", systemImage: "eye")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
            }

            Text("Avis anonymes des utilisateurs de MaPile.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .task(id: book.sharedReviewAt) { await load() }
        .sheet(isPresented: $showingRules) {
            CommunityRulesSheet {
                rulesAccepted = true
                Task { await share() }
            }
        }
        .sheet(isPresented: $showingAll) {
            AllCommunityReviewsView(reviews: reviews, bookTitle: book.title) { review in
                reviewToReport = review
            }
        }
        .confirmationDialog("Signaler cet avis", isPresented: Binding(get: { reviewToReport != nil },
                                                                     set: { if !$0 { reviewToReport = nil } }),
                            titleVisibility: .visible) {
            ForEach(["Insultant ou haineux", "Révèle l'intrigue (spoiler)", "Hors sujet ou publicité", "Autre problème"], id: \.self) { reason in
                Button(reason) { if let review = reviewToReport { Task { await report(review, reason: reason) } } }
            }
            Button("Masquer tous les avis de cet utilisateur", role: .destructive) {
                if let review = reviewToReport {
                    HiddenAuthors.hide(review.authorKey)
                    reviews.removeAll { $0.authorKey == review.authorKey && !$0.isMine }
                }
            }
        } message: {
            Text("L'avis sera examiné par l'éditeur de MaPile.")
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var reviewList: some View {
        let withText = reviews.filter { !$0.text.isEmpty }
        if !withText.isEmpty {
            ForEach(withText.prefix(3)) { review in
                CommunityReviewRow(review: review) { reviewToReport = review }
                if review.id != withText.prefix(3).last?.id { Divider() }
            }
            if withText.count > 3 {
                Button {
                    showingAll = true
                } label: {
                    Label("Voir les \(withText.count) avis", systemImage: "chevron.right")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var shareControls: some View {
        if book.sharedReviewAt != nil {
            HStack(spacing: 8) {
                Label("Votre avis est partagé", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
                Spacer()
                Button("Mettre à jour") { Task { await share() } }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                Button("Retirer", role: .destructive) { Task { await unshare() } }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
            .disabled(working)
        } else {
            Button {
                if rulesAccepted { Task { await share() } } else { showingRules = true }
            } label: {
                if working {
                    ProgressView()
                } else {
                    Label("Partager ma note et mon avis", systemImage: "square.and.arrow.up")
                }
            }
            .buttonStyle(.glassProminent)
            .controlSize(.small)
            .disabled(working || book.myRating == 0)
            if book.myRating == 0 {
                Text("Notez d'abord le livre avec les étoiles de « Mon avis ».")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        reviews = (try? await CommunityService.reviews(for: book)) ?? []
    }

    private func share() async {
        working = true
        defer { working = false }
        do {
            try await CommunityService.publish(book: book)
            message = "Merci ! Votre note et votre avis sont partagés anonymement avec les lecteurs MaPile."
        } catch {
            message = error.localizedDescription
        }
    }

    private func unshare() async {
        working = true
        defer { working = false }
        do {
            try await CommunityService.unpublish(book: book)
            message = "Votre avis a été retiré des avis MaPile."
        } catch {
            message = error.localizedDescription
        }
    }

    private func report(_ review: CommunityService.Review, reason: String) async {
        do {
            try await CommunityService.report(review, reason: reason)
            message = "Merci, l'avis a été signalé."
        } catch {
            message = error.localizedDescription
        }
    }
}

struct CommunityReviewRow: View {
    let review: CommunityService.Review
    var onReport: () -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                StarRatingDisplay(rating: Double(review.rating), size: 11)
                if review.isMine {
                    Text("Vous")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15), in: .capsule)
                }
                Spacer()
                if !review.isMine {
                    Menu {
                        Button("Signaler ou masquer", systemImage: "flag") { onReport() }
                    } label: {
                        Label("Options", systemImage: "ellipsis")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 22)
                    }
                }
            }
            if !review.text.isEmpty {
                Text(review.text)
                    .font(.subheadline)
                    .lineLimit(expanded ? nil : 5)
                    .onTapGesture { withAnimation(.smooth) { expanded.toggle() } }
            }
            Text("Un lecteur MaPile · \(review.date.formatted(.dateTime.day().month(.abbreviated).year()))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AllCommunityReviewsView: View {
    let reviews: [CommunityService.Review]
    let bookTitle: String
    var onReport: (CommunityService.Review) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(reviews.filter { !$0.text.isEmpty }) { review in
                CommunityReviewRow(review: review) {
                    dismiss()
                    onReport(review)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle(bookTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK", systemImage: "checkmark") { dismiss() }
                }
            }
        }
    }
}

/// Règles de la communauté, à accepter avant le premier partage.
struct CommunityRulesSheet: View {
    var onAccept: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Avant de partager")
                        .font(.system(.title2, design: .serif).weight(.bold))
                    rule("eye.slash", "Votre avis est publié anonymement : ni nom, ni e-mail, ni pseudo ne sont affichés.")
                    rule("hand.raised", "Restez respectueux : pas d'insultes, de propos haineux, de harcèlement ni de contenu choquant. Aucune tolérance.")
                    rule("text.badge.xmark", "Pas de publicité, de liens ni de coordonnées.")
                    rule("theatermasks", "Évitez de dévoiler la fin du livre.")
                    rule("flag", "Les avis signalés sont examinés et peuvent être supprimés ; les auteurs d'abus peuvent être exclus.")
                    rule("trash", "Vous pouvez retirer votre avis à tout moment depuis la fiche du livre.")
                    Link("Lire les règles complètes", destination: URL(string: "https://mapile.pages.dev/regles")!)
                        .font(.subheadline)
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    dismiss()
                    onAccept()
                } label: {
                    Text("J'accepte et je partage").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func rule(_ icon: String, _ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: icon).foregroundStyle(Color.accentColor)
        }
    }
}
