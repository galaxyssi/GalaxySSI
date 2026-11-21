import SwiftUI

struct GalaxySSIHealthAtlasSimulationPanel: View {
  let entry: GalaxySSIHealthAtlas.Entry
  let model: GalaxySSIHealthAtlas.Mechanism
  @Binding var simulation: GalaxySSIHealthAtlasSimulation
  @Binding var physiologyInputs: [Int]?
  @Binding var previewPresented: Bool
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scene
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var playing = false
  @State private var lastTick: Date?
  private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
  private var cardiac: Bool { ["cardio", "heart"].contains(entry.id) }
  private var lung: Bool { ["lungs", "respiratory"].contains(entry.id) }
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
      GalaxySSIHealthAtlasPhysiologyPanel(entryID: entry.id, inputs: $physiologyInputs, language: language,
        legacyVentilation: lung ? [simulation.first, simulation.second] : nil)
      #endif
      Text(String(format: t("related_process"), GalaxySSIHealthAtlasText.get(model.title, language))).font(.headline)
      Text(t("process_note")).font(.footnote).foregroundColor(.secondary)
      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
        ForEach(0..<4) { stage in
          Button { playing = false; simulation.phase = Double(stage) / 4 } label: {
            VStack(spacing: 8) {
              Text("\(stage + 1)").font(.headline).frame(width: 32, height: 32)
                .background(stage <= simulation.stage ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.08)).clipShape(Circle())
              Text(GalaxySSIHealthAtlasText.get(model.stages[stage], language)).font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, minHeight: 44).padding(8)
          }.accessibilityLabel(GalaxySSIHealthAtlasText.get(model.stages[stage], language))
            .accessibilityAddTraits(stage == simulation.stage ? .isSelected : [])
        }
      }
      ProgressView(value: simulation.phase).accessibilityLabel(t("phase"))
      Text(String(format: t("stage"), Int64(simulation.stage + 1), Int64(4),
        GalaxySSIHealthAtlasText.get(model.stages[simulation.stage], language)))
      Slider(value: $simulation.phase, in: 0...1, onEditingChanged: { _ in playing = false })
        .accessibilityLabel(t("phase"))
      HStack {
        control("backward.step", "previous_step") { playing = false; simulation.phase = Double(max(0, simulation.stage - 1)) / 4 }
        control(playing ? "pause.fill" : "play.fill", playing ? "pause" : "play") {
          if simulation.phase >= 1 { simulation.phase = 0 }
          playing.toggle(); lastTick = nil
        }.disabled(reduceMotion || previewPresented)
        control("forward.step", "next_step") { playing = false; simulation.phase = Double(min(3, simulation.stage + 1)) / 4 }
        Spacer()
        Button { playing = false; simulation = .initial(entry.id); physiologyInputs = nil } label: {
          Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44)
        }.accessibilityLabel(t("reset")).help(t("reset"))
      }
      if reduceMotion { Text(bodyText("motion_disabled")).font(.caption) }
      Text(t("speed") + " · " + String(format: "%.1f×", simulation.speed))
      Slider(value: $simulation.speed, in: 0.5...2, step: 0.5).accessibilityLabel(t("speed"))
      Text(t("teaching_note")).font(.footnote).foregroundColor(.secondary)
      if cardiac || (lung && !hasPhysiology) {
        Text(t("parameters")).font(.headline)
        parameter(cardiac ? "heart_rate" : "rate", value: $simulation.first, range: cardiac ? 40...160 : 6...30,
          unit: cardiac ? "bpm" : "/min")
        parameter(cardiac ? "stroke_volume" : "tidal", value: $simulation.second,
          range: cardiac ? 30...120 : 200...900, unit: "mL")
        Text(t(cardiac ? "cardiac_output" : "ventilation") + ": " + String(format: "%.2f L/min", simulation.output)).font(.headline)
        Text(t(cardiac ? "cardiac_formula" : "ventilation_formula")).font(.footnote)
      } else if !hasPhysiology { Text(t("qualitative_note")).font(.footnote) }
    }
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
