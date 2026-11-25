import SwiftUI

@MainActor
struct GalaxySSIHealthAtlasSimulationPanel: View {
  let atlas: GalaxySSIHealthAtlas
  let entry: GalaxySSIHealthAtlas.Entry
  let model: GalaxySSIHealthAtlas.Mechanism
  @Binding var simulation: GalaxySSIHealthAtlasSimulation
  @Binding var physiologyInputs: [Int]?
  @Binding var previewPresented: Bool
  let destination: (String) -> AnyView
  var mechanismFirst = false
  var inline = false
  @EnvironmentObject private var playback: GalaxySSIHealthAtlasPlayback
  @State private var inlineClock: GalaxySSIHealthAtlasChapterClock?
  private var playbackID: String { "simulation|" + entry.id }
  @State private var structure: String?
  @State private var referencesExpanded = false
  @ScaledMetric(relativeTo: .footnote) private var stageSize: CGFloat = 14
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scene
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var playing = false
  @State private var lastTick: Date?
  private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
  private var cardiac: Bool { ["cardio", "heart"].contains(entry.id) }
  private var lung: Bool { ["lungs", "respiratory"].contains(entry.id) }
  private var gasExchange: Bool { GalaxySSIHealthAtlasGasExchange.supports(entry.id) }
  private var retinal: Bool { entry.id == GalaxySSIHealthAtlasRetinaPath.owner }
  private var sweat: Bool { entry.id == GalaxySSIHealthAtlasSweat.owner }
  private var section: GalaxySSIHealthAtlasSectionLesson? { .forEntry(entry.id) }
  private var quantitativeAfterSection: Bool { section != nil && entry.kind != .cell }
  var quantitativeAfterArt: Bool {
    mechanismFirst || gasExchange || entry.id == "pancreas" || endocrine != nil || sweat || quantitativeAfterSection
  }
  private var endocrine: GalaxySSIHealthAtlasEndocrinePath? { GalaxySSIHealthAtlasEndocrinePath.forEntry(entry.id) }
  private var germline: GalaxySSIHealthAtlasGermline.Counts? {
    GalaxySSIHealthAtlasGermline.counts(entry.id, stage: simulation.stage)
  }
  private var hasPhysiology: Bool {
    #if GALAXYSSI_ATLAS_PHYSIOLOGY
    return GalaxySSIHealthAtlasPhysiology.Kind.forEntry(entry.id) != nil
    #else
    return false
    #endif
  }

  private var hasDiagram: Bool { GalaxySSIHealthAtlasCirculation.supports(entry.id) || gasExchange || endocrine != nil || retinal }
  private var hasCloseup: Bool {
    section != nil || sweat || germline != nil || GalaxySSIHealthAtlasPancreatic.supports(entry.id) ||
      GalaxySSIHealthAtlasHeartSection.Valve.supports(entry.id) || entry.id == GalaxySSIHealthAtlasFiltrationStage.owner ||
      entry.id == GalaxySSIHealthAtlasSarcomere.owner || entry.id == GalaxySSIHealthAtlasPhagocytosis.owner ||
      GalaxySSIHealthAtlasGranulocyte(rawValue: entry.id) != nil || GalaxySSIHealthAtlasImmuneLink(rawValue: entry.id) != nil ||
      GalaxySSIHealthAtlasBloodDefense(rawValue: entry.id) != nil
  }
  private var stageCaptions: [String] {
    model.stages.enumerated().map {
      String(format: t("stage"), Int64($0.offset + 1), Int64(model.stages.count), GalaxySSIHealthAtlasText.get($0.element, language))
    }
  }
  private var stageCaption: some View {
    GalaxySSIHealthAtlasReservedCaption(values: stageCaptions, selected: simulation.stage, identifier: "atlas-simulation-stage")
      .font(.system(size: stageSize, weight: .semibold))
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      #if GALAXYSSI_ATLAS_PHYSIOLOGY
      if !quantitativeAfterArt { quantitative.accessibilityIdentifier("atlas-quantitative-before-art") }
      #endif
      GalaxySSIHealthAtlasSceneFrame(identifier: "atlas-simulation-frame", inset: 8) {
        VStack(alignment: .leading, spacing: 8) {
          if !hasDiagram && !hasCloseup, let plate = atlas.plate(for: entry.id) {
            GalaxySSIHealthAtlasSimulationPlate(plate: plate, name: GalaxySSIHealthAtlasText.get(entry.name, language),
              language: language, preview: { if $0 { pause() }; previewPresented = $0 })
          }
          Text(GalaxySSIHealthAtlasText.get(model.title, language)).font(.callout.weight(.semibold))
          if !inline && (hasDiagram || hasCloseup) { playbackControls }
          simulationArtwork
          if !retinal && endocrine == nil {
            GalaxySSIHealthAtlasFigureFrame(identifier: "atlas-simulation-figure", header: { EmptyView() }, artwork: {
              processArtwork
            }, legend: { stageCaption })
          }
          if inline || (!hasDiagram && !hasCloseup) { playbackControls }
          Slider(value: Binding(get: { simulation.phase }, set: { value in pause(); simulation.phase = value }), in: 0...1,
            onEditingChanged: { _ in pause() })
            .accessibilityLabel(t("phase")).accessibilityIdentifier("atlas-simulation-progress")
        }
      }
      #if GALAXYSSI_ATLAS_PHYSIOLOGY
      if quantitativeAfterArt { quantitative.accessibilityIdentifier("atlas-quantitative-after-art") }
      #endif
      if cardiac || (lung && !hasPhysiology) {
        Text(t("parameters")).font(.headline)
        parameter(cardiac ? "heart_rate" : "rate", value: $simulation.first, range: cardiac ? 40...160 : 6...30,
          unit: cardiac ? "bpm" : "/min")
        parameter(cardiac ? "stroke_volume" : "tidal", value: $simulation.second,
          range: cardiac ? 30...120 : 200...900, unit: "mL")
        Text(t(cardiac ? "cardiac_output" : "ventilation") + ": " + String(format: "%.2f L/min", simulation.output)).font(.headline)
      }
      if !inline {
        Text(t("speed") + " · " + String(format: "%.1f×", simulation.speed))
        Slider(value: $simulation.speed, in: 0.5...2, step: 0.5).accessibilityLabel(t("speed"))
      }
      if inline {
        DisclosureGroup(isExpanded: $referencesExpanded) { referenceNotes } label: {
          Text(t("evidence")).frame(minHeight: 44)
        }.accessibilityIdentifier("atlas-simulation-references-toggle")
      } else { referenceNotes }
    }
    .background(NavigationLink(isActive: Binding(get: { structure != nil }, set: { if !$0 { structure = nil } })) {
      if let structure { destination(structure) }
    } label: { EmptyView() })
    .onReceive(timer) { now in
      guard playing, scene == .active, !previewPresented else { return }
      guard playback.owner == playbackID else { pause(at: playback.changedAt); return }
      if inline {
        guard var clock = inlineClock else { return }
        let next = clock.sample(GalaxySSIHealthAtlasChapterClock.now)
        inlineClock = clock
        if !reduceMotion || Int(min(3, next * 4)) != simulation.stage || !clock.playing { simulation.phase = next }
        if !clock.playing { playing = false; playback.release(playbackID) }
        return
      }
      guard !reduceMotion else { return }
      defer { lastTick = now }
      guard let lastTick else { return }
      simulation.phase = min(1, simulation.phase + min(0.2, now.timeIntervalSince(lastTick)) * simulation.speed / 8)
      if simulation.phase >= 1 { pause() }
    }
    .onChange(of: playback.owner) { if playing, $0 != playbackID { pause(at: playback.changedAt) } }
    .onChange(of: scene) { _ in pause() }
    .onChange(of: reduceMotion) { _ in pause() }
    .onChange(of: previewPresented) { _ in pause() }
    .onDisappear { pause() }
  }
  @ViewBuilder private var simulationArtwork: some View {
    if let section { GalaxySSIHealthAtlasSectionLessonView(lesson: section, phase: simulation.phase, stages: model.stages, language: language) }
    if sweat { GalaxySSIHealthAtlasSweatView(phase: simulation.phase, stages: model.stages, language: language) }
    if retinal {
      GalaxySSIHealthAtlasRetinaPathView(atlas: atlas, model: model, stage: simulation.stage, language: language,
        select: { pause(); simulation.selectStage($0) }, open: openStructure)
    }
    if let endocrine {
      GalaxySSIHealthAtlasEndocrinePathView(atlas: atlas, entry: entry, path: endocrine, stage: simulation.stage, language: language,
        select: { pause(); simulation.selectStage($0) }, open: openStructure)
    }
    if GalaxySSIHealthAtlasPancreatic.supports(entry.id) {
      GalaxySSIHealthAtlasPancreaticPanel(atlas: atlas, entryID: entry.id, stage: simulation.stage, language: language,
        open: openStructure, showsScope: false)
    }
    if entry.id == GalaxySSIHealthAtlasFiltrationStage.owner { GalaxySSIHealthAtlasPodocyteView(stage: simulation.stage, stages: model.stages, language: language) }
    if entry.id == GalaxySSIHealthAtlasSarcomere.owner { GalaxySSIHealthAtlasSarcomerePanel(stage: simulation.stage, stages: model.stages, language: language) }
    if entry.id == GalaxySSIHealthAtlasPhagocytosis.owner { GalaxySSIHealthAtlasPhagocytosis(phase: simulation.phase, stages: model.stages, language: language) }
    if let lesson = GalaxySSIHealthAtlasGranulocyte(rawValue: entry.id) {
      GalaxySSIHealthAtlasGranulocyteView(lesson: lesson, phase: simulation.phase, stages: model.stages, language: language)
    }
    if let lesson = GalaxySSIHealthAtlasImmuneLink(rawValue: entry.id) {
      GalaxySSIHealthAtlasImmuneLinkView(atlas: atlas, lesson: lesson, phase: simulation.phase, stages: model.stages,
        language: language, open: openStructure, showsDetails: false)
    }
    if let lesson = GalaxySSIHealthAtlasBloodDefense(rawValue: entry.id) {
      GalaxySSIHealthAtlasBloodDefenseView(atlas: atlas, lesson: lesson, phase: simulation.phase, stages: model.stages,
        language: language, open: openStructure, showsDetails: false)
    }
    if GalaxySSIHealthAtlasHeartSection.Valve.supports(entry.id) {
      GalaxySSIHealthAtlasValvePanel(atlas: atlas, entryID: entry.id, stage: simulation.stage, language: language, open: openStructure)
    }
    if let germline { GalaxySSIHealthAtlasGermlineView(counts: germline, language: language, showsDetails: false) }
  }
  @ViewBuilder private var processArtwork: some View {
    if gasExchange {
      GalaxySSIHealthAtlasGasExchangeView(phase: simulation.phase, language: language, stages: model.stages,
        selected: { pause(); simulation.selectStage($0) }, open: openStructure)
    }
    if GalaxySSIHealthAtlasCirculation.supports(entry.id) {
      GalaxySSIHealthAtlasCirculationView(phase: simulation.phase, flow: cardiac ? simulation.output : nil, language: language,
        stages: model.stages, selected: { pause(); simulation.selectStage($0) }, open: openStructure)
    }
    if !hasDiagram {
      GalaxySSIHealthAtlasProcessStages(stages: model.stages, phase: simulation.phase, language: language,
        entryID: entry.id, compact: inline, annotationScope: "atlas-simulation-figure",
        selected: { pause(); simulation.selectStage($0) })
    }
  }
  private func openStructure(_ id: String) { pause(); structure = id }
  private var referenceNotes: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let section {
        ForEach(section.notes, id: \.self) { key in Text(GalaxySSIHealthAtlasText.get(key, language)).font(.footnote).foregroundColor(.secondary) }
      }
      if sweat { Text(t("context_sweat_scope")) }
      if entry.id == "hair-follicles" { Text(t("context_hair_scope")) }
      if entry.id == GalaxySSIHealthAtlasFiltrationStage.owner { Text(t("podocyte_scope")) }
      if entry.id == GalaxySSIHealthAtlasPhagocytosis.owner { Text(t("phagocytosis_scope")) }
      if let lesson = GalaxySSIHealthAtlasGranulocyte(rawValue: entry.id) { Text(t(lesson.scopeKey)) }
      if let lesson = GalaxySSIHealthAtlasImmuneLink(rawValue: entry.id) {
        Text(t(lesson.scopeKey))
        GalaxySSIHealthAtlasCellSceneRelatedRow(atlas: atlas, entryID: lesson.relatedID, language: language, open: openStructure)
      }
      if let lesson = GalaxySSIHealthAtlasBloodDefense(rawValue: entry.id) {
        Text(t(lesson.scopeKey))
        if let id = lesson.relatedID { GalaxySSIHealthAtlasCellSceneRelatedRow(atlas: atlas, entryID: id, language: language, open: openStructure) }
      }
      if gasExchange {
        Text(t("gas_scope")); Link(t("gas_reference"), destination: GalaxySSIHealthAtlasGasExchange.source).frame(minHeight: 44)
      }
      if GalaxySSIHealthAtlasCirculation.supports(entry.id) {
        Text(t("circuit_scope")); Link(t("circuit_reference"), destination: GalaxySSIHealthAtlasCirculation.source).frame(minHeight: 44)
      }
      if retinal { Link(t("sensory_retinal_paper"), destination: GalaxySSIHealthAtlasRetinaPath.source).frame(minHeight: 44) }
      if entry.id == "pancreas" {
        Text(t("digestive_routes_scope"))
        Link(t("digestive_routes_reference"), destination: GalaxySSIHealthAtlasPancreatic.source).frame(minHeight: 44)
      }
      if entry.id == "pancreatic-islets" { Text(t("digestive_islets_scope")) }
      if germline != nil {
        Text(t("germline_timing"))
        Text(t("germline_scope")).accessibilityIdentifier("atlas-germline-scope")
        Link(t("germline_source"), destination: GalaxySSIHealthAtlasGermline.source).frame(minHeight: 44)
      }
      Text(t("process_note"))
      #if GALAXYSSI_ATLAS_PHYSIOLOGY
      if hasPhysiology, let note = GalaxySSIHealthAtlasPhysiologyText.processNote(language: language) { Text(note) }
      #endif
      Text(t("teaching_note"))
      if cardiac || (lung && !hasPhysiology) { Text(t(cardiac ? "cardiac_formula" : "ventilation_formula")) }
      else if !hasPhysiology, germline == nil { Text(t("qualitative_note")) }
      if reduceMotion { Text(bodyText("motion_disabled")) }
      if inline {
        Link(t(model.reference == nil ? "reference_openstax" : "reference_pubmed"), destination: model.source)
          .frame(minHeight: 44).accessibilityIdentifier("atlas-source-physiology")
      }
    }.font(.footnote).foregroundColor(.secondary).accessibilityIdentifier("atlas-simulation-references")
  }
  #if GALAXYSSI_ATLAS_PHYSIOLOGY
  private var quantitative: some View {
    GalaxySSIHealthAtlasPhysiologyPanel(entryID: entry.id, inputs: $physiologyInputs, language: language,
      legacyVentilation: (lung || entry.id == "alveoli") ? [simulation.first, simulation.second] : nil)
  }
  #endif
  private var playbackControls: some View {
      HStack {
        control("backward.step", "previous_step") { pause(); simulation.selectStage(max(0, simulation.stage - 1)) }
        control(playing ? "pause.fill" : "play.fill", playing ? "pause" : "play") {
          if playing { pause(); return }
          if simulation.phase >= 1 { simulation.phase = 0 }
          let now = GalaxySSIHealthAtlasChapterClock.now
          playback.claim(playbackID, now: now, pause: { pause(at: $0) })
          if inline {
            var clock = GalaxySSIHealthAtlasChapterClock(chapters: model.stages.count, phase: simulation.phase)
            clock.resume(now); inlineClock = clock
          }
          playing = true; lastTick = nil
        }.disabled((reduceMotion && !inline) || previewPresented)
        control("forward.step", "next_step") { pause(); simulation.selectStage(min(3, simulation.stage + 1)) }
        Spacer()
        Button { pause(); simulation = .initial(entry.id); physiologyInputs = nil } label: {
          Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44)
        }.accessibilityLabel(t("reset")).help(t("reset"))
      }
  }
  private func pause(at now: Int64) {
    if playing, inline, var clock = inlineClock {
      clock.pause(now); simulation.phase = clock.sample(now); inlineClock = clock
    }
    playing = false; lastTick = nil; playback.release(playbackID)
  }
  private func pause() { pause(at: GalaxySSIHealthAtlasChapterClock.now) }
  private func parameter(_ key: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
    VStack(alignment: .leading) {
      Text(t(key) + ": " + String(Int(value.wrappedValue)) + " " + unit)
      Slider(value: value, in: range, step: 1).accessibilityLabel(t(key))
    }
  }
  private func control(_ symbol: String, _ key: String, action: @escaping () -> Void) -> some View {
    Button(action: action) { Image(systemName: symbol).frame(width: 44, height: 44) }
      .accessibilityLabel(bodyText(key)).help(bodyText(key))
  }
  private func t(_ key: String) -> String { GalaxySSIHealthAtlasText.get("health_atlas_" + key, language) }
  private func bodyText(_ key: String) -> String { GalaxySSIHealthBodyText.string(key, language: language) }
}
