import SwiftUI

struct GalaxySSIHealthAtlasFunctionPlayer<Artwork: View>: View {
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let language: String
  let previewPresented: Bool
  @Binding private var phase: Double
  let onPhase: (Double) -> Void
  let artwork: (Double) -> Artwork
  @Environment(\.scenePhase) private var scene
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.openURL) private var openURL
  @State private var position: Double
  @State private var playing = false
  @State private var lastTick: TimeInterval?
  private let timer = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect()
  init(story: GalaxySSIHealthAtlasFunctionCatalogue.Story, language: String, phase: Binding<Double>,
       previewPresented: Bool, onPhase: @escaping (Double) -> Void, @ViewBuilder artwork: @escaping (Double) -> Artwork) {
    self.story = story; self.language = language; _phase = phase; self.previewPresented = previewPresented
    self.onPhase = onPhase; self.artwork = artwork
    _position = State(initialValue: GalaxySSIHealthAtlasFunctionCatalogue.Story.safePhase(phase.wrappedValue))
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(text(story.title)).font(.headline).fixedSize(horizontal: false, vertical: true)
      HStack {
        control("backward.step", "previous_step") { skip(-1) }
        control(playing ? "pause.fill" : "play.fill", playing ? "pause" : "play", action: toggle)
        control("forward.step", "next_step") { skip(1) }
        Spacer()
        Button { stop(); setPosition(0); commit() } label: {
          Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44)
        }.accessibilityLabel(text("health_atlas_reset")).help(text("health_atlas_reset"))
          .accessibilityIdentifier("atlas-function-reset")
      }.disabled(previewPresented).accessibilityIdentifier("atlas-function-controls")
      Slider(value: Binding(get: { position }, set: setPosition), in: 0...1, onEditingChanged: { editing in
        stop(); if !editing { commit() }
      }).accessibilityLabel(text("health_atlas_phase")).accessibilityIdentifier("atlas-function-position")
      artwork(position).modifier(GalaxySSIHealthAtlasFunctionViewport(storyID: story.id))
      let index = story.chapter(position), chapter = story.chapters[index]
      Text(String(format: text("health_atlas_stage"), Int64(index + 1), Int64(story.chapters.count), text(chapter.title)))
        .font(.headline).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("atlas-function-chapter")
      Text(text(chapter.caption)).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("atlas-function-caption")
      Text(text(story.scope)).font(.footnote).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
      ForEach(Array(story.references.enumerated()), id: \.offset) { index, reference in
        Button { pause(); openURL(reference.url) } label: {
          HStack {
            Text(text(reference.title)).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Image(systemName: "arrow.up.right").accessibilityHidden(true)
          }.frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("atlas-function-source-" + String(index))
      }
    }.accessibilityIdentifier("atlas-function-player")
      .onAppear { onPhase(position) }
      .onChange(of: phase) { value in
        let next = GalaxySSIHealthAtlasFunctionCatalogue.Story.safePhase(value)
        if next != position { stop(); setPosition(next) }
      }
      .onReceive(timer) { _ in
        guard playing, scene == .active, !reduceMotion, !previewPresented else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let lastTick {
          let next = Self.advance(position, elapsed: now - lastTick, durationMs: story.durationMs)
          setPosition(next)
          if next >= 1 { pause() }
        }
        if playing { lastTick = now }
      }
      .onChange(of: scene) { _ in pause() }
      .onChange(of: reduceMotion) { _ in pause() }
      .onChange(of: previewPresented) { if $0 { pause() } }
      .onDisappear { pause() }
  }
  nonisolated static func advance(_ phase: Double, elapsed: Double, durationMs: Int) -> Double {
    guard elapsed.isFinite, durationMs > 0 else { return GalaxySSIHealthAtlasFunctionCatalogue.Story.safePhase(phase) }
    return min(1, GalaxySSIHealthAtlasFunctionCatalogue.Story.safePhase(phase) + max(0, elapsed) * 1000 / Double(durationMs))
  }
  private func stop() { playing = false; lastTick = nil }
  private func setPosition(_ value: Double) {
    position = GalaxySSIHealthAtlasFunctionCatalogue.Story.safePhase(value)
    onPhase(position)
  }
  private func commit() { phase = position; onPhase(position) }
  private func pause() { stop(); commit() }
  private func skip(_ direction: Int) { stop(); setPosition(story.startOf(story.chapter(position) + direction)); commit() }
  private func toggle() {
    if playing { pause(); return }
    if reduceMotion { skip(1); return }
    if position >= 1 { setPosition(0) }
    lastTick = ProcessInfo.processInfo.systemUptime; playing = true
  }
  private func control(_ symbol: String, _ key: String, action: @escaping () -> Void) -> some View {
    Button(action: action) { Image(systemName: symbol).frame(width: 44, height: 44) }
      .accessibilityLabel(GalaxySSIHealthBodyText.string(key, language: language))
      .help(GalaxySSIHealthBodyText.string(key, language: language))
      .accessibilityIdentifier("atlas-function-" + (key == "previous_step" ? "previous" : key == "next_step" ? "next" : "play"))
  }
  private func text(_ key: String) -> String { GalaxySSIHealthAtlasFunctionText.get(key, language) }
}
