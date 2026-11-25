import SwiftUI

struct GalaxySSIHealthAtlasChapterClock: Equatable {
  static let stepMilliseconds: Int64 = 5_000
  let length: Int64
  private var elapsed: Int64
  private var startedAt: Int64?
  var playing: Bool { startedAt != nil }
  static var now: Int64 { Int64(ProcessInfo.processInfo.systemUptime * 1_000) }

  init(chapters: Int, phase: Double) {
    precondition(chapters > 0 && chapters <= Int(Int64.max / Self.stepMilliseconds))
    length = Int64(chapters) * Self.stepMilliseconds
    elapsed = 0
    seek(phase)
  }
  private func position(_ now: Int64) -> Int64 {
    guard let startedAt else { return elapsed }
    let delta = now.subtractingReportingOverflow(startedAt)
    let active = delta.overflow ? (now > startedAt ? length : 0) : max(0, delta.partialValue)
    return elapsed + min(length - elapsed, active)
  }
  mutating func resume(_ now: Int64) {
    guard !playing else { return }
    if elapsed == length { elapsed = 0 }
    startedAt = now
  }
  mutating func pause(_ now: Int64) { elapsed = position(now); startedAt = nil }
  mutating func seek(_ phase: Double) {
    let safe = phase.isFinite ? min(1, max(0, phase)) : 0
    let milliseconds = (safe * Double(length)).rounded()
    elapsed = milliseconds >= Double(length) ? length : Int64(milliseconds)
    startedAt = nil
  }
  mutating func sample(_ now: Int64) -> Double {
    let current = position(now)
    if current == length { pause(now) }
    return Double(current) / Double(length)
  }
  func nextStepIn(_ now: Int64) -> Int64 { Self.stepMilliseconds - position(now) % Self.stepMilliseconds }
}

// One owner per Atlas navigation stack; losers pause at the handoff timestamp,
// not at a later timer tick or SwiftUI change notification.
@MainActor
final class GalaxySSIHealthAtlasPlayback: ObservableObject {
  @Published private(set) var owner: String?
  private(set) var changedAt: Int64 = 0
  private var pauseOwner: ((Int64) -> Void)?
  func claim(_ id: String, now: Int64 = GalaxySSIHealthAtlasChapterClock.now, pause: ((Int64) -> Void)? = nil) {
    guard owner != id else { return }
    changedAt = now
    let previous = pauseOwner
    pauseOwner = nil
    previous?(now)
    pauseOwner = pause
    owner = id
  }
  func release(_ id: String) { if owner == id { pauseOwner = nil; owner = nil } }
  func pause() {
    let callback = pauseOwner
    pauseOwner = nil
    changedAt = GalaxySSIHealthAtlasChapterClock.now
    callback?(changedAt)
    owner = nil
  }
}
