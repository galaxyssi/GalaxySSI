import SwiftUI

enum GalaxySSIHealthCatalogAnchor {
  static func restoration<ID: Equatable>(visible: [ID], updated: [ID], limit: Int) -> (id: ID, limit: Int)? {
    for id in visible {
      if let index = updated.firstIndex(of: id) { return (id, max(limit, index + 1)) }
    }
    return nil
  }
}

private struct GalaxySSIHealthRowPositions: PreferenceKey {
  static var defaultValue: [UUID: CGRect] { [:] }

  static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
    value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
  }
}

@MainActor
struct GalaxySSIHealthMetricCatalogView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scene
  let records: GalaxySSIHealthRecords
  let add: (GalaxySSIHealthMetric) -> Void
  let edit: (GalaxySSIHealthReading) -> Void
  @State private var query = ""
  @State private var mode = Mode.daily

  private enum Mode { case daily, laboratory, all }

  var body: some View {
    List {
      if scene == .active {
        Picker(t("category", "Category"), selection: $mode) {
          Text(t("daily", "Daily")).tag(Mode.daily)
          Text(t("laboratory", "Laboratory")).tag(Mode.laboratory)
          Text(t("all", "All")).tag(Mode.all)
        }
        .pickerStyle(.segmented)
        let matches = GalaxySSIHealthMetric.allCases.filter { metric in
          (mode == .all || (mode == .laboratory ? metric.laboratory : !metric.laboratory || metric == .glucose)) &&
            metric.matches(query)
        }
        if matches.isEmpty { Text(t("no_matches", "No matching measurements")).foregroundColor(.secondary) }
        ForEach(GalaxySSIHealthMetric.Group.allCases, id: \.self) { group in
          let metrics = matches.filter { $0.entry.group == group }
          if !metrics.isEmpty {
            Section(group.title(language: language)) {
              ForEach(metrics) { metric in
                NavigationLink {
                  MetricReadings(records: records, metric: metric, add: add, edit: edit)
                } label: {
                  VStack(alignment: .leading, spacing: 4) {
                    Text(metric.title(language: language))
                    Text(metric.unit.isEmpty ? t("qualitative", "Qualitative") : metric.units.joined(separator: " / "))
                      .font(.footnote).foregroundColor(.secondary)
                  }
                }
              }
            }
          }
        }
      }
    }
    .searchable(text: $query, prompt: t("search", "Search measurements"))
    .navigationTitle(t("title", "Measurement Catalog"))
    .navigationBarTitleDisplayMode(.inline)
    .onChange(of: scene) {
      if $0 == .background { query = ""; mode = .daily }
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.catalog." + key, fallback: fallback, language: language)
  }

  @MainActor
  private struct MetricReadings: View {
    @Environment(\.galaxySSIInterfaceLanguage) private var language
    @Environment(\.scenePhase) private var scene
    @Environment(\.locale) private var locale
    let records: GalaxySSIHealthRecords
    let metric: GalaxySSIHealthMetric
    let add: (GalaxySSIHealthMetric) -> Void
    let edit: (GalaxySSIHealthReading) -> Void
    @State private var current: [GalaxySSIHealthReading]?
    @State private var hasDraft = false
    @State private var limit = 30
    @State private var visible: [UUID] = []
    @State private var restoreID: UUID?
    @State private var refresh = 0

    var body: some View {
      GeometryReader { geometry in
        ScrollViewReader { proxy in
          List {
            if scene == .active, let current {
              NavigationLink {
                GalaxySSIHealthTrendView(records: records, fixedMetric: metric, recordMeasurement: add)
              } label: {
                Label(t("trend", "Measurement trends"), systemImage: "chart.xyaxis.line")
              }
              Button { add(metric) } label: {
                Label(hasDraft ? t("resume", "Resume draft") : t("record", "Record measurement"),
                      systemImage: hasDraft ? "doc.text" : "plus.circle")
              }
              if current.isEmpty { Text(t("empty", "No confirmed readings")).foregroundColor(.secondary) }
              ForEach(current.prefix(limit)) { reading in
                Button { edit(reading) } label: {
                  VStack(alignment: .leading, spacing: 4) {
                    Text(summary(reading)).foregroundColor(.primary)
                    if let reference = reading.referenceInterval, !reference.isEmpty {
                      Text(reference).font(.footnote).foregroundColor(.secondary)
                    }
                    Text(reading.measuredAt.formatted(date: .abbreviated, time: .shortened))
                      .foregroundColor(.secondary)
                  }
                }
                .disabled(hasDraft)
                .id(reading.id)
                .background(GeometryReader { row in
                  Color.clear.preference(key: GalaxySSIHealthRowPositions.self,
                    value: [reading.id: row.frame(in: .named("health-catalog-records"))])
                })
              }
              if current.count > limit { Button(t("more", "Show more")) { limit += 30 } }
            } else if scene == .active {
              Button(t("reload", "Reload measurements"), action: reload)
            }
          }
          .coordinateSpace(name: "health-catalog-records")
          .onPreferenceChange(GalaxySSIHealthRowPositions.self) { frames in
            guard scene == .active, !frames.isEmpty else { return }
            visible = frames.filter { $0.value.maxY > 0 && $0.value.minY < geometry.size.height }
              .sorted { $0.value.minY < $1.value.minY }.map(\.key)
          }
          .onChange(of: refresh) { _ in
            if let restoreID {
              proxy.scrollTo(restoreID, anchor: .top)
              self.restoreID = nil
            }
          }
        }
      }
      .navigationTitle(metric.title(language: language))
      .navigationBarTitleDisplayMode(.inline)
      .onAppear(perform: reload)
      .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.trendInputsChanged)) {
        if $0.object as? String == records.owner { reload() }
      }
      .onChange(of: scene) {
        if $0 == .active { reload() }
        else if $0 == .background {
          current = nil; hasDraft = false; limit = 30; visible = []; restoreID = nil
        }
      }
    }

    private func reload() {
      guard scene == .active else { return }
      do {
        let archive = try records.load()
        let next = archive.current.filter { $0.metric == metric }
        if let current, current.prefix(limit).map(\.id) != next.prefix(limit).map(\.id),
           let anchor = GalaxySSIHealthCatalogAnchor.restoration(visible: visible, updated: next.map(\.id), limit: limit) {
          limit = anchor.limit
          restoreID = anchor.id
          refresh += 1
        }
        current = next
        hasDraft = archive.draft != nil
      } catch { current = nil; hasDraft = false }
    }

    private func summary(_ reading: GalaxySSIHealthReading) -> String {
      let value = reading.reported?.raw ?? reading.value?.formatted(.number.locale(locale)) ?? ""
      let lower = reading.diastolic.map { "/" + $0.formatted(.number.locale(locale)) } ?? ""
      return value + lower + (reading.unit.isEmpty ? "" : " " + reading.unit)
    }

    private func t(_ key: String, _ fallback: String) -> String {
      GalaxySSILocalization.string("galaxyssi.health.catalog." + key, fallback: fallback, language: language)
    }
  }
}
