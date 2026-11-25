import SwiftUI

@MainActor
struct GalaxySSIHealthAtlasFunctionPlayer<Artwork: View>: View {
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let language: String
  let previewPresented: Bool
  @Binding private var phase: Double
  let onPhase: (Double) -> Void
  let artwork: (Double) -> Artwork
  let showTitle: Bool
  let playbackID: String
  let related: [GalaxySSIHealthAtlasRelatedAction]
  @EnvironmentObject private var playback: GalaxySSIHealthAtlasPlayback
  @Environment(\.scenePhase) private var scene
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var position: Double
  @State private var clock: GalaxySSIHealthAtlasChapterClock
  private var playing: Bool { clock.playing }
  private let timer = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect()
  init(story: GalaxySSIHealthAtlasFunctionCatalogue.Story, language: String, phase: Binding<Double>,
       previewPresented: Bool, showTitle: Bool = true, playbackID: String,
       related: [GalaxySSIHealthAtlasRelatedAction] = [], onPhase: @escaping (Double) -> Void, @ViewBuilder artwork: @escaping (Double) -> Artwork) {
    self.story = story; self.language = language; _phase = phase; self.previewPresented = previewPresented
    self.onPhase = onPhase; self.artwork = artwork
    self.showTitle = showTitle; self.playbackID = playbackID
    self.related = related
    _clock = State(initialValue: .init(chapters: story.chapters.count, phase: phase.wrappedValue))
    _position = State(initialValue: GalaxySSIHealthAtlasFunctionCatalogue.Story.safePhase(phase.wrappedValue))
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      GalaxySSIHealthAtlasFunctionScene(story: story, language: language, phase: position, showTitle: showTitle,
        artwork: artwork(reduceMotion ? story.startOf(story.chapter(position)) : position)
          .modifier(GalaxySSIHealthAtlasFunctionViewport(storyID: story.id))
          .contentShape(Rectangle()).onTapGesture { if !previewPresented { toggle() } }
          .accessibilityAction(named: Text(GalaxySSIHealthBodyText.string(playing ? "pause" : "play", language: language))) {
            if !previewPresented { toggle() }
          })
      Slider(value: Binding(get: { position }, set: setPosition), in: 0...1, onEditingChanged: { editing in
        pause(); if !editing { commit() }
      }).accessibilityLabel(text("health_atlas_phase")).accessibilityIdentifier("atlas-function-position")
      HStack {
        control("backward.step", "previous_step") { skip(-1) }
        control(playing ? "pause.fill" : "play.fill", playing ? "pause" : "play", action: toggle)
        control("forward.step", "next_step") { skip(1) }
        Spacer()
        GalaxySSIHealthAtlasFunctionPlaybackMenu(story: story, language: language, phase: position,
          seek: { stop(); setPosition($0); commit() }, pause: pause, related: related)
      }.disabled(previewPresented).accessibilityIdentifier("atlas-function-controls")
    }.accessibilityIdentifier("atlas-function-player")
      .onAppear { onPhase(position) }
      .onChange(of: phase) { value in
        let next = GalaxySSIHealthAtlasFunctionCatalogue.Story.safePhase(value)
        if next != position { stop(); setPosition(next) }
      }
      .onReceive(timer) { _ in
        guard playing, scene == .active, !previewPresented else { return }
        guard playback.owner == playbackID else { pause(at: playback.changedAt); return }
        let next = clock.sample(GalaxySSIHealthAtlasChapterClock.now)
        if !reduceMotion || story.chapter(next) != story.chapter(position) || !clock.playing { publish(next) }
        if !clock.playing { publish(next); commit(); playback.release(playbackID) }
      }
      .onChange(of: playback.owner) { if playing, $0 != playbackID { pause(at: playback.changedAt) } }
      .onChange(of: scene) { _ in pause() }
      .onChange(of: reduceMotion) { _ in pause() }
      .onChange(of: previewPresented) { if $0 { pause() } }
      .onDisappear { pause() }
  }
  private func stop() { clock.seek(position); playback.release(playbackID) }
  private func setPosition(_ value: Double) {
    clock.seek(value)
    publish(value)
  }
  private func publish(_ value: Double) {
    position = GalaxySSIHealthAtlasFunctionCatalogue.Story.safePhase(value)
    onPhase(position)
  }
  private func commit() { phase = position; onPhase(position) }
  private func pause(at now: Int64) {
    if clock.playing { clock.pause(now); publish(clock.sample(now)) }
    playback.release(playbackID); commit()
  }
  private func pause() { pause(at: GalaxySSIHealthAtlasChapterClock.now) }
  private func skip(_ direction: Int) { pause(); setPosition(story.startOf(story.chapter(position) + direction)); commit() }
  private func toggle() {
    if playing { pause(); return }
    guard !previewPresented, scene == .active else { return }
    let now = GalaxySSIHealthAtlasChapterClock.now
    playback.claim(playbackID, now: now, pause: { pause(at: $0) })
    clock.resume(now); publish(clock.sample(now))
  }
  private func control(_ symbol: String, _ key: String, action: @escaping () -> Void) -> some View {
    Button(action: action) { Image(systemName: symbol).frame(width: 44, height: 44) }
      .accessibilityLabel(GalaxySSIHealthBodyText.string(key, language: language))
      .help(GalaxySSIHealthBodyText.string(key, language: language))
      .accessibilityIdentifier("atlas-function-" + (key == "previous_step" ? "previous" : key == "next_step" ? "next" : "play"))
  }
  private func text(_ key: String) -> String { GalaxySSIHealthAtlasFunctionText.get(key, language) }
}
