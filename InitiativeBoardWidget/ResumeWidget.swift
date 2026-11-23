import SwiftUI
import WidgetKit

private struct ResumeEntry: TimelineEntry {
    var date = Date()
    var snapshot: WidgetSnapshot?
}

private struct ResumeProvider: TimelineProvider {
    func placeholder(in context: Context) -> ResumeEntry {
        ResumeEntry(snapshot: WidgetSnapshot(id: UUID(), round: 2, current: nil, next: nil))
    }
    func getSnapshot(in context: Context, completion: @escaping (ResumeEntry) -> Void) {
        completion(ResumeEntry(snapshot: WidgetSnapshot.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ResumeEntry>) -> Void) {
        let entry = ResumeEntry(snapshot: WidgetSnapshot.load())
        completion(Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(60 * 30))))
    }
}

private struct ResumeView: View {
    let entry: ResumeEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if family == .accessoryCircular {
                VStack {
                    Image(systemName: "list.number")
                    if let round = entry.snapshot?.round { Text(round, format: .number) }
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Label(L.t("widget.open"), systemImage: "list.number").font(.headline)
                    if let snapshot = entry.snapshot {
                        Text(L.f("round", snapshot.round)).font(.subheadline)
                        if let current = snapshot.current {
                            Text(L.f("widget.now", current)).lineLimit(1).privacySensitive()
                        }
                        if let next = snapshot.next {
                            Text(L.f("widget.next", next)).lineLimit(1).privacySensitive()
                        }
                    } else {
                        Text(L.t("widget.empty")).font(.caption)
                    }
                }
            }
        }
        .widgetURL(entry.snapshot?.url ?? URL(string: "initiativeboard://resume"))
        .containerBackground(for: .widget) { Color(red: 0.965, green: 0.961, blue: 0.937) }
    }
}

@main struct ResumeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "InitiativeResume", provider: ResumeProvider()) { ResumeView(entry: $0) }
            .configurationDisplayName(L.t("widget.title"))
            .description(L.t("widget.description"))
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}
