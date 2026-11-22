import WidgetKit
import SwiftUI
import ActivityKit

@main
struct MaPileWidgetBundle: WidgetBundle {
    var body: some Widget {
        ReadingWidget()
        GoalWidget()
        ReadingLiveActivity()
    }
}

// MARK: - Données

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .example)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let snapshot = context.isPreview ? WidgetSnapshot.example : WidgetSnapshot.load()
        completion(SnapshotEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: WidgetSnapshot.load())
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

private let brandGradient = LinearGradient(
    colors: [Color(red: 0.95, green: 0.55, blue: 0.34), Color(red: 0.59, green: 0.2, blue: 0.36)],
    startPoint: .topLeading, endPoint: .bottomTrailing)

private struct WidgetCover: View {
    let data: Data?
    let title: String

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.white.opacity(0.2)
                    Text(title)
                        .font(.system(size: 9, weight: .semibold, design: .serif))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(3)
                }
            }
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 5))
    }
}

// MARK: - Widget « Lecture en cours »

struct ReadingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ReadingWidget", provider: SnapshotProvider()) { entry in
            ReadingWidgetView(entry: entry)
                .containerBackground(for: .widget) { brandGradient }
        }
        .configurationDisplayName("Lecture en cours")
        .description("Votre livre du moment, la page atteinte et votre série de lecture.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct ReadingWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var book: WidgetSnapshot.ReadingBook? { entry.snapshot.reading.first }

    var body: some View {
        switch family {
        case .accessoryCircular:
            if let progress = book?.progress {
                Gauge(value: progress) { Image(systemName: "book") } currentValueLabel: {
                    Text("\(Int(progress * 100))")
                }
                .gaugeStyle(.accessoryCircularCapacity)
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "book")
                }
            }
        case .accessoryInline:
            if let book {
                Text("📖 \(book.title) · p. \(book.page)")
            } else {
                Text("📖 Aucune lecture en cours")
            }
        case .accessoryRectangular:
            if let book {
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title).font(.headline).lineLimit(1)
                    if let progress = book.progress {
                        ProgressView(value: progress)
                        Text("Page \(book.page)/\(book.pageCount) · \(Int(progress * 100)) %").font(.caption2)
                    } else {
                        Text("Page \(book.page)").font(.caption2)
                    }
                }
            } else {
                Text("Aucune lecture en cours").font(.caption)
            }
        case .systemMedium:
            medium
        default:
            small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let book {
                HStack(alignment: .top) {
                    WidgetCover(data: book.cover, title: book.title).frame(height: 62)
                    Spacer()
                    if entry.snapshot.streak > 0 {
                        Text("🔥\(entry.snapshot.streak)").font(.caption.weight(.bold)).foregroundStyle(.white)
                    }
                }
                Spacer(minLength: 0)
                Text(book.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let progress = book.progress {
                    ProgressView(value: progress).tint(.white)
                    Text("\(Int(progress * 100)) % · p. \(book.page)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.85))
                }
            } else {
                Text("📚").font(.largeTitle)
                Text("Aucune lecture en cours")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
    }

    private var medium: some View {
        HStack(spacing: 14) {
            if let book {
                WidgetCover(data: book.cover, title: book.title).frame(height: 120)
                VStack(alignment: .leading, spacing: 6) {
                    Text("En cours")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                    Text(book.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(book.author)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let progress = book.progress {
                        ProgressView(value: progress).tint(.white)
                        Text("Page \(book.page) sur \(book.pageCount) · \(Int(progress * 100)) %")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    if entry.snapshot.streak > 0 {
                        Text("🔥 \(entry.snapshot.streak) jours d'affilée")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
            } else {
                Text("📚").font(.system(size: 44))
                Text("Aucune lecture en cours.\nChoisissez un livre dans votre PAL !")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Widget « Objectif annuel »

struct GoalWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GoalWidget", provider: SnapshotProvider()) { entry in
            GoalWidgetView(entry: entry)
                .containerBackground(for: .widget) { brandGradient }
        }
        .configurationDisplayName("Objectif de lecture")
        .description("Votre progression vers l'objectif de l'année.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct GoalWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var fraction: Double {
        min(Double(entry.snapshot.yearCount) / Double(max(entry.snapshot.goal, 1)), 1)
    }

    var body: some View {
        if family == .accessoryCircular {
            Gauge(value: fraction) { Text("📚") } currentValueLabel: { Text("\(entry.snapshot.yearCount)") }
                .gaugeStyle(.accessoryCircularCapacity)
        } else {
            VStack(spacing: 8) {
                ZStack {
                    Circle().stroke(.white.opacity(0.25), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(.white, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(entry.snapshot.yearCount)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("sur \(entry.snapshot.goal)").font(.caption2)
                    }
                    .foregroundStyle(.white)
                }
                .frame(width: 92, height: 92)
                Text("Objectif \(String(Calendar.current.component(.year, from: entry.date)))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Live Activity de la séance de lecture

struct ReadingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReadingActivityAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: "book.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.bookTitle)
                        .font(.headline)
                        .lineLimit(1)
                    Text(context.state.pageCount > 0
                         ? "Commencé page \(context.state.page) sur \(context.state.pageCount)"
                         : "Commencé page \(context.state.page)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(timerInterval: context.state.startDate...Date.distantFuture, countsDown: false)
                    .font(.system(.title2, design: .rounded).weight(.semibold).monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
            }
            .padding(16)
            .activityBackgroundTint(Color.black.opacity(0.55))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Lecture", systemImage: "book.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.state.startDate...Date.distantFuture, countsDown: false)
                        .font(.system(.body, design: .rounded).weight(.semibold).monospacedDigit())
                        .frame(width: 70)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.bookTitle)
                        .font(.headline)
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "book.fill").foregroundStyle(.orange)
            } compactTrailing: {
                Text(timerInterval: context.state.startDate...Date.distantFuture, countsDown: false)
                    .monospacedDigit()
                    .frame(width: 44)
            } minimal: {
                Image(systemName: "book.fill").foregroundStyle(.orange)
            }
        }
    }
}
