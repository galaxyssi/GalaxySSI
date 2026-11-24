import SwiftUI

@MainActor
struct GalaxySSIHealthAtlasDetail: View {
  let atlas: GalaxySSIHealthAtlas
  let entry: GalaxySSIHealthAtlas.Entry
  @ObservedObject var state: GalaxySSIHealthAtlasState
  let records: GalaxySSIHealthRecords
  let depth: Int
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @State private var research = false

  private var selection: Binding<GalaxySSIHealthAtlasState.Selection> { state.binding(entry) }
  private var functionCatalogue: GalaxySSIHealthAtlasFunctionCatalogue? { try? GalaxySSIHealthAtlasFunctionCatalogue.bundled.get() }
  private var hasFunctionPlayer: Bool {
    functionCatalogue?.choices(for: entry.id).contains { GalaxySSIHealthAtlasFunctionRendering.implemented.contains($0.id) } == true
  }
  private var showFunctionStructurePreview: Bool {
    guard hasFunctionPlayer, let catalogue = functionCatalogue else { return false }
    let alternate = entry.kind == .system && atlas.views(for: entry.id).count > 1
    let plate = atlas.plate(for: entry.id)
    let labels = plate.map { !$0.markers.isEmpty || !$0.annotations.isEmpty } ?? false
    return alternate || (labels && catalogue.choices(for: entry.id).contains { $0.showStructurePreview })
  }
  private var functionSelection: Binding<GalaxySSIHealthAtlasFunctionSelection> {
    Binding(get: { selection.wrappedValue.functionSelection ?? .init() }, set: { selection.wrappedValue.functionSelection = $0 })
  }
  var body: some View {
    VStack(spacing: 0) {
      Picker(name, selection: selection.tab) {
        ForEach(GalaxySSIHealthAtlasState.Tab.allCases, id: \.self) { Text(t($0.rawValue)).tag($0) }
      }.pickerStyle(.segmented).padding()
      if selection.wrappedValue.tab == .values {
        GalaxySSIHealthAtlasValues(entry: entry, records: records, selection: selection)
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            if selection.wrappedValue.tab == .function, hasFunctionPlayer, let catalogue = functionCatalogue {
              GalaxySSIHealthAtlasFunctionPanel(catalogue: catalogue, entryID: entry.id, language: language,
                previewPresented: state.previewPresented, selection: functionSelection,
                onPhase: { state.recordFunctionPhase(entryID: entry.id, storyID: $0, phase: $1) })
              if let story = functionSelection.wrappedValue.current(entryID: entry.id, catalogue: catalogue) {
                ForEach(Array(story.related.enumerated()), id: \.offset) { _, related in
                  if let target = atlas.entry(related.entryID), let lesson = catalogue.story(related.storyID) {
                    GalaxySSIHealthAtlasFunctionRelatedRow(atlas: atlas, catalogue: catalogue, target: target, story: lesson,
                      state: state, records: records, depth: depth, language: language)
                  }
                }
              }
            }
            if selection.wrappedValue.tab != .structure && !(selection.wrappedValue.tab == .function && hasFunctionPlayer) &&
              (selection.wrappedValue.tab != .simulation ||
                (!GalaxySSIHealthAtlasCirculation.supports(entry.id) && !GalaxySSIHealthAtlasHeartSection.Valve.supports(entry.id) &&
                  entry.id != GalaxySSIHealthAtlasPhagocytosis.owner && GalaxySSIHealthAtlasGranulocyte(rawValue: entry.id) == nil &&
                  GalaxySSIHealthAtlasImmuneLink(rawValue: entry.id) == nil && GalaxySSIHealthAtlasBloodDefense(rawValue: entry.id) == nil &&
                  entry.id != GalaxySSIHealthAtlasSarcomere.owner &&
                  entry.id != GalaxySSIHealthAtlasFiltrationStage.owner && !GalaxySSIHealthAtlasPancreatic.supports(entry.id) &&
                  GalaxySSIHealthAtlasEndocrinePath.forEntry(entry.id) == nil && entry.id != GalaxySSIHealthAtlasRetinaPath.owner &&
                  entry.id != GalaxySSIHealthAtlasSweat.owner && GalaxySSIHealthAtlasSectionLesson.forEntry(entry.id) == nil)) {
              GalaxySSIHealthAtlasArtwork(atlas: atlas, entry: entry, state: state, records: records, depth: depth)
            }
            if selection.wrappedValue.tab != .structure { Text(GalaxySSIHealthAtlasText.get(entry.description, language)) }
            if selection.wrappedValue.tab == .structure {
              structure
            } else if selection.wrappedValue.tab == .function {
              Text(String(format: t("related_process"), GalaxySSIHealthAtlasText.get(atlas.model(entry).title, language))).font(.headline)
              ForEach(Array(atlas.model(entry).stages.enumerated()), id: \.offset) { index, key in
                Text("\(index + 1). " + GalaxySSIHealthAtlasText.get(key, language))
              }
              Text(t("process_note")).font(.footnote).foregroundColor(.secondary)
              if showFunctionStructurePreview {
                GalaxySSIHealthAtlasArtwork(atlas: atlas, entry: entry, state: state, records: records, depth: depth)
              }
              Button(t("simulation")) { selection.wrappedValue.tab = .simulation }
            } else {
              GalaxySSIHealthAtlasSimulationPanel(atlas: atlas, entry: entry, model: atlas.model(entry), simulation: selection.simulation,
                physiologyInputs: selection.physiologyInputs, previewPresented: $state.previewPresented,
                destination: { id in
                  if let target = atlas.entry(id), depth < 32 {
                    return AnyView(GalaxySSIHealthAtlasDetail(atlas: atlas, entry: target, state: state, records: records, depth: depth + 1))
                  }
                  return AnyView(EmptyView())
                })
            }
            Button(t("research")) { research = true }
            Divider()
            Link(t(atlas.model(entry).reference == nil ? "evidence" : "reference_pubmed"), destination: atlas.model(entry).source)
            Text(t("art_note")).font(.footnote).foregroundColor(.secondary)
            if selection.wrappedValue.tab == .structure || selection.wrappedValue.tab == .function,
               let source = atlas.plate(for: entry.id, viewKey: selection.wrappedValue.artworkView)?.source {
              Link(t("plate_source"), destination: source).frame(minHeight: 44)
            }
          }.padding()
        }
      }
    }
    .navigationTitle(name).navigationBarTitleDisplayMode(.inline)
    .safeAreaInset(edge: .bottom) {
      if selection.wrappedValue.tab != .values {
        GalaxySSIHealthAtlasAsk(atlas: atlas, entry: entry, selection: state.functionSnapshot(entry),
          selectionSnapshot: { state.functionSnapshot(entry) }, onPreviewStateChange: { state.previewPresented = $0 })
          .padding(.horizontal)
      }
    }
    .background(NavigationLink(isActive: $research) {
      GalaxySSIHealthAtlasResearch(atlas: atlas, entry: entry, state: state, records: records, depth: depth)
    } label: { EmptyView() }.hidden())
    .galaxySSIHealthTheme()
  }
  @ViewBuilder private var structure: some View {
    if entry.kind == .organ {
      Picker(t("structure"), selection: selection.selectedStructureLayer) {
        Text(t("organ_layer")).tag(GalaxySSIHealthAtlasState.StructureLayer.organ)
        Text(t("tissues")).tag(GalaxySSIHealthAtlasState.StructureLayer.tissue)
        Text(t("cells")).tag(GalaxySSIHealthAtlasState.StructureLayer.cell)
      }.pickerStyle(.segmented).accessibilityIdentifier("atlas-structure-layer")
      switch selection.wrappedValue.selectedStructureLayer {
      case .organ: anatomy
      case .tissue:
        let tissues = atlas.tissues(entry)
        if tissues.isEmpty { Text(t("no_linked_tissues")).foregroundColor(.secondary) }
        else { relationships(tissues, title: t("tissues")) }
      case .cell:
        let cells = atlas.cells(entry)
        if cells.isEmpty { Text(t("no_linked_cells")).foregroundColor(.secondary) }
        else { relationships(cells, title: t("cells")) }
      }
    } else { anatomy }
  }
  @ViewBuilder private var anatomy: some View {
    GalaxySSIHealthAtlasArtwork(atlas: atlas, entry: entry, state: state, records: records, depth: depth)
    Text(GalaxySSIHealthAtlasText.get(entry.description, language))
    let cells = entry.kind == .cell || entry.kind == .fragment ? [] : atlas.cells(entry)
    relationships(atlas.children(entry).filter { item in !cells.contains(where: { $0.id == item.id }) }, title: t("related"))
    if entry.kind == .system { relationships(atlas.tissues(entry), title: t("tissues")) }
    relationships(cells, title: t(entry.kind == .tissue ? "tissue_cell_examples" : "cells"))
    let systems = entry.systems.compactMap(atlas.entry).filter { $0.id != entry.id }
    if entry.kind == .tissue {
      relationships(entry.locations.compactMap(atlas.entry), title: t("tissue_locations"))
      relationships(systems, title: t("belongs"))
    } else { relationships((atlas.parents(entry) + systems).filter { $0.id != entry.id }, title: t("belongs")) }
  }
  @ViewBuilder private func relationships(_ entries: [GalaxySSIHealthAtlas.Entry], title: String) -> some View {
    let unique = entries.reduce(into: [GalaxySSIHealthAtlas.Entry]()) { result, entry in
      if !result.contains(where: { $0.id == entry.id }) { result.append(entry) }
    }
    if !unique.isEmpty {
      Text(title).font(.headline)
      ForEach(unique) { item in
        if depth < 32 {
          NavigationLink(destination: GalaxySSIHealthAtlasDetail(atlas: atlas, entry: item, state: state, records: records, depth: depth + 1)) {
            GalaxySSIHealthAtlasRow(entry: item)
          }
        } else { GalaxySSIHealthAtlasRow(entry: item) }
      }
    }
  }
  private var name: String { GalaxySSIHealthAtlasText.get(entry.name, language) }
  private func t(_ key: String) -> String { GalaxySSIHealthAtlasText.get("health_atlas_" + key, language) }
}

@MainActor
struct GalaxySSIHealthAtlasValues: View {
  let entry: GalaxySSIHealthAtlas.Entry
  let records: GalaxySSIHealthRecords
  @Binding var selection: GalaxySSIHealthAtlasState.Selection
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  private var metrics: [GalaxySSIHealthMetric] { GalaxySSIHealthAtlasMetrics.forEntry(entry.id) }
  var body: some View {
    if let first = metrics.first {
      VStack(spacing: 8) {
        Text(t("records_note")).font(.footnote).foregroundColor(.secondary).padding(.horizontal)
        Picker(t("measurements"), selection: Binding(get: { selection.metric ?? first }, set: { selection.metric = $0 })) {
          ForEach(metrics) { metric in
            Text(metric.title(language: language)).tag(metric)
          }
        }.padding(.horizontal)
        trend(first)
      }.privacySensitive()
    } else {
      Text(t("no_metrics")).padding().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .safeAreaInset(edge: .bottom) {
          #if GALAXYSSI_ATLAS_AGENT_CONTEXT
          GalaxySSIHealthAtlasPinnedAnalysisButton(enabled: false, action: {})
          #endif
        }
    }
  }
  @ViewBuilder private func trend(_ first: GalaxySSIHealthMetric) -> some View {
    #if GALAXYSSI_ATLAS_AGENT_CONTEXT
    GalaxySSIHealthTrendView(records: records, fixedMetric: selection.metric ?? first,
      atlasWindow: $selection.window).id(selection.metric ?? first).environment(\.galaxySSIAtlasPinnedAnalysis, true)
      .environment(\.galaxySSIAtlasAnalysisSelection, entry.id + ":" + (selection.metric ?? first).rawValue + ":" + selection.window.rawValue)
    #else
    GalaxySSIHealthTrendView(records: records, fixedMetric: selection.metric ?? first,
      atlasWindow: $selection.window).id(selection.metric ?? first)
    #endif
  }
  private func t(_ key: String) -> String { GalaxySSIHealthAtlasText.get("health_atlas_" + key, language) }
}
