import SwiftUI
import WidgetKit

/// Watch-face complication that opens the Tesla Key screen with one tap, so you
/// can raise your wrist and unlock without first launching the app.
@main
struct EEAccessComplicationBundle: WidgetBundle {
    var body: some Widget {
        TeslaKeyComplication()
    }
}

struct TeslaKeyComplication: Widget {
    var body: some WidgetConfiguration {
        // `kind` is a stable identifier — keep it as "CarKeyComplication" so
        // complications already placed on a watch face survive this rename.
        StaticConfiguration(kind: "CarKeyComplication", provider: TeslaKeyProvider()) { _ in
            TeslaKeyComplicationView()
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "eeaccess://car"))
        }
        .configurationDisplayName("Tesla Key")
        .description("Open your Tesla Key from the watch face.")
        .supportedFamilies([.accessoryCircular, .accessoryInline, .accessoryRectangular])
    }
}

struct TeslaKeyEntry: TimelineEntry {
    let date: Date
}

struct TeslaKeyProvider: TimelineProvider {
    func placeholder(in _: Context) -> TeslaKeyEntry {
        TeslaKeyEntry(date: Date())
    }

    func getSnapshot(in _: Context, completion: @escaping (TeslaKeyEntry) -> Void) {
        completion(TeslaKeyEntry(date: Date()))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<TeslaKeyEntry>) -> Void) {
        completion(Timeline(entries: [TeslaKeyEntry(date: Date())], policy: .never))
    }
}

struct TeslaKeyComplicationView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("Tesla Key", systemImage: "key.radiowaves.forward.fill")
        case .accessoryRectangular:
            HStack(spacing: 6) {
                Image(systemName: "key.radiowaves.forward.fill")
                Text("Tesla Key")
            }
        default:
            Image(systemName: "key.radiowaves.forward.fill")
                .font(.title3)
        }
    }
}
