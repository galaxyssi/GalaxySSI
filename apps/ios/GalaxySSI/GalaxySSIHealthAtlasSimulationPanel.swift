import SwiftUI

struct GalaxySSIHealthAtlasSimulationPanel: View {
  let atlas: GalaxySSIHealthAtlas
  let entry: GalaxySSIHealthAtlas.Entry
  let model: GalaxySSIHealthAtlas.Mechanism
  @Binding var simulation: GalaxySSIHealthAtlasSimulation
  @Binding var physiologyInputs: [Int]?
  @Binding var previewPresented: Bool
  let destination: (String) -> AnyView
  @State private var structure: String?
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

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      #if GALAXYSSI_ATLAS_PHYSIOLOGY
      if !gasExchange, entry.id != "pancreas", endocrine == nil, !retinal {
      GalaxySSIHealthAtlasPhysiologyPanel(entryID: entry.id, inputs: $physiologyInputs, language: language,
        legacyVentilation: lung ? [simulation.first, simulation.second] : nil)
      }
      #endif
      Text(String(format: t("related_process"), GalaxySSIHealthAtlasText.get(model.title, language))).font(.headline)
      if retinal {
        playbackControls
        GalaxySSIHealthAtlasRetinaPathView(atlas: atlas, model: model, stage: simulation.stage, language: language,
          select: { playing = false; simulation.selectStage($0) }, open: { playing = false; structure = $0 })
      }
      if let endocrine {
        playbackControls
        GalaxySSIHealthAtlasEndocrinePathView(atlas: atlas, entry: entry, path: endocrine, stage: simulation.stage,
          language: language, select: { playing = false; simulation.selectStage($0) },
          open: { playing = false; structure = $0 })
      }
      if GalaxySSIHealthAtlasPancreatic.supports(entry.id) {
        playbackControls
        GalaxySSIHealthAtlasPancreaticPanel(atlas: atlas, entryID: entry.id, stage: simulation.stage, language: language,
          open: { playing = false; structure = $0 })
      }
      if entry.id == GalaxySSIHealthAtlasFiltrationStage.owner {
        playbackControls
        GalaxySSIHealthAtlasPodocyteView(stage: simulation.stage, stages: model.stages, language: language)
        Text(t("podocyte_scope")).font(.footnote).foregroundColor(.secondary)
      }
      if entry.id == GalaxySSIHealthAtlasSarcomere.owner {
        playbackControls
        GalaxySSIHealthAtlasSarcomerePanel(stage: simulation.stage, stages: model.stages, language: language)
      }
      if entry.id == GalaxySSIHealthAtlasPhagocytosis.owner {
        playbackControls
        GalaxySSIHealthAtlasPhagocytosis(stage: simulation.stage, stages: model.stages, language: language)
        Text(t("phagocytosis_scope")).font(.footnote).foregroundColor(.secondary)
      }
      if GalaxySSIHealthAtlasHeartSection.Valve.supports(entry.id) {
        playbackControls
        GalaxySSIHealthAtlasValvePanel(atlas: atlas, entryID: entry.id, stage: simulation.stage, language: language,
          open: { playing = false; structure = $0 })
      }
      if let germline {
        playbackControls
        Text(String(format: t("stage"), Int64(simulation.stage + 1), Int64(4),
          GalaxySSIHealthAtlasText.get(model.stages[simulation.stage], language)))
        GalaxySSIHealthAtlasGermlineView(counts: germline, language: language)
      }
      if gasExchange {
        GalaxySSIHealthAtlasGasExchangeView(phase: simulation.phase, language: language, stages: model.stages,
          selected: { playing = false; simulation.selectStage($0) },
          open: { playing = false; structure = $0 })
        Text(t("gas_scope")).font(.footnote).foregroundColor(.secondary)
        Link(t("gas_reference"), destination: GalaxySSIHealthAtlasGasExchange.source)
      }
      Text(t("process_note")).font(.footnote).foregroundColor(.secondary)
      #if GALAXYSSI_ATLAS_PHYSIOLOGY
      if hasPhysiology, let note = GalaxySSIHealthAtlasPhysiologyText.processNote(language: language) {
        Text(note).font(.footnote).foregroundColor(.secondary)
      }
      #endif
      if GalaxySSIHealthAtlasCirculation.supports(entry.id) {
        playbackControls
        GalaxySSIHealthAtlasCirculationView(phase: simulation.phase, flow: cardiac ? simulation.output : nil,
          language: language, stages: model.stages,
          selected: { playing = false; simulation.selectStage($0) },
          open: { playing = false; structure = $0 })
        Text(t("circuit_scope")).font(.footnote).foregroundColor(.secondary)
        Link(t("circuit_reference"), destination: GalaxySSIHealthAtlasCirculation.source)
      } else if endocrine == nil, !retinal {
      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
        ForEach(gasExchange ? [] : [0, 1, 3, 2], id: \.self) { stage in
          Button { playing = false; simulation.selectStage(stage) } label: {
            VStack(spacing: 8) {
              Text("\(stage + 1)").font(.headline).frame(width: 32, height: 32)
                .background(stage <= simulation.stage ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.08)).clipShape(Circle())
              Text(GalaxySSIHealthAtlasText.get(model.stages[stage], language)).font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, minHeight: 44).padding(8)
          }.accessibilityLabel(String(format: t("stage"), Int64(stage + 1), Int64(4),
            GalaxySSIHealthAtlasText.get(model.stages[stage], language)))
            .accessibilityAddTraits(stage == simulation.stage ? .isSelected : [])
            .accessibilitySortPriority(Double(4 - stage))
            .accessibilityIdentifier("health-atlas-stage-" + entry.id + "-" + String(stage))
        }
      }
      }
      ProgressView(value: simulation.phase).accessibilityLabel(t("phase"))
      if germline == nil {
      Text(String(format: t("stage"), Int64(simulation.stage + 1), Int64(4),
        GalaxySSIHealthAtlasText.get(model.stages[simulation.stage], language)))
      }
      Slider(value: $simulation.phase, in: 0...1, onEditingChanged: { _ in playing = false })
        .accessibilityLabel(t("phase"))
      if !GalaxySSIHealthAtlasCirculation.supports(entry.id), !GalaxySSIHealthAtlasHeartSection.Valve.supports(entry.id),
         germline == nil, entry.id != GalaxySSIHealthAtlasPhagocytosis.owner,
         entry.id != GalaxySSIHealthAtlasSarcomere.owner, entry.id != GalaxySSIHealthAtlasFiltrationStage.owner,
         !GalaxySSIHealthAtlasPancreatic.supports(entry.id), endocrine == nil, !retinal { playbackControls }
      if reduceMotion { Text(bodyText("motion_disabled")).font(.caption) }
      Text(t("speed") + " · " + String(format: "%.1f×", simulation.speed))
      Slider(value: $simulation.speed, in: 0.5...2, step: 0.5).accessibilityLabel(t("speed"))
      if retinal { Link(t("sensory_retinal_paper"), destination: GalaxySSIHealthAtlasRetinaPath.source) }
      if entry.id == "pancreas" {
        Link(t("digestive_routes_reference"), destination: GalaxySSIHealthAtlasPancreatic.source)
      }
      #if GALAXYSSI_ATLAS_PHYSIOLOGY
      if endocrine != nil {
        GalaxySSIHealthAtlasPhysiologyPanel(entryID: entry.id, inputs: $physiologyInputs, language: language)
      }
      if entry.id == "pancreas" {
        GalaxySSIHealthAtlasPhysiologyPanel(entryID: entry.id, inputs: $physiologyInputs, language: language)
      }
      if gasExchange {
        GalaxySSIHealthAtlasPhysiologyPanel(entryID: entry.id, inputs: $physiologyInputs, language: language,
          legacyVentilation: entry.id == "alveoli" ? [simulation.first, simulation.second] : nil)
      }
      #endif
      Text(t("teaching_note")).font(.footnote).foregroundColor(.secondary)
      if cardiac || (lung && !hasPhysiology) {
        Text(t("parameters")).font(.headline)
        parameter(cardiac ? "heart_rate" : "rate", value: $simulation.first, range: cardiac ? 40...160 : 6...30,
          unit: cardiac ? "bpm" : "/min")
        parameter(cardiac ? "stroke_volume" : "tidal", value: $simulation.second,
          range: cardiac ? 30...120 : 200...900, unit: "mL")
        Text(t(cardiac ? "cardiac_output" : "ventilation") + ": " + String(format: "%.2f L/min", simulation.output)).font(.headline)
        Text(t(cardiac ? "cardiac_formula" : "ventilation_formula")).font(.footnote)
      } else if !hasPhysiology, germline == nil { Text(t("qualitative_note")).font(.footnote) }
    }
    .background(NavigationLink(isActive: Binding(get: { structure != nil }, set: { if !$0 { structure = nil } })) {
      if let structure { destination(structure) }
    } label: { EmptyView() })
    .onReceive(timer) { now in
      guard playing, scene == .active, !reduceMotion, !previewPresented else { return }
      defer { lastTick = now }
      guard let lastTick else { return }
      simulation.phase = min(1, simulation.phase + min(0.2, now.timeIntervalSince(lastTick)) * simulation.speed / 8)
      if simulation.phase >= 1 { playing = false }
    }
    .onChange(of: scene) { _ in playing = false; lastTick = nil }
    .onChange(of: reduceMotion) { _ in playing = false; lastTick = nil }
    .onChange(of: previewPresented) { _ in playing = false; lastTick = nil }
    .onDisappear { playing = false; lastTick = nil }
  }
  private var playbackControls: some View {
      HStack {
        control("backward.step", "previous_step") { playing = false; simulation.selectStage(max(0, simulation.stage - 1)) }
        control(playing ? "pause.fill" : "play.fill", playing ? "pause" : "play") {
          if simulation.phase >= 1 { simulation.phase = 0 }
          playing.toggle(); lastTick = nil
        }.disabled(reduceMotion || previewPresented)
        control("forward.step", "next_step") { playing = false; simulation.selectStage(min(3, simulation.stage + 1)) }
        Spacer()
        Button { playing = false; simulation = .initial(entry.id); physiologyInputs = nil } label: {
          Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44)
        }.accessibilityLabel(t("reset")).help(t("reset"))
      }
  }
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
