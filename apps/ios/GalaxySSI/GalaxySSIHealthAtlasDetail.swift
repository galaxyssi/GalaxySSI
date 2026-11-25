import SwiftUI

@MainActor
struct GalaxySSIHealthAtlasDetail: View {
  let atlas: GalaxySSIHealthAtlas
  let entry: GalaxySSIHealthAtlas.Entry
  @ObservedObject var state: GalaxySSIHealthAtlasState
  let records: GalaxySSIHealthRecords
  let depth: Int
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @StateObject private var scrollMemory = GalaxySSIHealthAtlasScrollMemory()
  @State private var principleExpanded = false
  private var usesInlineModels: Bool { GalaxySSIHealthAtlasState.usesInlineModels(entry) }
  private var currentTab: GalaxySSIHealthAtlasState.Tab { selection.wrappedValue.tab == .simulation ? .function : selection.wrappedValue.tab }
  private var standalone: Binding<Bool> {
    Binding(get: { !usesInlineModels && selection.wrappedValue.tab == .simulation }, set: {
      if !$0, selection.wrappedValue.tab == .simulation { state.closeStandaloneModel(entry) }
    })
  }

  private var location: GalaxySSIHealthAtlasLessonNavigation.Location { .init(entryID: entry.id, depth: depth) }
  private var selection: Binding<GalaxySSIHealthAtlasState.Selection> { state.detailBinding(entry, depth: depth) }
  private var relatedDestination: Binding<Bool> {
    Binding(get: { state.lessonNavigation.returns[location.key] != nil }, set: { if !$0 { state.closeRelatedLesson(location) } })
  }
  private var research: Binding<Bool> {
    Binding(get: { selection.wrappedValue.tab != .simulation && selection.wrappedValue.researchPresented == true }, set: { open in
      if !open { state.closeResearch(entry) }
    })
  }
  private var researchTitle: String { t(usesInlineModels ? "targeted_research" : "research") }
  private var functionCatalogue: GalaxySSIHealthAtlasFunctionCatalogue? { try? GalaxySSIHealthAtlasFunctionCatalogue.bundled.get() }
  private var hasFunctionPlayer: Bool {
    functionCatalogue?.choices(for: entry.id).contains { GalaxySSIHealthAtlasFunctionRendering.implemented.contains($0.id) } == true
  }
  private var functionSelection: Binding<GalaxySSIHealthAtlasFunctionSelection> {
    Binding(get: { selection.wrappedValue.functionSelection ?? .init() }, set: { selection.wrappedValue.functionSelection = $0 })
  }
  var body: some View {
    VStack(spacing: 0) {
      GalaxySSIHealthAtlasCompactTabs(options: GalaxySSIHealthAtlasState.detailTabs,
        selection: Binding(get: { currentTab }, set: { _ = state.selectDetailTab(entry, depth: depth, tab: $0) }),
        title: { t($0.rawValue) }, key: { $0.rawValue }, identifier: "atlas-detail-tabs")
        .onChange(of: selection.wrappedValue.tab) { tab in
          if tab != .values { selection.wrappedValue.revealTrend = false }
          if tab == .function { scrollMemory.restore(0) }
        }
      if selection.wrappedValue.tab == .values {
        GalaxySSIHealthAtlasValues(entry: entry, records: records, selection: selection)
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            if currentTab == .function, hasFunctionPlayer, let catalogue = functionCatalogue {
              GalaxySSIHealthAtlasFunctionPanel(catalogue: catalogue, entryID: entry.id, language: language,
                previewPresented: state.previewPresented, selection: functionSelection,
                onPhase: { state.recordFunctionPhase(entryID: entry.id, storyID: $0, phase: $1, depth: depth) },
                navigationID: location.key, relatedActions: relatedActions)
              numericalModelButton
            }
            if currentTab == .function && !hasFunctionPlayer {
              GalaxySSIHealthAtlasArtwork(atlas: atlas, entry: entry, state: state, records: records, depth: depth)
              Text(GalaxySSIHealthAtlasText.get(entry.description, language))
            }
            if currentTab == .structure {
              structure
            } else if currentTab == .function && !hasFunctionPlayer {
              DisclosureGroup(isExpanded: $principleExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                  ForEach(Array(atlas.model(entry).stages.enumerated()), id: \.offset) { index, key in
                    Text(String(format: t("stage"), Int64(index + 1), Int64(atlas.model(entry).stages.count), GalaxySSIHealthAtlasText.get(key, language)))
                  }
                  Text(t("process_note")).font(.footnote).foregroundColor(.secondary)
                }.accessibilityIdentifier("atlas-function-principle")
              } label: {
                Text(String(format: t("related_process"), GalaxySSIHealthAtlasText.get(atlas.model(entry).title, language)))
                  .font(.headline).frame(minHeight: 44)
              }.accessibilityIdentifier("atlas-function-principle-toggle")
              numericalModelButton
            }
            if currentTab == .function {
              Button(researchTitle) { state.openResearch(entry, returnScroll: scrollMemory.offset) }
                .frame(minHeight: 44).accessibilityIdentifier("atlas-open-research")
            }
            if currentTab == .structure {
              Divider()
              Text(t("art_note")).font(.footnote).foregroundColor(.secondary)
              if let source = atlas.plate(for: entry.id, viewKey: selection.wrappedValue.artworkView)?.source {
                Link(t("plate_source"), destination: source).frame(minHeight: 44)
              }
            }
          }.padding().background {
            if selection.wrappedValue.tab == .function {
              GalaxySSIHealthAtlasScrollAnchor(memory: scrollMemory, revision: scrollMemory.revision)
            }
          }
        }.id(currentTab)
      }
    }
    .navigationTitle(name).navigationBarTitleDisplayMode(.inline)
    .safeAreaInset(edge: .bottom) {
      if selection.wrappedValue.tab != .values {
        GalaxySSIHealthAtlasAsk(atlas: atlas, entry: entry, selection: state.functionSnapshot(entry, depth: depth),
          selectionSnapshot: { state.functionSnapshot(entry, depth: depth) }, onPreviewStateChange: {
            if $0 { state.playback.pause() }
            state.previewPresented = $0
          })
          .padding(.horizontal)
      }
    }
    .background(NavigationLink(isActive: research) {
      GalaxySSIHealthAtlasResearch(atlas: atlas, entry: entry, state: state, records: records, depth: depth)
    } label: { EmptyView() }.hidden())
    .background(NavigationLink(isActive: standalone) {
      GalaxySSIHealthAtlasStandaloneModels(atlas: atlas, entry: entry, state: state, records: records, depth: depth)
    } label: { EmptyView() }.hidden())
    .background(NavigationLink(isActive: relatedDestination) {
      if let saved = state.lessonNavigation.returns[location.key], let target = atlas.entry(saved.targetID) {
        GalaxySSIHealthAtlasDetail(atlas: atlas, entry: target, state: state, records: records, depth: depth + 1)
      }
    } label: { EmptyView() }.hidden())
    .background(GalaxySSIHealthAtlasRestoredDetailLink(atlas: atlas, entry: entry, state: state, records: records, depth: depth,
      enabled: selection.wrappedValue.researchPresented != true && selection.wrappedValue.tab != .simulation))
    .galaxySSIHealthTheme()
    .environmentObject(state.playback)
    .onAppear {
      state.recordDetail(entry, depth: depth)
      if let offset = state.lessonReturnScroll.removeValue(forKey: location.key) ?? state.lessonNavigation.returns[location.key]?.scroll {
        scrollMemory.restore(offset)
      } else if selection.wrappedValue.tab == .function, let offset = selection.wrappedValue.researchReturnScroll { scrollMemory.restore(offset) }
    }
    .onChange(of: selection.wrappedValue.researchPresented) { open in
      if open != true, selection.wrappedValue.tab == .function, let offset = selection.wrappedValue.researchReturnScroll { scrollMemory.restore(offset) }
    }
  }
  private func relatedActions(_ story: GalaxySSIHealthAtlasFunctionCatalogue.Story) -> [GalaxySSIHealthAtlasRelatedAction] {
    guard depth < 32, let catalogue = functionCatalogue else { return [] }
    return story.related.compactMap { related in
      guard let target = atlas.entry(related.entryID), let lesson = catalogue.story(related.storyID),
        catalogue.routes[target.id]?.contains(lesson.id) == true else { return nil }
      let label = String(format: t("related_lesson_label"), GalaxySSIHealthAtlasText.get(target.name, language),
        GalaxySSIHealthAtlasFunctionText.get(lesson.title, language))
      return GalaxySSIHealthAtlasRelatedAction(id: target.id + "|" + lesson.id, label: label, open: {
        _ = state.openRelatedLesson(origin: entry, depth: depth, related: related, scroll: scrollMemory.offset,
          atlas: atlas, catalogue: catalogue)
      })
    }
  }
  @ViewBuilder private var numericalModelButton: some View {
    if usesInlineModels {
      DisclosureGroup(isExpanded: Binding(get: { selection.wrappedValue.modelsExpanded == true }, set: { expanded in
        // Claiming the model surface freezes the lesson before expanding or saving it.
        state.playback.claim("models-disclosure|" + entry.id)
        selection.wrappedValue.modelsExpanded = expanded
      })) {
        VStack(alignment: .leading, spacing: 16) {
          simulationPanel
        }.accessibilityIdentifier("atlas-inline-models")
      } label: { Text(t("inline_models")).frame(minHeight: 44) }
        .accessibilityIdentifier("atlas-open-simulation")
    } else {
    Button {
      state.openNumericalModel(entry)
    } label: {
      HStack {
        Label(t("open_quantitative_model"), systemImage: "chart.bar")
        Spacer()
        Image(systemName: "chevron.right").accessibilityHidden(true)
      }.frame(minHeight: 44).contentShape(Rectangle())
    }.buttonStyle(.plain).accessibilityIdentifier("atlas-open-simulation")
    }
  }
  private var simulationPanel: some View {
    GalaxySSIHealthAtlasSimulationPanel(atlas: atlas, entry: entry, model: atlas.model(entry), simulation: selection.simulation,
      physiologyInputs: selection.physiologyInputs, previewPresented: $state.previewPresented,
      destination: { id in
        if let target = atlas.entry(id), depth < 32 {
          return AnyView(GalaxySSIHealthAtlasDetail(atlas: atlas, entry: target, state: state, records: records, depth: depth + 1))
        }
        return AnyView(EmptyView())
      }, mechanismFirst: usesInlineModels, inline: usesInlineModels)
  }
  private var mechanismSource: some View {
    Link(t(atlas.model(entry).reference == nil ? "evidence" : "reference_pubmed"), destination: atlas.model(entry).source)
      .frame(minHeight: 44).accessibilityIdentifier("atlas-source-physiology")
  }
  @ViewBuilder private var structure: some View {
    if entry.kind == .organ {
      GalaxySSIHealthAtlasCompactTabs(options: GalaxySSIHealthAtlasState.StructureLayer.allCases,
        selection: selection.selectedStructureLayer, title: {
          t($0 == .organ ? "organ_layer" : $0 == .tissue ? "tissues" : "cells")
        }, key: { $0.rawValue }, identifier: "atlas-structure-layer")
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
  private var revealTrend: Binding<Bool> {
    Binding(get: { selection.revealTrend == true }, set: { selection.revealTrend = $0 })
  }
  var body: some View {
    if let first = metrics.first {
      VStack(spacing: 8) {
        Text(t("records_note")).font(.footnote).foregroundColor(.secondary).padding(.horizontal)
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
      atlasWindow: $selection.window, revealAtlasTrend: revealTrend,
      atlasEntryID: entry.id, atlasMetricSelection: $selection.metric).id(selection.metric ?? first).environment(\.galaxySSIAtlasPinnedAnalysis, true)
      .environment(\.galaxySSIAtlasAnalysisSelection, entry.id + ":" + (selection.metric ?? first).rawValue + ":" + selection.window.rawValue)
    #else
    GalaxySSIHealthTrendView(records: records, fixedMetric: selection.metric ?? first,
      atlasWindow: $selection.window, revealAtlasTrend: revealTrend,
      atlasEntryID: entry.id, atlasMetricSelection: $selection.metric).id(selection.metric ?? first)
    #endif
  }
  private func t(_ key: String) -> String { GalaxySSIHealthAtlasText.get("health_atlas_" + key, language) }
}
