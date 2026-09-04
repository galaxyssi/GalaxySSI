import Foundation

typealias VoiceWhisperRuntimeThreadCountProvider = (
  _ profile: VoiceWhisperModelProfile,
  _ request: VoiceScheduledWhisperDecode
) -> Int

final class VoiceWhisperRuntimeDecodeSchedulerAdapter {
  private let runtime: VoiceStatefulLocalWhisperRuntime
  private let profileProvider: (String) -> VoiceWhisperModelProfile
  private let threadCountProvider: VoiceWhisperRuntimeThreadCountProvider

  init(
    runtime: VoiceStatefulLocalWhisperRuntime,
    profileProvider: @escaping (String) -> VoiceWhisperModelProfile = { VoiceWhisperModelCatalog.model($0) },
    threadCountProvider: @escaping VoiceWhisperRuntimeThreadCountProvider = VoiceWhisperRuntimeDecodeSchedulerAdapter.defaultThreadCount
  ) {
    self.runtime = runtime
    self.profileProvider = profileProvider
    self.threadCountProvider = threadCountProvider
  }

  func makeScheduler(maxQueueSize: Int = 8) -> VoiceWhisperDecodeScheduler {
    VoiceWhisperDecodeScheduler(
      maxQueueSize: maxQueueSize,
      decoder: { request in
        return try await self.decode(request)
      },
      abortActive: { reason in
        self.requestAbort(reason)
      }
    )
  }

  func decode(_ request: VoiceScheduledWhisperDecode) async throws -> VoiceNativeWhisperResult {
    let profile = profileProvider(request.modelProfileId)
    let options = try VoiceWhisperLoadOptions(
      threadCount: threadCountProvider(profile, request),
      warmUp: false
    )
    _ = try await runtime.load(profile: profile, options: options)
    let config = try VoiceLocalWhisperSessionConfig(
      language: request.language,
      noContext: true,
      mode: request.mode
    )
    let session = try await runtime.createSession(config: config)
    defer { session.close() }
    return try await session.decode(
      try VoiceWhisperDecodeRequest(
        pcm16: request.pcm16,
        sampleRateHz: request.sampleRateHz,
        mode: request.mode
      )
    )
  }

  func requestAbort(_ reason: VoiceWhisperAbortReason) {
    runtime.requestAbortAll(reason)
  }

  private static func defaultThreadCount(
    profile _: VoiceWhisperModelProfile,
    request: VoiceScheduledWhisperDecode
  ) -> Int {
    request.threadCount ?? min(4, max(1, ProcessInfo.processInfo.processorCount))
  }
}
