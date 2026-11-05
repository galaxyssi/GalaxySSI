import Foundation

/// Scoped to a Voice surface. The input tap never waits on the playback owner.
final class VoicePlaybackEchoReference {
  static let sampleRate = 4_000
  static let maximumFrames = sampleRate * 60
  private static let tailDuration: TimeInterval = 0.35

  private struct Clip {
    var id: UUID
    var samples: [Float]
    var started: TimeInterval
    var offset = 0

    mutating func wipe() {
      for index in samples.indices { samples[index] = 0 }
      samples.removeAll(keepingCapacity: false)
    }
  }

  private let lock = NSLock()
  private var active: Clip?
  private var tail: Clip?
  private var tailUntil: TimeInterval = 0

  deinit { clear() }

  func begin(id: UUID, samples: [Float], at now: TimeInterval) {
    lock.lock()
    defer { lock.unlock() }
    active?.wipe()
    active = Clip(id: id, samples: Array(samples.prefix(Self.maximumFrames)), started: now)
  }

  func end(id: UUID, played: TimeInterval, at now: TimeInterval) {
    lock.lock()
    guard let activeID = active?.id, activeID == id else { lock.unlock(); return }
    let end = played.isFinite && played > 0 && played <= 60
      ? min(active?.samples.count ?? 0, Int(played * Double(Self.sampleRate))) : 0
    let start = max(0, end - Int(Self.tailDuration * Double(Self.sampleRate)))
    tail?.wipe()
    if let active, end > start {
      tail = Clip(id: id, samples: Array(active.samples[start..<end]), started: active.started, offset: start)
      tailUntil = now + Self.tailDuration
    } else {
      tail = nil
    }
    active?.wipe()
    active = nil
    lock.unlock()
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.tailDuration) { [weak self] in
      self?.expire(id: id)
    }
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    active?.wipe()
    tail?.wipe()
    active = nil
    tail = nil
  }

  private func expire(id: UUID) {
    lock.lock()
    defer { lock.unlock() }
    guard tail?.id == id else { return }
    tail?.wipe()
    tail = nil
  }

  func matches(_ input: [Int16], rate: Double, endingAt now: TimeInterval) -> Bool {
    guard rate >= Double(Self.sampleRate), rate <= 192_000, now.isFinite,
          input.count >= Int(rate / 100), input.count <= Int(rate / 8),
          lock.try() else { return false }
    defer { lock.unlock() }
    guard active != nil || (tail != nil && now <= tailUntil) else { return false }

    let step = rate / Double(Self.sampleRate)
    let count = Int(Double(input.count) / step)
    var frame = [Float]()
    frame.reserveCapacity(count)
    for index in 0..<count {
      let first = Int(Double(index) * step)
      let end = min(input.count, Int(Double(index + 1) * step))
      let sum = input[first..<end].reduce(0) { $0 + Int($1) }
      frame.append(Float(sum) / Float(end - first) / 32_768)
    }
    let mean = frame.reduce(0, +) / Float(count)
    var energy: Float = 0
    for index in frame.indices {
      frame[index] -= mean
      energy += frame[index] * frame[index]
    }
    guard energy > Float(count) * 0.000001 else { return false }
    if let active, matches(frame, energy: energy, clip: active, endingAt: now) { return true }
    if let tail, now <= tailUntil { return matches(frame, energy: energy, clip: tail, endingAt: now) }
    return false
  }

  private func matches(_ frame: [Float], energy: Float, clip: Clip, endingAt now: TimeInterval) -> Bool {
    let position = now - clip.started
    guard position >= 0, position <= 61 else { return false }
    let end = Int(position * Double(Self.sampleRate)) - clip.offset
    let earliest = max(0, end - frame.count - Self.sampleRate / 3)
    let latest = min(clip.samples.count - frame.count, end - frame.count)
    guard earliest <= latest else { return false }
    let count = Float(frame.count)
    for offset in stride(from: earliest, through: latest, by: 2) {
      var dot: Float = 0
      var sum: Float = 0
      var square: Float = 0
      for index in frame.indices {
        let reference = clip.samples[offset + index]
        dot += frame[index] * reference
        sum += reference
        square += reference * reference
      }
      let referenceEnergy = square - sum * sum / count
      if referenceEnergy > count * 0.000001, dot * dot > 0.90 * 0.90 * energy * referenceEnergy {
        return true
      }
    }
    return false
  }
}
