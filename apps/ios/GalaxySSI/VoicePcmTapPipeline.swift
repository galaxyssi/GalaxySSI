import AVFoundation
import Foundation

struct VoicePcmTapUpdate {
  var frame: AudioFrame
  var decision: VadDecision
  var endpoint: EndpointUpdate
}

final class VoicePcmTapPipeline {
  private let config: VoiceAudioSessionConfig
  private let store: SpeechSegmentStore
  private let vad: VoiceActivityDetector
  private let endpoint: AdaptiveEndpointDetector
  private let elapsedClock: () -> Int64
  private let lock = NSLock()
  private var sequence: Int64 = 0

  init(
    config: VoiceAudioSessionConfig,
    vad: VoiceActivityDetector = AdaptiveSpeechVad(),
    elapsedClock: @escaping () -> Int64 = VoicePcmTapPipeline.defaultElapsedClock
  ) {
    self.config = config
    self.store = InMemorySpeechSegmentStore(
      sampleRateHz: config.capture.sampleRateHz,
      maxDurationMs: config.capture.maxDurationMs + 1_000
    )
    self.vad = vad
    self.endpoint = AdaptiveEndpointDetector(
      sampleRateHz: config.capture.sampleRateHz,
      config: config.endpoint,
      autoEndpoint: config.autoEndpoint
    )
    self.elapsedClock = elapsedClock
  }

  func accept(buffer: AVAudioPCMBuffer) -> VoicePcmTapUpdate? {
    let samples = Self.int16Samples(from: buffer)
    guard !samples.isEmpty else { return nil }
    return locked {
      let frame = AudioFrame(
        sequence: sequence,
        captureTimeNanos: elapsedClock(),
        samples: samples
      )
      sequence += 1
      store.append(frame)
      let decision = vad.accept(frame)
      let endpointUpdate = endpoint.accept(frame, vad: decision)
      if endpointUpdate.speechStarted {
        store.markSpeechStart(sequence: frame.sequence)
      }
      if endpointUpdate.speechEndedCandidate {
        store.markSpeechEnd(sequence: frame.sequence)
      }
      return VoicePcmTapUpdate(frame: frame, decision: decision, endpoint: endpointUpdate)
    }
  }

  func snapshot() -> PcmSnapshot {
    store.snapshot(
      segment: SegmentRange(
        preRollMs: config.endpoint.preRollMs,
        postRollMs: config.endpoint.postRollMs
      )
    )
  }

  func snapshotWindow(maxDurationMs: Int64) -> PcmSnapshot {
    store.snapshotWindow(
      maxDurationMs: maxDurationMs,
      segment: SegmentRange(
        preRollMs: config.endpoint.preRollMs,
        postRollMs: config.endpoint.postRollMs
      )
    )
  }

  func reset() {
    locked {
      sequence = 0
      store.clear()
      vad.reset()
      endpoint.reset()
    }
  }

  deinit {
    store.clear()
  }

  static func int16Samples(from buffer: AVAudioPCMBuffer) -> [Int16] {
    let frameCount = Int(buffer.frameLength)
    let channelCount = max(1, Int(buffer.format.channelCount))
    guard frameCount > 0 else { return [] }
    if let channels = buffer.floatChannelData {
      return (0..<frameCount).map { frameIndex in
        var mixed: Float = 0
        for channel in 0..<channelCount {
          mixed += channels[channel][frameIndex]
        }
        return int16Sample(fromUnitFloat: mixed / Float(channelCount))
      }
    }
    if let channels = buffer.int16ChannelData {
      return (0..<frameCount).map { frameIndex in
        var mixed = 0
        for channel in 0..<channelCount {
          mixed += Int(channels[channel][frameIndex])
        }
        return clampedInt16(mixed / channelCount)
      }
    }
    return []
  }

  private static func int16Sample(fromUnitFloat value: Float) -> Int16 {
    let clipped = min(max(value, -1), 1)
    return clampedInt16(Int((clipped * Float(Int16.max)).rounded()))
  }

  private static func clampedInt16(_ value: Int) -> Int16 {
    Int16(min(max(value, Int(Int16.min)), Int(Int16.max)))
  }

  private static func defaultElapsedClock() -> Int64 {
    Int64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
  }

  private func locked<T>(_ action: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return action()
  }
}
