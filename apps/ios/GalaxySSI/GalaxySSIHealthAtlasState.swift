import SwiftUI

@MainActor
final class GalaxySSIHealthAtlasState: ObservableObject {
  enum Tab: String, CaseIterable, Codable { case structure, function, values, simulation }
  enum Research: String, CaseIterable, Codable { case physiology, drugs, aging }
  enum StructureLayer: String, CaseIterable { case organ, tissue, cell }
  struct Selection: Codable, Equatable {
    var tab = Tab.structure
    var research = Research.physiology
    var simulation = GalaxySSIHealthAtlasSimulation()
    var physiologyInputs: [Int]?
    var elimination = GalaxySSIHealthAtlasElimination()
    var drugInputs: [Int]?
    var metric: GalaxySSIHealthMetric?
    var window = GalaxySSIHealthAtlasWindow.month
    var layers = true
    var zoom: Double = 1
    var artworkView: String?
    var aging: GalaxySSIHealthAtlasAgingSelection?
    var structureLayer: String?
    var functionSelection: GalaxySSIHealthAtlasFunctionSelection?
    var revealTrend: Bool?
    var modelsExpanded: Bool?
    var researchPresented: Bool?
    var researchReturnScroll: Double?
    var selectedStructureLayer: StructureLayer {
      get { StructureLayer(rawValue: structureLayer ?? "") ?? .organ }
      set { structureLayer = newValue.rawValue }
    }
  }
  @Published var entries: [String: Selection] = [:]
  @Published var previewPresented = false
  @Published var wholeFocus = "heart"
  let playback = GalaxySSIHealthAtlasPlayback()
  private var liveFunctionPhases: [String: [String: Double]] = [:]

  func recordFunctionPhase(entryID: String, storyID: String, phase: Double) {
    guard let catalogue = try? GalaxySSIHealthAtlasFunctionCatalogue.bundled.get(),
      catalogue.routes[entryID]?.contains(storyID) == true else { return }
    liveFunctionPhases[entryID, default: [:]][storyID] = GalaxySSIHealthAtlasFunctionCatalogue.Story.safePhase(phase)
  }
  func functionSnapshot(_ entry: GalaxySSIHealthAtlas.Entry) -> Selection {
    var value = binding(entry).wrappedValue
    guard let phases = liveFunctionPhases[entry.id], !phases.isEmpty,
      let catalogue = try? GalaxySSIHealthAtlasFunctionCatalogue.bundled.get() else { return value }
    var function = value.functionSelection ?? .init()
    for (storyID, phase) in phases { function.save(phase, storyID: storyID, entryID: entry.id, catalogue: catalogue) }
    value.functionSelection = function
    return value
  }

  func openNumericalModel(_ entry: GalaxySSIHealthAtlas.Entry) {
    var next = functionSnapshot(entry)
    if Self.usesInlineModels(entry) { next.tab = .function; next.modelsExpanded = true }
    else { next.tab = .simulation }
    entries[entry.id] = next
  }
  static func researchTopics(_ entry: GalaxySSIHealthAtlas.Entry) -> [Research] {
    usesInlineModels(entry) ? [.drugs, .aging] : Research.allCases
  }
  func openResearch(_ entry: GalaxySSIHealthAtlas.Entry, returnScroll: Double) {
    playback.pause()
    var next = functionSnapshot(entry)
    next.research = Self.usesInlineModels(entry) ? .drugs : .physiology
    next.researchReturnScroll = Self.safeScroll(returnScroll)
    next.researchPresented = true
    entries[entry.id] = next
  }
  func closeResearch(_ entry: GalaxySSIHealthAtlas.Entry) {
    playback.pause()
    var next = binding(entry).wrappedValue
    next.researchPresented = false
    entries[entry.id] = next
  }
  static func safeScroll(_ value: Double) -> Double { value.isFinite ? min(1_000_000, max(0, value)) : 0 }

  func wholeEntry(in atlas: GalaxySSIHealthAtlas) -> GalaxySSIHealthAtlas.Entry? {
    atlas.entry(wholeFocus) ?? atlas.entry("heart")
  }

  func rememberWholeSelection(_ id: String, in atlas: GalaxySSIHealthAtlas) {
    guard atlas.entry(id) != nil else { return }
    wholeFocus = id
  }

  func openWholeBody(_ entry: GalaxySSIHealthAtlas.Entry, tab: Tab, showTrend: Bool = false) {
    wholeFocus = entry.id
    var next = binding(entry).wrappedValue
    next.tab = tab
    next.revealTrend = showTrend && tab == .values && !GalaxySSIHealthAtlasMetrics.forEntry(entry.id).isEmpty
    entries[entry.id] = next
  }

  func binding(_ entry: GalaxySSIHealthAtlas.Entry) -> Binding<Selection> {
    Binding(get: { Self.migrated(self.entries[entry.id] ?? Selection(simulation: .initial(entry.id)), entry: entry) },
      set: { self.entries[entry.id] = Self.migrated($0, entry: entry) })
  }
  static func usesInlineModels(_ entry: GalaxySSIHealthAtlas.Entry) -> Bool { entry.kind == .system || entry.kind == .organ }
  static func migrated(_ selection: Selection, entry: GalaxySSIHealthAtlas.Entry) -> Selection {
    var next = selection
    if usesInlineModels(entry), next.tab == .simulation { next.tab = .function; next.modelsExpanded = true }
    if let offset = next.researchReturnScroll { next.researchReturnScroll = safeScroll(offset) }
    if usesInlineModels(entry), next.researchPresented == true, next.research == .physiology {
      next.tab = .function; next.modelsExpanded = true
      next.researchPresented = false; next.research = .drugs
    }
    return next
  }
  func restore(_ text: String, atlas: GalaxySSIHealthAtlas) {
    guard text.utf8.count <= 256_000, let data = text.data(using: .utf8),
      let decoded = try? JSONDecoder().decode([String: Selection].self, from: data), decoded.count <= max(300, atlas.entries.count) else { return }
    entries = decoded.filter { atlas.entry($0.key) != nil }.mapValues { $0 }
    liveFunctionPhases = [:]
    let functionCatalogue: GalaxySSIHealthAtlasFunctionCatalogue?
    if decoded.values.contains(where: { $0.functionSelection != nil }) {
      functionCatalogue = try? GalaxySSIHealthAtlasFunctionCatalogue.bundled.get()
    } else { functionCatalogue = nil }
    for id in Array(entries.keys) {
      if let entry = atlas.entry(id), let saved = entries[id] { entries[id] = Self.migrated(saved, entry: entry) }
      if let functionCatalogue { entries[id]?.functionSelection?.sanitize(entryID: id, catalogue: functionCatalogue) }
      else { entries[id]?.functionSelection = nil }
      if atlas.entry(id)?.kind != .organ || StructureLayer(rawValue: entries[id]?.structureLayer ?? "") == nil {
        entries[id]?.structureLayer = nil
      }
      if let view = entries[id]?.artworkView, !atlas.views(for: id).contains(where: { $0.viewKey == view }) {
        entries[id]?.artworkView = nil
      }
      entries[id]?.simulation.sanitize(id)
      #if GALAXYSSI_ATLAS_PHYSIOLOGY
      let restored = GalaxySSIHealthAtlasPhysiology.restore(id, inputs: entries[id]?.physiologyInputs)?.inputs
      entries[id]?.physiologyInputs = restored
      #endif
      entries[id]?.elimination.sanitize()
      if let aging = entries[id]?.aging { entries[id]?.aging = .resolved(aging, entryID: id) }
      entries[id]?.drugInputs = GalaxySSIHealthAtlasDrugState.restore(entries[id]?.drugInputs)?.encoded
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
  @SceneStorage("galaxyssi.health.atlas.whole-focus.v1") private var savedWholeFocus = "heart"
  @State private var atlas: GalaxySSIHealthAtlas?
  @SceneStorage("galaxyssi.health.atlas.query.v1") private var query = ""
  @SceneStorage("galaxyssi.health.atlas.kind.v1") private var kind = "whole"
  @SceneStorage("galaxyssi.health.atlas.system.v1") private var system = ""
  @SceneStorage("galaxyssi.health.atlas.tissue-catalogue.v1") private var showTissues = false
  @State private var limit = 24
  @State private var quickTarget: String?

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
            if let focus = state.wholeEntry(in: atlas) {
              GalaxySSIHealthAtlasWholeBodyActions(atlas: atlas, entry: focus, language: language) { tab, trend in
                state.openWholeBody(focus, tab: tab, showTrend: trend)
                quickTarget = focus.id
              }
            }
            Text(String(format: t("counts"), Int64(atlas.entries.filter { $0.kind == .system }.count),
              Int64(atlas.entries.filter { $0.kind == .organ }.count), Int64(atlas.entries.filter { $0.kind == .tissue }.count),
              Int64(atlas.entries.filter { $0.kind == .cell }.count)))
              .font(.subheadline).foregroundColor(.secondary)
            Text(t("category_note")).font(.footnote).foregroundColor(.secondary)
            NavigationLink(GalaxySSIHealthBodyText.string("entry", language: language)) {
              GalaxySSIHealthBodyView {
                GalaxySSIHealthTrendView(records: records, fixedMetric: .bloodPressure)
              }
            }
          } else {
            if kind == "organ" {
              Picker(t("organs"), selection: $showTissues) {
                Text(t("organs")).tag(false)
                Text(t("tissues")).tag(true)
              }.pickerStyle(.segmented).accessibilityIdentifier("atlas-catalogue-layer")
            }
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
            let matches = atlas.search(query, kind: kind == "organ" && showTissues ? .tissue : GalaxySSIHealthAtlas.Kind(rawValue: kind),
              system: system, language: language)
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
      if let atlas {
        GalaxySSIHealthAtlasAsk(atlas: atlas, entry: kind == "whole" ? state.wholeEntry(in: atlas) : nil,
          selection: .init()).padding(.horizontal)
      }
    }
    .background(NavigationLink(isActive: Binding(get: { quickTarget != nil }, set: { if !$0 { quickTarget = nil } })) {
      if let atlas, let quickTarget, let entry = atlas.entry(quickTarget) {
        GalaxySSIHealthAtlasDetail(atlas: atlas, entry: entry, state: state, records: records, depth: 1)
      }
    } label: { EmptyView() }.hidden())
    .galaxySSIHealthTheme()
    .onAppear { if atlas == nil { load() } }
    .onChange(of: state.serialized) { saved = $0 }
    .onChange(of: state.wholeFocus) { savedWholeFocus = $0 }
    .onChange(of: kind) { _ in system = ""; limit = 24 }
    .onChange(of: system) { _ in limit = 24 }
    .onChange(of: showTissues) { _ in limit = 24 }
  }

  private func link(_ entry: GalaxySSIHealthAtlas.Entry, atlas: GalaxySSIHealthAtlas) -> some View {
    NavigationLink(destination: GalaxySSIHealthAtlasDetail(atlas: atlas, entry: entry, state: state, records: records, depth: 1)) {
      GalaxySSIHealthAtlasRow(entry: entry)
    }
  }
  private func load() {
    do {
      let content = try GalaxySSIHealthAtlas.load()
      if !["whole", "system", "organ", "cell"].contains(kind) { kind = "whole" }
      if !system.isEmpty, content.entry(system)?.kind != .system { system = "" }
      query = String(query.prefix(100))
      state.restore(saved, atlas: content)
      state.wholeFocus = content.entry(savedWholeFocus)?.id ?? "heart"
      atlas = content
    }
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
