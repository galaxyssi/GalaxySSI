import Foundation

enum VoiceWhisperBenchmarkRunnerError: LocalizedError, Equatable {
  case deferred(String)

  var errorDescription: String? {
    switch self {
    case .deferred(let detail):
      return detail
    }
  }
}

final class VoiceWhisperBenchmarkRunner {
  private let runtimeFactory: () -> VoiceStatefulLocalWhisperRuntime
  private let keyFactory: (VoiceWhisperModelProfile, String) -> VoiceWhisperBenchmarkKey
  private let snapshot: () -> VoiceWhisperBenchmarkSystemSnapshot
  private let highPerformanceCoreCount: () -> Int
  private let verifyModel: (VoiceWhisperModelProfile) throws -> Void
  private let elapsedMillis: () -> Int64
  private let clockMillis: () -> Int64
  private let store: VoiceWhisperBenchmarkStore
  private let plan: VoiceWhisperBenchmarkPlan

  init(
    runtimeFactory: @escaping () -> VoiceStatefulLocalWhisperRuntime,
    keyFactory: @escaping (VoiceWhisperModelProfile, String) -> VoiceWhisperBenchmarkKey,
    snapshot: @escaping () -> VoiceWhisperBenchmarkSystemSnapshot,
    highPerformanceCoreCount: @escaping () -> Int,
    verifyModel: @escaping (VoiceWhisperModelProfile) throws -> Void,
    elapsedMillis: @escaping () -> Int64 = { Int64(ProcessInfo.processInfo.systemUptime * 1_000) },
    clockMillis: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) },
    store: VoiceWhisperBenchmarkStore,
    plan: VoiceWhisperBenchmarkPlan = VoiceWhisperBenchmarkPlan()
  ) {
    self.runtimeFactory = runtimeFactory
    self.keyFactory = keyFactory
    self.snapshot = snapshot
    self.highPerformanceCoreCount = highPerformanceCoreCount
    self.verifyModel = verifyModel
    self.elapsedMillis = elapsedMillis
    self.clockMillis = clockMillis
    self.store = store
    self.plan = plan
  }

  func run(
    profile: VoiceWhisperModelProfile,
    audio: VoiceWhisperBenchmarkAudio,
    force: Bool = false,
    onProgress: @escaping (VoiceWhisperBenchmarkProgress) -> Void = { _ in }
  ) async throws -> VoiceWhisperBenchmarkRecord {
    try Task.checkCancellation()
    let key = keyFactory(profile, audio.version)
    if !force, let cached = store.find(key) {
      return cached
    }

    let highPerformanceCores = min(max(highPerformanceCoreCount(), 1), 16)
    let threadCandidates = VoiceWhisperThreadSearch.candidates(
      highPerformanceCoreCount: highPerformanceCores
    )
    let totalSteps = plan.totalSteps(threadCandidateCount: threadCandidates.count)
    var completedSteps = 0

    func progress(
      _ stage: VoiceWhisperBenchmarkStage,
      threadCount: Int? = nil,
      detail: String = ""
    ) {
      onProgress(
        VoiceWhisperBenchmarkProgress(
          stage: stage,
          completedSteps: completedSteps,
          totalSteps: totalSteps,
          threadCount: threadCount,
          detail: detail
        )
      )
    }

    progress(.verifying)
    try Task.checkCancellation()
    let verificationStarted = elapsedMillis()
    try verifyModel(profile)
    let verificationDurationMillis = max(elapsedMillis() - verificationStarted, 0)
    completedSteps += 1

    progress(.checkingDevice)
    let initialSnapshot = snapshot()
    if let failure = VoiceWhisperBenchmarkRecordBuilder.preflightFailure(
      profile: profile,
      system: initialSnapshot
    ) {
      let record = VoiceWhisperBenchmarkRecordBuilder.terminalRecord(
        key: key,
        profile: profile,
        level: .remoteRecommended,
        reason: failure,
        verificationDurationMillis: verificationDurationMillis,
        highPerformanceCoreCount: highPerformanceCores,
        threadCandidates: threadCandidates,
        fallbackThermalStatus: initialSnapshot.thermalStatus,
        createdAtEpochMillis: clockMillis()
      )
      try store.save(record)
      return record
    }
    guard VoiceWhisperBenchmarkRecordBuilder.thermalAllowsBenchmark(initialSnapshot) else {
      throw VoiceWhisperBenchmarkRunnerError.deferred(
        "Benchmark paused until the device cools below MODERATE"
      )
    }
    completedSteps += 1

    var measurements: [VoiceWhisperBenchmarkMeasurement] = []
    var loadSequence = 0
    for threadCount in threadCandidates {
      try Task.checkCancellation()
      let runtime = runtimeFactory()
      do {
        progress(.searchingThreads, threadCount: threadCount)
        let loaded = try await runtime.load(
          profile: profile,
          options: try VoiceWhisperLoadOptions(threadCount: threadCount, warmUp: true)
        )
        let loadKind: VoiceWhisperBenchmarkLoadKind = loadSequence == 0 ? .cold : .hot
        loadSequence += 1
        for duration in plan.candidateAudioDurationsMillis {
          for _ in 0..<plan.candidateIterations {
            try Task.checkCancellation()
            try ensureThermalAllowsBenchmark()
            measurements.append(
              try await measureDecode(
                runtime: runtime,
                audio: audio,
                durationMillis: duration,
                threadCount: threadCount,
                loadKind: loadKind,
                loaded: loaded
              )
            )
            completedSteps += 1
            progress(.searchingThreads, threadCount: threadCount)
          }
        }
        await runtime.unload(reason: .userRequest)
        runtime.close()
      } catch {
        await runtime.unload(reason: .loadFailed)
        runtime.close()
        throw error
      }
    }

    let bestThreadCount = try VoiceWhisperThreadSearch.selectBest(measurements: measurements)
    try Task.checkCancellation()
    let stabilityRuntime = runtimeFactory()
    var stabilityMeasurements: [VoiceWhisperBenchmarkMeasurement] = []
    var abortLatencies: [Int64] = []
    do {
      progress(.stability, threadCount: bestThreadCount)
      let loaded = try await stabilityRuntime.load(
        profile: profile,
        options: try VoiceWhisperLoadOptions(threadCount: bestThreadCount, warmUp: true)
      )
      let loadKind: VoiceWhisperBenchmarkLoadKind = loadSequence == 0 ? .cold : .hot
      for _ in 0..<plan.stabilityIterations {
        try Task.checkCancellation()
        try ensureThermalAllowsBenchmark()
        stabilityMeasurements.append(
          try await measureDecode(
            runtime: stabilityRuntime,
            audio: audio,
            durationMillis: plan.stabilityAudioDurationMillis,
            threadCount: bestThreadCount,
            loadKind: loadKind,
            loaded: loaded
          )
        )
        completedSteps += 1
        progress(.stability, threadCount: bestThreadCount)
      }

      progress(.cancellation, threadCount: bestThreadCount)
      for _ in 0..<plan.abortIterations {
        try Task.checkCancellation()
        stabilityRuntime.requestAbortAll(.userStop)
        abortLatencies.append(0)
        completedSteps += 1
        progress(.cancellation, threadCount: bestThreadCount)
      }
      await stabilityRuntime.unload(reason: .userRequest)
      stabilityRuntime.close()
    } catch {
      await stabilityRuntime.unload(reason: .loadFailed)
      stabilityRuntime.close()
      throw error
    }

    progress(.certifying, threadCount: bestThreadCount)
    try Task.checkCancellation()
    let allMeasurements = measurements + stabilityMeasurements
    let record = VoiceWhisperBenchmarkRecordBuilder.certify(
      key: key,
      profile: profile,
      measurements: allMeasurements,
      stabilityMeasurements: stabilityMeasurements,
      verificationDurationMillis: verificationDurationMillis,
      abortLatenciesMillis: abortLatencies,
      highPerformanceCoreCount: highPerformanceCores,
      threadCandidates: threadCandidates,
      threadCount: bestThreadCount,
      createdAtEpochMillis: clockMillis()
    )
    try store.save(record)
    completedSteps = totalSteps
    progress(.complete, threadCount: bestThreadCount)
    return record
  }

  private func measureDecode(
    runtime: VoiceStatefulLocalWhisperRuntime,
    audio: VoiceWhisperBenchmarkAudio,
    durationMillis: Int64,
    threadCount: Int,
    loadKind: VoiceWhisperBenchmarkLoadKind,
    loaded: VoiceWhisperLoadedModel
  ) async throws -> VoiceWhisperBenchmarkMeasurement {
    let start = snapshot()
    let executionMode: VoiceWhisperExecutionMode = durationMillis <= firstPartialProbeDurationMillis
      ? .realtimePartial
      : .finalOnly
    let session = try await runtime.createSession(
      config: try VoiceLocalWhisperSessionConfig(
        language: audio.language,
        noContext: true,
        singleSegment: executionMode == .realtimePartial,
        mode: executionMode
      )
    )
    let result: VoiceNativeWhisperResult
    do {
      result = try await session.decode(
        try VoiceWhisperDecodeRequest(
          pcm16: audio.window(durationMillis: durationMillis),
          mode: executionMode
        )
      )
    } catch {
      session.close()
      throw error
    }
    session.close()
    guard result.successful else {
      throw VoiceWhisperRuntimeFailure.decodeFailed(result.message ?? String(describing: result.code))
    }
    let end = snapshot()
    let timings = result.timings
    return VoiceWhisperBenchmarkMeasurement(
      threadCount: threadCount,
      loadKind: loadKind,
      audioDurationMillis: max(timings.audioMillis, durationMillis),
      decodeDurationMillis: max(Int64(timings.totalMillis.rounded()), 0),
      realTimeFactor: timings.realTimeFactor,
      loadDurationMillis: loaded.loadDurationMillis,
      warmUpDurationMillis: max(Int64(loaded.warmUpTimings?.totalMillis.rounded() ?? 0), 0),
      peakPssBytes: max(start.pssBytes, end.pssBytes),
      peakRssBytes: max(start.rssBytes, end.rssBytes),
      peakNativeAllocatedBytes: max(start.nativeAllocatedBytes, end.nativeAllocatedBytes),
      cpuTimeMillis: max(end.cpuTimeMillis - start.cpuTimeMillis, 0),
      energyDeltaNwh: energyDelta(start.energyCounterNwh, end.energyCounterNwh),
      firstPartialLatencyMillis: executionMode == .realtimePartial ? max(Int64(timings.totalMillis.rounded()), 0) : 0,
      finalTailLatencyMillis: executionMode == .finalOnly ? max(Int64(timings.totalMillis.rounded()), 0) : 0,
      batteryTemperatureStartCelsius: start.batteryTemperatureCelsius,
      batteryTemperatureEndCelsius: end.batteryTemperatureCelsius,
      thermalStatusStart: start.thermalStatus,
      thermalStatusEnd: max(start.thermalStatus, end.thermalStatus),
      transcriptCorrect: VoiceWhisperBenchmarkRecordBuilder.transcriptMatches(
        result.text,
        expectedTokens: audio.expectedTokens
      )
    )
  }

  private func ensureThermalAllowsBenchmark() throws {
    guard VoiceWhisperBenchmarkRecordBuilder.thermalAllowsBenchmark(snapshot()) else {
      throw VoiceWhisperBenchmarkRunnerError.deferred(
        "Benchmark paused because the device reached MODERATE thermal pressure"
      )
    }
  }

  private func energyDelta(_ start: Int64?, _ end: Int64?) -> Int64? {
    guard let start, let end else {
      return nil
    }
    return abs(end - start)
  }

  private let firstPartialProbeDurationMillis: Int64 = 3_000
}
