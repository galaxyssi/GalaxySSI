import Foundation

enum VoiceWhisperBenchmarkPlanningError: LocalizedError, Equatable {
  case invalidAudio
  case missingThreadMeasurements

  var errorDescription: String? {
    switch self {
    case .invalidAudio:
      return "Whisper benchmark audio is invalid."
    case .missingThreadMeasurements:
      return "Whisper benchmark thread search has no measurements."
    }
  }
}

struct VoiceWhisperBenchmarkAudio: Equatable {
  static let sampleRateHz = 16_000
  private static let minimumAudioSeconds = 5

  var version: String
  var pcm16: [Int16]
  var expectedTokens: Set<String>
  var language: String

  init(
    version: String,
    pcm16: [Int16],
    expectedTokens: Set<String>,
    language: String = "zh"
  ) throws {
    let cleanVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanTokens = Set(
      expectedTokens
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    )
    guard !cleanVersion.isEmpty,
          pcm16.count >= Self.sampleRateHz * Self.minimumAudioSeconds,
          !cleanTokens.isEmpty,
          !cleanLanguage.isEmpty else {
      throw VoiceWhisperBenchmarkPlanningError.invalidAudio
    }
    self.version = cleanVersion
    self.pcm16 = pcm16
    self.expectedTokens = cleanTokens
    self.language = cleanLanguage
  }

  func window(durationMillis: Int64) -> [Int16] {
    let requestedFrames = Int(
      min(
        Int64(Int.max),
        max(durationMillis, 1) * Int64(Self.sampleRateHz) / 1_000
      )
    )
    if requestedFrames <= pcm16.count {
      return Array(pcm16.prefix(requestedFrames))
    }
    var padded = pcm16
    padded.append(contentsOf: repeatElement(0, count: requestedFrames - pcm16.count))
    return padded
  }
}

struct VoiceWhisperBenchmarkSystemSnapshot: Codable, Equatable {
  var availableMemoryBytes: Int64
  var systemLowMemory: Bool
  var pssBytes: Int64
  var rssBytes: Int64
  var nativeAllocatedBytes: Int64
  var cpuTimeMillis: Int64
  var energyCounterNwh: Int64?
  var batteryTemperatureCelsius: Double?
  var thermalStatus: Int

  init(
    availableMemoryBytes: Int64,
    systemLowMemory: Bool = false,
    pssBytes: Int64 = 0,
    rssBytes: Int64 = 0,
    nativeAllocatedBytes: Int64 = 0,
    cpuTimeMillis: Int64 = 0,
    energyCounterNwh: Int64? = nil,
    batteryTemperatureCelsius: Double? = nil,
    thermalStatus: Int = 0
  ) {
    self.availableMemoryBytes = max(availableMemoryBytes, 0)
    self.systemLowMemory = systemLowMemory
    self.pssBytes = max(pssBytes, 0)
    self.rssBytes = max(rssBytes, 0)
    self.nativeAllocatedBytes = max(nativeAllocatedBytes, 0)
    self.cpuTimeMillis = max(cpuTimeMillis, 0)
    self.energyCounterNwh = energyCounterNwh.map { max($0, 0) }
    self.batteryTemperatureCelsius = batteryTemperatureCelsius?.isFinite == true ? batteryTemperatureCelsius : nil
    self.thermalStatus = max(thermalStatus, 0)
  }
}

struct VoiceWhisperBenchmarkPlan: Codable, Equatable {
  var candidateAudioDurationsMillis: [Int64]
  var candidateIterations: Int
  var stabilityAudioDurationMillis: Int64
  var stabilityIterations: Int
  var abortIterations: Int
  var metricSampleIntervalMillis: Int64
  var abortDelayMillis: Int64
  var abortTimeoutMillis: Int64

  init(
    candidateAudioDurationsMillis: [Int64] = [3_000, 5_000],
    candidateIterations: Int = 2,
    stabilityAudioDurationMillis: Int64 = 10_000,
    stabilityIterations: Int = 3,
    abortIterations: Int = 3,
    metricSampleIntervalMillis: Int64 = 50,
    abortDelayMillis: Int64 = 50,
    abortTimeoutMillis: Int64 = 5_000
  ) {
    let cleanDurations = candidateAudioDurationsMillis.filter { $0 > 0 }
    self.candidateAudioDurationsMillis = cleanDurations.isEmpty ? [3_000, 5_000] : cleanDurations
    self.candidateIterations = min(max(candidateIterations, 2), 5)
    self.stabilityAudioDurationMillis = max(stabilityAudioDurationMillis, 1)
    self.stabilityIterations = min(max(stabilityIterations, 3), 5)
    self.abortIterations = min(max(abortIterations, 1), 5)
    self.metricSampleIntervalMillis = min(max(metricSampleIntervalMillis, 10), 250)
    self.abortDelayMillis = min(max(abortDelayMillis, 1), 1_000)
    self.abortTimeoutMillis = min(max(abortTimeoutMillis, 500), 15_000)
  }

  func totalSteps(threadCandidateCount: Int) -> Int {
    3 +
      max(threadCandidateCount, 0) * candidateAudioDurationsMillis.count * candidateIterations +
      stabilityIterations +
      abortIterations
  }
}

enum VoiceWhisperBenchmarkStage: String, Codable, Equatable {
  case verifying = "VERIFYING"
  case checkingDevice = "CHECKING_DEVICE"
  case searchingThreads = "SEARCHING_THREADS"
  case stability = "STABILITY"
  case cancellation = "CANCELLATION"
  case certifying = "CERTIFYING"
  case complete = "COMPLETE"
}

struct VoiceWhisperBenchmarkProgress: Codable, Equatable {
  var stage: VoiceWhisperBenchmarkStage
  var completedSteps: Int
  var totalSteps: Int
  var threadCount: Int?
  var detail: String

  init(
    stage: VoiceWhisperBenchmarkStage,
    completedSteps: Int,
    totalSteps: Int,
    threadCount: Int? = nil,
    detail: String = ""
  ) {
    self.stage = stage
    self.completedSteps = min(max(completedSteps, 0), max(totalSteps, 0))
    self.totalSteps = max(totalSteps, 0)
    self.threadCount = threadCount.map { min(max($0, 1), 16) }
    self.detail = String(detail.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
  }
}

enum VoiceWhisperThreadSearch {
  static func candidates(highPerformanceCoreCount: Int) -> [Int] {
    let cores = min(max(highPerformanceCoreCount, 1), 16)
    var seen = Set<Int>()
    return [2, 3, 4, cores, min(6, cores)]
      .map { min(max($0, 1), cores) }
      .filter { seen.insert($0).inserted }
      .sorted()
  }

  static func selectBest(measurements: [VoiceWhisperBenchmarkMeasurement]) throws -> Int {
    guard !measurements.isEmpty else {
      throw VoiceWhisperBenchmarkPlanningError.missingThreadMeasurements
    }
    let scores = Dictionary(grouping: measurements, by: \.threadCount)
      .map { entry in score(thread: entry.key, measurements: entry.value) }
      .sorted {
        if $0.score != $1.score {
          return $0.score < $1.score
        }
        if $0.averageEnergyNwh != $1.averageEnergyNwh {
          return $0.averageEnergyNwh < $1.averageEnergyNwh
        }
        return $0.threadCount < $1.threadCount
      }
    return scores.first?.threadCount ?? 1
  }

  private static func score(thread: Int, measurements: [VoiceWhisperBenchmarkMeasurement]) -> ThreadScore {
    let p95 = VoiceWhisperBenchmarkMath.percentile(
      measurements.map(\.realTimeFactor),
      percentile: 0.95
    )
    let maxThermal = measurements.map(\.thermalStatusEnd).max() ?? 0
    let firstRtf = measurements.first?.realTimeFactor ?? 0
    let lastRtf = measurements.last?.realTimeFactor ?? firstRtf
    let degradation = max(lastRtf - firstRtf, 0)
    let energyValues = measurements.compactMap(\.energyDeltaNwh).map(Double.init)
    let energy = energyValues.isEmpty ? Double.greatestFiniteMagnitude :
      energyValues.reduce(0, +) / Double(energyValues.count)
    return ThreadScore(
      threadCount: thread,
      score: p95 + Double(maxThermal) * 0.10 + degradation,
      averageEnergyNwh: energy
    )
  }

  private struct ThreadScore {
    var threadCount: Int
    var score: Double
    var averageEnergyNwh: Double
  }
}
