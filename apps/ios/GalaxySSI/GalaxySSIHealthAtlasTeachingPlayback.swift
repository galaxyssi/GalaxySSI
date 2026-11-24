import SwiftUI

struct GalaxySSIHealthAtlasTeachingPlaybackState: Equatable {
  private(set) var offset = 1.0
  private(set) var startedAt: Date?
  var isPlaying: Bool { startedAt != nil }
  func phase(at date: Date, duration: Double) -> Double {
    guard duration.isFinite, duration > 0 else { return 1 }
    return min(1, max(0, offset + (startedAt.map { date.timeIntervalSince($0) / duration } ?? 0)))
  }
  mutating func start(at date: Date, duration: Double, allowed: Bool) {
    guard allowed, duration.isFinite, duration > 0, !isPlaying else { return }
    if offset >= 1 { offset = 0 }
    startedAt = date
  }
  mutating func pause(at date: Date, duration: Double) {
    offset = phase(at: date, duration: duration); startedAt = nil
  }
  mutating func seek(_ position: Double) {
    guard position.isFinite else { return }
    startedAt = nil; offset = min(1, max(0, position))
  }
  mutating func showTarget() { startedAt = nil; offset = 1 }
}

struct GalaxySSIHealthAtlasTeachingPlayback<Artwork: View>: View {
  let caption: String
  let playLabel: String
  let pauseLabel: String
  let duration: Double
  let modelKey: [Int]
  let resetToken: Int
  let playIdentifier: String
  let diagramIdentifier: String
  let diagramDescription: String
  let heightRatio: CGFloat
  var maximumHeight: CGFloat = 180
  var positionLabel: String? = nil
  var positionIdentifier: String? = nil
  let artwork: (Double) -> Artwork
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var playback = GalaxySSIHealthAtlasTeachingPlaybackState()
  @State private var measuredWidth: CGFloat = 340
  private var canPlay: Bool { duration.isFinite && duration > 0 && !reduceMotion && scenePhase == .active }
  private func pause(at date: Date = Date()) { playback.pause(at: date, duration: duration) }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(caption).font(.subheadline).bold().fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 8)
        Button {
          if playback.isPlaying { pause() }
          else { playback.start(at: Date(), duration: duration, allowed: canPlay) }
        } label: {
          Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill").frame(width: 44, height: 44)
        }.disabled(!canPlay).opacity(canPlay ? 1 : 0.4)
          .accessibilityIdentifier(playIdentifier)
          .accessibilityLabel(playback.isPlaying ? pauseLabel : playLabel)
          .help(playback.isPlaying ? pauseLabel : playLabel)
      }
      TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playback.isPlaying)) { timeline in
        let fraction = playback.phase(at: timeline.date, duration: duration)
        VStack(spacing: 8) {
          artwork(fraction).frame(height: min(measuredWidth * heightRatio, maximumHeight))
            .background(GeometryReader { proxy in
              Color.clear.preference(key: GalaxySSIHealthAtlasTeachingWidth.self, value: proxy.size.width)
            })
            .onPreferenceChange(GalaxySSIHealthAtlasTeachingWidth.self) { width in
              if width.isFinite, width > 0, width != measuredWidth { measuredWidth = width }
            }
            .clipped().accessibilityElement(children: .ignore)
            .accessibilityIdentifier(diagramIdentifier).accessibilityLabel(diagramDescription)
          if let positionLabel {
            Slider(value: Binding(get: { fraction }, set: { playback.seek($0) }), in: 0...1, step: 0.001,
              onEditingChanged: { editing in if editing { pause() } })
              .accessibilityLabel(positionLabel).accessibilityIdentifier(positionIdentifier ?? "")
          }
        }.onChange(of: fraction) { value in
          if value >= 1, playback.isPlaying { pause(at: timeline.date) }
        }
      }
    }.onChange(of: modelKey) { _ in playback.showTarget() }
      .onChange(of: duration) { _ in playback.showTarget() }
      .onChange(of: resetToken) { _ in playback.showTarget() }
      .onChange(of: reduceMotion) { value in if value { pause() } }
      .onChange(of: scenePhase) { value in if value != .active { pause() } }
      .onDisappear { pause() }
  }
}

private struct GalaxySSIHealthAtlasTeachingWidth: PreferenceKey {
  static let defaultValue: CGFloat = 340
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
