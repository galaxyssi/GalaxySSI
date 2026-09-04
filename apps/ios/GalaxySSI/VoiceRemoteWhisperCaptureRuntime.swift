import Foundation

@MainActor
final class VoiceRemoteWhisperCaptureRuntime {
  static let shared = VoiceRemoteWhisperCaptureRuntime()

  private weak var coordinator: MessageCoordinator?

  private init() {}

  func bind(coordinator: MessageCoordinator) {
    self.coordinator = coordinator
  }

  var isAvailable: Bool {
    guard VoiceFeatureFlags.isRemoteWhisperNodeEnabled(),
          let coordinator,
          coordinator.store.voiceSettings.normalized.remoteWhisperAllowed else {
      return false
    }
    return !coordinator.verifiedRemoteWhisperNodes.isEmpty
  }

  func transcribe(
    sessionID: String,
    transcriptID: String,
    snapshot: PcmSnapshot,
    language: String
  ) async throws -> VoiceRemoteWhisperTranscript {
    guard let coordinator else {
      throw VoiceRemoteWhisperClientError.failed(
        code: "remote_whisper_runtime_unavailable",
        message: "Remote Whisper transport is unavailable."
      )
    }
    var normalizedSnapshot = VoiceRemoteWhisperPcmConverter.convertTo16k(snapshot)
    defer {
      normalizedSnapshot.samples = Array(repeating: 0, count: normalizedSnapshot.samples.count)
    }
    return try await coordinator.transcribeWithRemoteWhisper(
      voiceSessionID: sessionID,
      transcriptID: transcriptID,
      pcm16: normalizedSnapshot.samples,
      sampleRateHz: normalizedSnapshot.sampleRateHz,
      language: language
    )
  }
}

private enum VoiceRemoteWhisperPcmConverter {
  static func convertTo16k(_ snapshot: PcmSnapshot) -> PcmSnapshot {
    let targetRateHz = 16_000
    guard !snapshot.samples.isEmpty,
          snapshot.sampleRateHz > 0,
          snapshot.sampleRateHz != targetRateHz else {
      return snapshot
    }
    let outputCount = max(
      1,
      Int(Int64(snapshot.samples.count) * Int64(targetRateHz) / Int64(snapshot.sampleRateHz))
    )
    let samples = (0..<outputCount).map { index -> Int16 in
      let sourcePosition = Double(index) * Double(snapshot.sampleRateHz) / Double(targetRateHz)
      let left = min(max(Int(sourcePosition.rounded(.down)), 0), snapshot.samples.count - 1)
      let right = min(left + 1, snapshot.samples.count - 1)
      let fraction = sourcePosition - Double(left)
      let interpolated = Double(snapshot.samples[left]) +
        (Double(snapshot.samples[right]) - Double(snapshot.samples[left])) * fraction
      return Int16(min(max(Int(interpolated.rounded()), Int(Int16.min)), Int(Int16.max)))
    }
    return PcmSnapshot(
      samples: samples,
      sampleRateHz: targetRateHz,
      speechDetected: snapshot.speechDetected,
      speechStartSample: nil,
      speechEndSampleExclusive: nil,
      captureStartSample: 0,
      captureEndSampleExclusive: Int64(samples.count)
    )
  }
}
