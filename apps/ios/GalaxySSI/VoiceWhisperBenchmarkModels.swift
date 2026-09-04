import CryptoKit
import Foundation

struct VoiceWhisperBenchmarkKey: Codable, Equatable {
  var manufacturer: String
  var device: String
  var soc: String
  var osVersion: String
  var appVersionCode: Int
  var whisperNativeVersion: String
  var nativeBuildFingerprint: String
  var modelProfileId: String
  var modelSha256: String
  var benchmarkAudioVersion: String

  init(
    manufacturer: String,
    device: String,
    soc: String,
    osVersion: String,
    appVersionCode: Int,
    whisperNativeVersion: String,
    nativeBuildFingerprint: String,
    modelProfileId: String,
    modelSha256: String,
    benchmarkAudioVersion: String
  ) {
    self.manufacturer = Self.clean(manufacturer, fallback: "Apple")
    self.device = Self.clean(device, fallback: "unknown-device")
    self.soc = Self.clean(soc, fallback: "unknown-soc")
    self.osVersion = Self.clean(osVersion, fallback: "unknown-ios")
    self.appVersionCode = max(appVersionCode, 1)
    self.whisperNativeVersion = Self.clean(whisperNativeVersion, fallback: "unknown-native")
    self.nativeBuildFingerprint = Self.clean(nativeBuildFingerprint, fallback: "unknown-build")
    self.modelProfileId = Self.clean(modelProfileId, fallback: "unknown-model")
    let normalizedSha = modelSha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    self.modelSha256 = Self.isSha256(normalizedSha) ? normalizedSha : String(repeating: "0", count: 64)
    self.benchmarkAudioVersion = Self.clean(benchmarkAudioVersion, fallback: "unknown-audio")
  }

  var stableId: String {
    Self.sha256(canonicalValue)
  }

  private var canonicalValue: String {
    [
      manufacturer,
      device,
      soc,
      osVersion,
      String(appVersionCode),
      whisperNativeVersion,
      nativeBuildFingerprint,
      modelProfileId,
      modelSha256,
      benchmarkAudioVersion
    ].joined(separator: "\u{001f}")
  }

  private static func clean(_ value: String, fallback: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank(fallback)
  }

  private static func isSha256(_ value: String) -> Bool {
    value.count == 64 && value.unicodeScalars.allSatisfy { scalar in
      (48...57).contains(scalar.value) || (97...102).contains(scalar.value)
    }
  }

  private static func sha256(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

enum VoiceWhisperBenchmarkLoadKind: String, Codable, Equatable {
  case cold = "COLD"
  case hot = "HOT"
}

struct VoiceWhisperBenchmarkMeasurement: Codable, Equatable {
  var threadCount: Int
  var loadKind: VoiceWhisperBenchmarkLoadKind
  var audioDurationMillis: Int64
  var decodeDurationMillis: Int64
  var realTimeFactor: Double
  var loadDurationMillis: Int64
  var warmUpDurationMillis: Int64
  var peakPssBytes: Int64
  var peakRssBytes: Int64
  var peakNativeAllocatedBytes: Int64
  var cpuTimeMillis: Int64
  var energyDeltaNwh: Int64?
  var firstPartialLatencyMillis: Int64
  var finalTailLatencyMillis: Int64
  var batteryTemperatureStartCelsius: Double?
  var batteryTemperatureEndCelsius: Double?
  var thermalStatusStart: Int
  var thermalStatusEnd: Int
  var transcriptCorrect: Bool

  init(
    threadCount: Int,
    loadKind: VoiceWhisperBenchmarkLoadKind = .hot,
    audioDurationMillis: Int64,
    decodeDurationMillis: Int64,
    realTimeFactor: Double,
    loadDurationMillis: Int64 = 0,
    warmUpDurationMillis: Int64 = 0,
    peakPssBytes: Int64 = 0,
    peakRssBytes: Int64 = 0,
    peakNativeAllocatedBytes: Int64 = 0,
    cpuTimeMillis: Int64 = 0,
    energyDeltaNwh: Int64? = nil,
    firstPartialLatencyMillis: Int64 = 0,
    finalTailLatencyMillis: Int64 = 0,
    batteryTemperatureStartCelsius: Double? = nil,
    batteryTemperatureEndCelsius: Double? = nil,
    thermalStatusStart: Int = 0,
    thermalStatusEnd: Int = 0,
    transcriptCorrect: Bool = false
  ) {
    self.threadCount = min(max(threadCount, 1), 16)
    self.loadKind = loadKind
    self.audioDurationMillis = max(audioDurationMillis, 1)
    self.decodeDurationMillis = max(decodeDurationMillis, 0)
    self.realTimeFactor = realTimeFactor.isFinite ? max(realTimeFactor, 0) : 0
    self.loadDurationMillis = max(loadDurationMillis, 0)
    self.warmUpDurationMillis = max(warmUpDurationMillis, 0)
    self.peakPssBytes = max(peakPssBytes, 0)
    self.peakRssBytes = max(peakRssBytes, 0)
    self.peakNativeAllocatedBytes = max(peakNativeAllocatedBytes, 0)
    self.cpuTimeMillis = max(cpuTimeMillis, 0)
    self.energyDeltaNwh = energyDeltaNwh.map { max($0, 0) }
    self.firstPartialLatencyMillis = max(firstPartialLatencyMillis, 0)
    self.finalTailLatencyMillis = max(finalTailLatencyMillis, 0)
    self.batteryTemperatureStartCelsius = batteryTemperatureStartCelsius?.isFinite == true ? batteryTemperatureStartCelsius : nil
    self.batteryTemperatureEndCelsius = batteryTemperatureEndCelsius?.isFinite == true ? batteryTemperatureEndCelsius : nil
    self.thermalStatusStart = max(thermalStatusStart, 0)
    self.thermalStatusEnd = max(thermalStatusEnd, 0)
    self.transcriptCorrect = transcriptCorrect
  }
}

struct VoiceWhisperCertification: Codable, Equatable {
  var key: VoiceWhisperBenchmarkKey
  var level: VoiceWhisperCertificationLevel
  var recommendedMode: VoiceWhisperExecutionMode
  var recommendedThreadCount: Int
  var recommendedPartialIntervalMillis: Int64
  var warmRtfP50: Double
  var warmRtfP95: Double
  var loadTimeMillisP95: Int64
  var peakPssBytes: Int64
  var maxThermalStatus: Int
  var abortLatencyMillisP95: Int64
  var createdAtEpochMillis: Int64
  var failureReason: String?

  init(
    key: VoiceWhisperBenchmarkKey,
    level: VoiceWhisperCertificationLevel,
    recommendedMode: VoiceWhisperExecutionMode,
    recommendedThreadCount: Int,
    recommendedPartialIntervalMillis: Int64,
    warmRtfP50: Double,
    warmRtfP95: Double,
    loadTimeMillisP95: Int64 = 0,
    peakPssBytes: Int64 = 0,
    maxThermalStatus: Int = 0,
    abortLatencyMillisP95: Int64 = 0,
    createdAtEpochMillis: Int64,
    failureReason: String? = nil
  ) {
    self.key = key
    self.level = level
    self.recommendedMode = recommendedMode
    self.recommendedThreadCount = min(max(recommendedThreadCount, 1), 16)
    self.recommendedPartialIntervalMillis = max(recommendedPartialIntervalMillis, 0)
    let p50 = warmRtfP50.isFinite ? max(warmRtfP50, 0) : 0
    let p95 = warmRtfP95.isFinite ? max(warmRtfP95, p50) : p50
    self.warmRtfP50 = p50
    self.warmRtfP95 = p95
    self.loadTimeMillisP95 = max(loadTimeMillisP95, 0)
    self.peakPssBytes = max(peakPssBytes, 0)
    self.maxThermalStatus = max(maxThermalStatus, 0)
    self.abortLatencyMillisP95 = max(abortLatencyMillisP95, 0)
    self.createdAtEpochMillis = max(createdAtEpochMillis, 1)
    let cleanFailure = failureReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    self.failureReason = cleanFailure.isEmpty ? nil : String(cleanFailure.prefix(512))
  }

  var realtimeCertified: Bool {
    level == .realtime && recommendedMode == .realtimePartial
  }

  var remoteRecommended: Bool {
    level == .remoteRecommended && recommendedMode == .remoteNode
  }
}

struct VoiceWhisperBenchmarkRecord: Codable, Equatable {
  var certification: VoiceWhisperCertification
  var measurements: [VoiceWhisperBenchmarkMeasurement]
  var verificationDurationMillis: Int64
  var abortLatenciesMillis: [Int64]
  var highPerformanceCoreCount: Int
  var threadCandidates: [Int]

  init(
    certification: VoiceWhisperCertification,
    measurements: [VoiceWhisperBenchmarkMeasurement] = [],
    verificationDurationMillis: Int64 = 0,
    abortLatenciesMillis: [Int64] = [],
    highPerformanceCoreCount: Int = 1,
    threadCandidates: [Int] = [1]
  ) {
    self.certification = certification
    self.measurements = Array(measurements.prefix(256))
    self.verificationDurationMillis = max(verificationDurationMillis, 0)
    self.abortLatenciesMillis = Array(abortLatenciesMillis.prefix(16)).map { max($0, 0) }
    self.highPerformanceCoreCount = max(highPerformanceCoreCount, 1)
    let candidates = threadCandidates.filter { (1...16).contains($0) }
    self.threadCandidates = candidates.isEmpty ? [1] : candidates
  }
}

enum VoiceWhisperBenchmarkMath {
  static func percentile(_ values: [Double], percentile: Double) -> Double {
    if values.isEmpty {
      return 0
    }
    let sorted = values.sorted()
    let index = Int(Double(sorted.count - 1) * min(max(percentile, 0), 1) + 0.5)
    return sorted[min(max(index, 0), sorted.count - 1)]
  }

  static func percentileMillis(_ values: [Int64], percentile: Double) -> Int64 {
    if values.isEmpty {
      return 0
    }
    let sorted = values.sorted()
    let index = Int(Double(sorted.count - 1) * min(max(percentile, 0), 1) + 0.5)
    return sorted[min(max(index, 0), sorted.count - 1)]
  }
}
