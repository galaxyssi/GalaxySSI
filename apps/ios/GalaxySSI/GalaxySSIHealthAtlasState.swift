import SwiftUI

@MainActor
final class GalaxySSIHealthAtlasState: ObservableObject {
  enum Tab: String, CaseIterable, Codable { case structure, function, values, simulation }
  enum Research: String, CaseIterable, Codable { case physiology, drugs, aging }
  struct Selection: Codable, Equatable {
    var tab = Tab.structure
    var research = Research.physiology
    var simulation = GalaxySSIHealthAtlasSimulation()
    var physiologyInputs: [Int]?
    var elimination = GalaxySSIHealthAtlasElimination()
    var artworkView: String?
    var metric: GalaxySSIHealthMetric?
    var window = GalaxySSIHealthAtlasWindow.month
    var layers = true
    var zoom: Double = 1
  }
  @Published var entries: [String: Selection] = [:]
  @Published var previewPresented = false

  func binding(_ entry: GalaxySSIHealthAtlas.Entry) -> Binding<Selection> {
    Binding(get: { self.entries[entry.id] ?? Selection(simulation: .initial(entry.id)) },
      set: { self.entries[entry.id] = $0 })
  }
  func restore(_ text: String, atlas: GalaxySSIHealthAtlas) {
    guard text.utf8.count <= 256_000, let data = text.data(using: .utf8),
      let decoded = try? JSONDecoder().decode([String: Selection].self, from: data), decoded.count <= 300 else { return }
    entries = decoded.filter { atlas.entry($0.key) != nil }.mapValues { $0 }
    for id in Array(entries.keys) {
      entries[id]?.simulation.sanitize(id)
      #if GALAXYSSI_ATLAS_PHYSIOLOGY
      let restored = GalaxySSIHealthAtlasPhysiology.restore(id, inputs: entries[id]?.physiologyInputs)?.inputs
      entries[id]?.physiologyInputs = restored
      #endif
      entries[id]?.elimination.sanitize()
      if let view = entries[id]?.artworkView, !atlas.views(for: id).contains(where: { $0.viewKey == view }) {
        entries[id]?.artworkView = nil
      }
      if let zoom = entries[id]?.zoom { entries[id]?.zoom = zoom.isFinite ? min(4, max(1, zoom)) : 1 }
      if let metric = entries[id]?.metric, !GalaxySSIHealthAtlasMetrics.forEntry(id).contains(metric) { entries[id]?.metric = nil }
    }
  }
  var serialized: String { (try? JSONEncoder().encode(entries)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}" }
}

@MainActor
struct GalaxySSIHealthAtlasView: View {
  let records: GalaxySSIHealthRecords
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @StateObject private var state = GalaxySSIHealthAtlasState()
  @SceneStorage("galaxyssi.health.atlas.public-selection.v1") private var saved = "{}"
  @State private var atlas: GalaxySSIHealthAtlas?
  @State private var query = ""
  @State private var kind = "whole"
  @State private var system = ""
  @State private var limit = 24

  var body: some View {
    Group {
      if let atlas {
        List {
          Picker(t("whole"), selection: $kind) {
            Text(t("whole")).tag("whole")
            Text(t("systems")).tag("system")
            Text(t("organs")).tag("organ")
            Text(t("cells")).tag("cell")
          }.pickerStyle(.segmented)
          if kind == "whole" {
            GalaxySSIHealthAtlasArtwork(atlas: atlas, entry: nil, state: state, records: records, depth: 0)
            Text(String(format: t("counts"), Int64(atlas.entries.filter { $0.kind == .system }.count),
              Int64(atlas.entries.filter { $0.kind == .organ }.count), Int64(atlas.entries.filter { $0.kind == .cell }.count)))
              .font(.subheadline).foregroundColor(.secondary)
            ForEach(["heart", "cell-pancreatic-beta-cell"], id: \.self) { id in
              if let entry = atlas.entry(id) { link(entry, atlas: atlas) }
            }
            Text(t("category_note")).font(.footnote).foregroundColor(.secondary)
            NavigationLink(GalaxySSIHealthBodyText.string("entry", language: language)) {
              GalaxySSIHealthBodyView {
                GalaxySSIHealthTrendView(records: records, fixedMetric: .bloodPressure)
              }
            }
          } else {
            TextField(t("search"), text: $query)
              .onChange(of: query) { value in
                if value.count > 100 { query = String(value.prefix(100)) }
                limit = 24
              }
            if kind != "system" {
              Picker(t("systems"), selection: $system) {
                Text(t("all")).tag("")
                ForEach(atlas.entries.filter { $0.kind == .system }) { entry in
                  Text(GalaxySSIHealthAtlasText.get(entry.name, language)).tag(entry.id)
                }
              }
            }
            let matches = atlas.search(query, kind: GalaxySSIHealthAtlas.Kind(rawValue: kind), system: system, language: language)
            if matches.isEmpty { Text(t("no_matches")) }
            ForEach(Array(matches.prefix(limit))) { link($0, atlas: atlas) }
            if matches.count > limit { Button(t("more")) { limit += 24 } }
          }
        }
      } else {
        VStack(spacing: 16) {
          Text(t("load_error"))
          Button(t("retry"), action: load)
        }.padding()
      }
    }
    .navigationTitle(t("whole"))
    .navigationBarTitleDisplayMode(.inline)
    .safeAreaInset(edge: .bottom) {
      if let atlas { GalaxySSIHealthAtlasAsk(atlas: atlas, entry: nil, selection: .init()).padding(.horizontal) }
    }
    .galaxySSIHealthTheme()
    .onAppear { if atlas == nil { load() } }
    .onChange(of: state.serialized) { saved = $0 }
    .onChange(of: kind) { _ in system = ""; limit = 24 }
    .onChange(of: system) { _ in limit = 24 }
  }

  private func link(_ entry: GalaxySSIHealthAtlas.Entry, atlas: GalaxySSIHealthAtlas) -> some View {
    NavigationLink(destination: GalaxySSIHealthAtlasDetail(atlas: atlas, entry: entry, state: state, records: records, depth: 1)) {
      GalaxySSIHealthAtlasRow(entry: entry)
    }
  }
  private func load() {
    do { let content = try GalaxySSIHealthAtlas.load(); state.restore(saved, atlas: content); atlas = content }
    catch { atlas = nil }
  }
  private func t(_ key: String) -> String { GalaxySSIHealthAtlasText.get("health_atlas_" + key, language) }
}

struct GalaxySSIHealthAtlasRow: View {
  let entry: GalaxySSIHealthAtlas.Entry
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: symbol).font(.title3).frame(width: 32, height: 44)
        .foregroundColor(Color(red: red, green: green, blue: blue)).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(GalaxySSIHealthAtlasText.get(entry.name, language))
        Text(GalaxySSIHealthAtlasText.get(entry.description, language)).font(.caption).foregroundColor(.secondary).lineLimit(2)
      }
    }.padding(.vertical, 4)
  }
  private var rgb: UInt64 { UInt64(entry.color.dropFirst(), radix: 16) ?? 0x17866C }
  private var red: Double { Double((rgb >> 16) & 255) / 255 }
  private var green: Double { Double((rgb >> 8) & 255) / 255 }
  private var blue: Double { Double(rgb & 255) / 255 }
  private var symbol: String {
    switch entry.icon {
    case "brain": return "brain.head.profile"
    case "eye": return "eye"
    case "heart-pulse": return "heart"
    case "wind": return "wind"
    case "bone": return "figure.walk"
    case "shield-plus": return "cross.case"
    case "microscope": return "circle.hexagongrid"
    default: return entry.kind == .cell || entry.kind == .fragment ? "circle.hexagongrid" : "square.stack.3d.up"
    }
  }
}
