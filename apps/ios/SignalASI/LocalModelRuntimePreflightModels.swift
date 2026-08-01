import Foundation

#if canImport(UIKit)
import UIKit
#endif

enum LocalModelRuntimeReadiness: String, Codable, CaseIterable, Identifiable {
  case ready = "READY"
  case caution = "CAUTION"
  case blocked = "BLOCKED"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> LocalModelRuntimeReadiness {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    return allCases.first { $0.rawValue == normalized } ?? .blocked
  }
}

enum LocalModelRuntimeIssue: String, Codable, CaseIterable, Identifiable {
  case modelFileMissing = "MODEL_FILE_MISSING"
  case modelFileInvalid = "MODEL_FILE_INVALID"
  case systemLowMemory = "SYSTEM_LOW_MEMORY"
  case insufficientMemory = "INSUFFICIENT_MEMORY"
  case contextReduced = "CONTEXT_REDUCED"
  case thermalPressure = "THERMAL_PRESSURE"
  case deviceTooHot = "DEVICE_TOO_HOT"
  case lowBattery = "LOW_BATTERY"
  case criticalBattery = "CRITICAL_BATTERY"
  case powerSaveMode = "POWER_SAVE_MODE"

  var id: String { rawValue }

  var blocksLaunch: Bool {
    switch self {
    case .modelFileMissing, .modelFileInvalid, .systemLowMemory, .insufficientMemory, .deviceTooHot,
         .criticalBattery:
      return true
    case .contextReduced, .thermalPressure, .lowBattery, .powerSaveMode:
      return false
    }
  }

  static func fromWireValue(_ value: String?) -> LocalModelRuntimeIssue? {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    return allCases.first { $0.rawValue == normalized }
  }
}

struct LocalModelRuntimeProfile: Codable, Equatable, Identifiable {
  var id: String
  var displayName: String
  var expectedModelFileBytes: Int64
  var layerCount: Int
  var keyValueHeadCount: Int
  var headDimension: Int
  var defaultContextTokens: Int
  var maximumContextTokens: Int
  var quantizationLabel: String

  init(
    id: String,
    displayName: String,
    expectedModelFileBytes: Int64,
    layerCount: Int,
    keyValueHeadCount: Int,
    headDimension: Int,
    defaultContextTokens: Int,
    maximumContextTokens: Int,
    quantizationLabel: String
  ) {
    self.id = id
    self.displayName = displayName
    self.expectedModelFileBytes = expectedModelFileBytes
    self.layerCount = layerCount
    self.keyValueHeadCount = keyValueHeadCount
    self.headDimension = headDimension
    self.defaultContextTokens = defaultContextTokens
    self.maximumContextTokens = maximumContextTokens
    self.quantizationLabel = quantizationLabel
  }

  enum CodingKeys: String, CodingKey {
    case id
    case displayName = "display_name"
    case expectedModelFileBytes = "expected_model_file_bytes"
    case layerCount = "layer_count"
    case keyValueHeadCount = "key_value_head_count"
    case headDimension = "head_dimension"
    case defaultContextTokens = "default_context_tokens"
    case maximumContextTokens = "maximum_context_tokens"
    case quantizationLabel = "quantization_label"
  }
}

struct LocalModelRuntimeRequest: Codable, Equatable {
  var profile: LocalModelRuntimeProfile
  var requestedContextTokens: Int
  var preferredThreads: Int
  var modelFileBytes: Int64
  var modelFilePresent: Bool
  var requireModelFile: Bool

  init(
    profile: LocalModelRuntimeProfile,
    requestedContextTokens: Int? = nil,
    preferredThreads: Int = 0,
    modelFileBytes: Int64? = nil,
    modelFilePresent: Bool = true,
    requireModelFile: Bool = false
  ) {
    self.profile = profile
    self.requestedContextTokens = requestedContextTokens ?? profile.defaultContextTokens
    self.preferredThreads = preferredThreads
    self.modelFileBytes = modelFileBytes ?? profile.expectedModelFileBytes
    self.modelFilePresent = modelFilePresent
    self.requireModelFile = requireModelFile
  }

  enum CodingKeys: String, CodingKey {
    case profile
    case requestedContextTokens = "requested_context_tokens"
    case preferredThreads = "preferred_threads"
    case modelFileBytes = "model_file_bytes"
    case modelFilePresent = "model_file_present"
    case requireModelFile = "require_model_file"
  }
}

struct LocalModelDeviceSnapshot: Codable, Equatable {
  var totalMemoryBytes: Int64
  var availableMemoryBytes: Int64
  var systemLowMemory: Bool
  var cpuCoreCount: Int
  var batteryPercent: Int?
  var charging: Bool
  var batteryTemperatureCelsius: Double?
  var thermalStatus: Int?
  var powerSaveMode: Bool

  init(
    totalMemoryBytes: Int64,
    availableMemoryBytes: Int64,
    systemLowMemory: Bool,
    cpuCoreCount: Int,
    batteryPercent: Int? = nil,
    charging: Bool,
    batteryTemperatureCelsius: Double? = nil,
    thermalStatus: Int? = nil,
    powerSaveMode: Bool
  ) {
    self.totalMemoryBytes = max(0, totalMemoryBytes)
    self.availableMemoryBytes = min(max(0, availableMemoryBytes), max(0, totalMemoryBytes))
    self.systemLowMemory = systemLowMemory
    self.cpuCoreCount = max(1, cpuCoreCount)
    self.batteryPercent = batteryPercent.map { $0.clamped(to: 0...100) }
    self.charging = charging
    self.batteryTemperatureCelsius = batteryTemperatureCelsius
    self.thermalStatus = thermalStatus
    self.powerSaveMode = powerSaveMode
  }

  enum CodingKeys: String, CodingKey {
    case totalMemoryBytes = "total_memory_bytes"
    case availableMemoryBytes = "available_memory_bytes"
    case systemLowMemory = "system_low_memory"
    case cpuCoreCount = "cpu_core_count"
    case batteryPercent = "battery_percent"
    case charging
    case batteryTemperatureCelsius = "battery_temperature_celsius"
    case thermalStatus = "thermal_status"
    case powerSaveMode = "power_save_mode"
  }
}

struct LocalModelRuntimeEstimate: Codable, Equatable {
  var readiness: LocalModelRuntimeReadiness
  var issues: Set<LocalModelRuntimeIssue>
  var modelFileBytes: Int64
  var modelResidentBytes: Int64
  var kvCacheBytes: Int64
  var runtimeOverheadBytes: Int64
  var threadOverheadBytes: Int64
  var totalRequiredBytes: Int64
  var safeMemoryBudgetBytes: Int64
  var requestedContextTokens: Int
  var recommendedContextTokens: Int
  var recommendedThreads: Int
  var device: LocalModelDeviceSnapshot

  var launchAllowed: Bool {
    readiness != .blocked
  }

  enum CodingKeys: String, CodingKey {
    case readiness
    case issues
    case modelFileBytes = "model_file_bytes"
    case modelResidentBytes = "model_resident_bytes"
    case kvCacheBytes = "kv_cache_bytes"
    case runtimeOverheadBytes = "runtime_overhead_bytes"
    case threadOverheadBytes = "thread_overhead_bytes"
    case totalRequiredBytes = "total_required_bytes"
    case safeMemoryBudgetBytes = "safe_memory_budget_bytes"
    case requestedContextTokens = "requested_context_tokens"
    case recommendedContextTokens = "recommended_context_tokens"
    case recommendedThreads = "recommended_threads"
    case device
  }
}

enum LocalModelRuntimeProfiles {
  static let GEMMA_3_1B_Q4 = LocalModelRuntimeProfile(
    id: "gemma-3-1b-q4",
    displayName: "Gemma 3 1B Q4",
    expectedModelFileBytes: 820 * MIB,
    layerCount: 26,
    keyValueHeadCount: 1,
    headDimension: 256,
    defaultContextTokens: 4_096,
    maximumContextTokens: 32_768,
    quantizationLabel: "Q4"
  )

  static let GEMMA_3_4B_Q4 = LocalModelRuntimeProfile(
    id: "gemma-3-4b-q4",
    displayName: "Gemma 3 4B Q4",
    expectedModelFileBytes: 2_650 * MIB,
    layerCount: 34,
    keyValueHeadCount: 4,
    headDimension: 256,
    defaultContextTokens: 4_096,
    maximumContextTokens: 32_768,
    quantizationLabel: "Q4"
  )

  static let QWEN_2_5_7B_Q4 = LocalModelRuntimeProfile(
    id: "qwen-2.5-7b-q4",
    displayName: "Qwen 2.5 7B Q4",
    expectedModelFileBytes: 4_450 * MIB,
    layerCount: 28,
    keyValueHeadCount: 4,
    headDimension: 128,
    defaultContextTokens: 4_096,
    maximumContextTokens: 32_768,
    quantizationLabel: "Q4"
  )

  static let all: [LocalModelRuntimeProfile] = [
    GEMMA_3_1B_Q4,
    GEMMA_3_4B_Q4,
    QWEN_2_5_7B_Q4,
  ]

  static func find(_ id: String) -> LocalModelRuntimeProfile {
    all.first { $0.id == id } ?? GEMMA_3_4B_Q4
  }

  private static let MIB: Int64 = 1_024 * 1_024
}

enum LocalModelRuntimePreflightError: Error, Equatable, LocalizedError {
  case blocked(LocalModelRuntimeEstimate)

  var errorDescription: String? {
    switch self {
    case .blocked(let estimate):
      let issueText = estimate.issues.map { $0.rawValue }.sorted().joined(separator: ",")
      return "Local model preflight blocked launch: \(issueText)"
    }
  }
}

enum LocalModelRuntimeEstimator {
  static func estimate(
    _ request: LocalModelRuntimeRequest,
    device: LocalModelDeviceSnapshot
  ) -> LocalModelRuntimeEstimate {
    let profile = request.profile
    let modelFileBytes = max(0, request.modelFileBytes)
    let maximumContext = max(MIN_CONTEXT_TOKENS, profile.maximumContextTokens)
    let requestedContext = request.requestedContextTokens.clamped(to: MIN_CONTEXT_TOKENS...maximumContext)
    var issues = Set<LocalModelRuntimeIssue>()

    if request.requireModelFile && !request.modelFilePresent {
      issues.insert(.modelFileMissing)
    }
    if modelFileBytes <= 0 {
      issues.insert(.modelFileInvalid)
    }
    if device.systemLowMemory {
      issues.insert(.systemLowMemory)
    }

    var threads = recommendedThreadCount(request: request, device: device)
    if shouldUseConservativeThreads(device: device) {
      threads = min(threads, CONSERVATIVE_MAX_THREADS)
    }

    let safeMemoryBudget = safeMemoryBudget(device)
    let contexts = candidateContexts(requestedContext)
    let requirements = contexts.map {
      ($0, requirement(profile: profile, modelFileBytes: modelFileBytes, contextTokens: $0, threads: threads))
    }
    let selectedPair = requirements.first { $0.1.total <= safeMemoryBudget } ?? requirements.last ??
      (MIN_CONTEXT_TOKENS, requirement(
        profile: profile,
        modelFileBytes: modelFileBytes,
        contextTokens: MIN_CONTEXT_TOKENS,
        threads: threads
      ))
    let recommendedContext = selectedPair.0
    let selected = selectedPair.1

    if selected.total > safeMemoryBudget {
      issues.insert(.insufficientMemory)
    } else if recommendedContext < requestedContext {
      issues.insert(.contextReduced)
    }

    let thermalStatus = device.thermalStatus ?? THERMAL_STATUS_NONE
    if thermalStatus >= THERMAL_STATUS_SEVERE ||
        (device.batteryTemperatureCelsius.map { $0 >= HOT_BATTERY_CELSIUS } ?? false) {
      issues.insert(.deviceTooHot)
    } else if thermalStatus >= THERMAL_STATUS_MODERATE ||
        (device.batteryTemperatureCelsius.map { $0 >= WARM_BATTERY_CELSIUS } ?? false) {
      issues.insert(.thermalPressure)
    }

    if !device.charging, let batteryPercent = device.batteryPercent {
      if batteryPercent < CRITICAL_BATTERY_PERCENT {
        issues.insert(.criticalBattery)
      } else if batteryPercent < LOW_BATTERY_PERCENT {
        issues.insert(.lowBattery)
      }
    }
    if device.powerSaveMode {
      issues.insert(.powerSaveMode)
    }

    let readiness: LocalModelRuntimeReadiness
    if issues.contains(where: { $0.blocksLaunch }) {
      readiness = .blocked
    } else if !issues.isEmpty {
      readiness = .caution
    } else {
      readiness = .ready
    }

    return LocalModelRuntimeEstimate(
      readiness: readiness,
      issues: issues,
      modelFileBytes: modelFileBytes,
      modelResidentBytes: selected.modelResident,
      kvCacheBytes: selected.kvCache,
      runtimeOverheadBytes: selected.runtimeOverhead,
      threadOverheadBytes: selected.threadOverhead,
      totalRequiredBytes: selected.total,
      safeMemoryBudgetBytes: safeMemoryBudget,
      requestedContextTokens: requestedContext,
      recommendedContextTokens: recommendedContext,
      recommendedThreads: threads,
      device: device
    )
  }

  static func requireLaunchable(_ estimate: LocalModelRuntimeEstimate) throws -> LocalModelRuntimeEstimate {
    guard estimate.launchAllowed else {
      throw LocalModelRuntimePreflightError.blocked(estimate)
    }
    return estimate
  }

  private static func recommendedThreadCount(
    request: LocalModelRuntimeRequest,
    device: LocalModelDeviceSnapshot
  ) -> Int {
    let availableCores = max(1, device.cpuCoreCount)
    if request.preferredThreads > 0 {
      return request.preferredThreads.clamped(to: 1...availableCores)
    }
    return min(DEFAULT_MAX_THREADS, availableCores)
  }

  private static func shouldUseConservativeThreads(device: LocalModelDeviceSnapshot) -> Bool {
    let thermalStatus = device.thermalStatus ?? THERMAL_STATUS_NONE
    let batteryPercent = device.batteryPercent ?? 100
    return device.powerSaveMode ||
      thermalStatus >= THERMAL_STATUS_MODERATE ||
      (!device.charging && batteryPercent < LOW_BATTERY_PERCENT)
  }

  private static func candidateContexts(_ requestedContext: Int) -> [Int] {
    var contexts: [Int] = []
    var current = requestedContext
    while true {
      if !contexts.contains(current) {
        contexts.append(current)
      }
      guard current > MIN_CONTEXT_TOKENS else { break }
      current = max(MIN_CONTEXT_TOKENS, current / 2)
    }
    return contexts
  }

  private static func requirement(
    profile: LocalModelRuntimeProfile,
    modelFileBytes: Int64,
    contextTokens: Int,
    threads: Int
  ) -> Requirement {
    let modelResident = modelFileBytes +
      max(MIN_MODEL_METADATA_BYTES, roundedBytes(modelFileBytes, ratio: MODEL_MAPPING_OVERHEAD_RATIO))
    let kvCache = 2 *
      Int64(max(1, profile.layerCount)) *
      Int64(max(MIN_CONTEXT_TOKENS, contextTokens)) *
      Int64(max(1, profile.keyValueHeadCount)) *
      Int64(max(1, profile.headDimension)) *
      KV_CACHE_ELEMENT_BYTES
    let runtimeScratch = roundedBytes(modelFileBytes, ratio: RUNTIME_SCRATCH_RATIO)
      .clamped(lower: MIN_RUNTIME_SCRATCH_BYTES, upper: MAX_RUNTIME_SCRATCH_BYTES)
    let runtimeOverhead = BASE_RUNTIME_BYTES + runtimeScratch
    let threadOverhead = Int64(max(1, threads)) * PER_THREAD_BYTES
    return Requirement(
      modelResident: modelResident,
      kvCache: kvCache,
      runtimeOverhead: runtimeOverhead,
      threadOverhead: threadOverhead,
      total: modelResident + kvCache + runtimeOverhead + threadOverhead
    )
  }

  private static func safeMemoryBudget(_ device: LocalModelDeviceSnapshot) -> Int64 {
    let total = max(0, device.totalMemoryBytes)
    let available = device.availableMemoryBytes.clamped(lower: 0, upper: total)
    let reserve = max(MIN_SYSTEM_RESERVE_BYTES, roundedBytes(total, ratio: SYSTEM_RESERVE_RATIO))
    let totalBound = max(0, total - reserve)
    let availableBound = roundedBytes(available, ratio: AVAILABLE_MEMORY_RATIO)
    return max(0, min(totalBound, availableBound))
  }

  private static func roundedBytes(_ value: Int64, ratio: Double) -> Int64 {
    Int64((Double(max(0, value)) * ratio).rounded())
  }

  private struct Requirement {
    var modelResident: Int64
    var kvCache: Int64
    var runtimeOverhead: Int64
    var threadOverhead: Int64
    var total: Int64
  }

  private static let MIN_CONTEXT_TOKENS = 512
  private static let DEFAULT_MAX_THREADS = 6
  private static let CONSERVATIVE_MAX_THREADS = 2
  private static let KV_CACHE_ELEMENT_BYTES: Int64 = 2
  private static let MODEL_MAPPING_OVERHEAD_RATIO = 0.04
  private static let RUNTIME_SCRATCH_RATIO = 0.08
  private static let SYSTEM_RESERVE_RATIO = 0.18
  private static let AVAILABLE_MEMORY_RATIO = 0.82
  private static let MIN_MODEL_METADATA_BYTES: Int64 = 64 * 1_024 * 1_024
  private static let BASE_RUNTIME_BYTES: Int64 = 256 * 1_024 * 1_024
  private static let MIN_RUNTIME_SCRATCH_BYTES: Int64 = 128 * 1_024 * 1_024
  private static let MAX_RUNTIME_SCRATCH_BYTES: Int64 = 768 * 1_024 * 1_024
  private static let PER_THREAD_BYTES: Int64 = 8 * 1_024 * 1_024
  private static let MIN_SYSTEM_RESERVE_BYTES: Int64 = 1_024 * 1_024 * 1_024
  private static let THERMAL_STATUS_NONE = 0
  private static let THERMAL_STATUS_MODERATE = 2
  private static let THERMAL_STATUS_SEVERE = 3
  private static let WARM_BATTERY_CELSIUS = 42.0
  private static let HOT_BATTERY_CELSIUS = 45.0
  private static let LOW_BATTERY_PERCENT = 20
  private static let CRITICAL_BATTERY_PERCENT = 10
}

enum LocalModelDeviceSnapshotDetector {
  static func capture(
    totalMemoryBytes: Int64? = nil,
    availableMemoryBytes: Int64? = nil,
    systemLowMemory: Bool = false,
    processorCount: Int? = nil,
    batteryPercent: Int? = nil,
    charging: Bool? = nil,
    batteryTemperatureCelsius: Double? = nil,
    thermalState: ProcessInfo.ThermalState? = nil,
    powerSaveMode: Bool? = nil,
    processInfo: ProcessInfo = .processInfo
  ) -> LocalModelDeviceSnapshot {
    let total = max(0, totalMemoryBytes ?? int64Memory(processInfo.physicalMemory))
    let estimatedAvailable = availableMemoryBytes ?? estimatedAvailableMemory(totalBytes: total, processInfo: processInfo)
    let battery = batterySnapshot()
    return LocalModelDeviceSnapshot(
      totalMemoryBytes: total,
      availableMemoryBytes: estimatedAvailable,
      systemLowMemory: systemLowMemory,
      cpuCoreCount: processorCount ?? processInfo.processorCount,
      batteryPercent: batteryPercent ?? battery.percent,
      charging: charging ?? battery.charging,
      batteryTemperatureCelsius: batteryTemperatureCelsius,
      thermalStatus: thermalStatus(for: thermalState ?? processInfo.thermalState),
      powerSaveMode: powerSaveMode ?? processInfo.isLowPowerModeEnabled
    )
  }

  static func thermalStatus(for state: ProcessInfo.ThermalState) -> Int {
    switch state {
    case .nominal:
      return 0
    case .fair:
      return 1
    case .serious:
      return 2
    case .critical:
      return 3
    @unknown default:
      return 2
    }
  }

  private static func estimatedAvailableMemory(totalBytes: Int64, processInfo: ProcessInfo) -> Int64 {
    let ratio: Double
    switch processInfo.thermalState {
    case .critical:
      ratio = 0.35
    case .serious:
      ratio = 0.45
    case .fair:
      ratio = 0.50
    case .nominal:
      ratio = processInfo.isLowPowerModeEnabled ? 0.45 : 0.55
    @unknown default:
      ratio = 0.45
    }
    return Int64((Double(max(0, totalBytes)) * ratio).rounded())
  }

  private static func int64Memory(_ value: UInt64) -> Int64 {
    value > UInt64(Int64.max) ? Int64.max : Int64(value)
  }

  private static func batterySnapshot() -> (percent: Int?, charging: Bool) {
    #if canImport(UIKit)
    let device = UIDevice.current
    let wasMonitoring = device.isBatteryMonitoringEnabled
    device.isBatteryMonitoringEnabled = true
    defer { device.isBatteryMonitoringEnabled = wasMonitoring }
    let percent = device.batteryLevel >= 0 ? Int((device.batteryLevel * 100).rounded()).clamped(to: 0...100) : nil
    let charging = device.batteryState == .charging || device.batteryState == .full
    return (percent, charging)
    #else
    return (nil, false)
    #endif
  }
}

enum LocalModelRuntimePreflight {
  static func estimate(
    profile: LocalModelRuntimeProfile,
    contextTokens: Int,
    preferredThreads: Int = 0,
    device: LocalModelDeviceSnapshot = LocalModelDeviceSnapshotDetector.capture()
  ) -> LocalModelRuntimeEstimate {
    LocalModelRuntimeEstimator.estimate(
      LocalModelRuntimeRequest(
        profile: profile,
        requestedContextTokens: contextTokens,
        preferredThreads: preferredThreads
      ),
      device: device
    )
  }

  static func beforeLaunch(
    profile: LocalModelRuntimeProfile,
    modelFileURL: URL,
    contextTokens: Int,
    preferredThreads: Int = 0,
    device: LocalModelDeviceSnapshot = LocalModelDeviceSnapshotDetector.capture()
  ) throws -> LocalModelRuntimeEstimate {
    let file = modelFile(modelFileURL)
    return try LocalModelRuntimeEstimator.requireLaunchable(
      LocalModelRuntimeEstimator.estimate(
        LocalModelRuntimeRequest(
          profile: profile,
          requestedContextTokens: contextTokens,
          preferredThreads: preferredThreads,
          modelFileBytes: file.bytes,
          modelFilePresent: file.present,
          requireModelFile: true
        ),
        device: device
      )
    )
  }

  private static func modelFile(_ url: URL) -> (present: Bool, bytes: Int64) {
    guard url.isFileURL,
          let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
          values.isRegularFile == true else {
      return (false, 0)
    }
    return (true, Int64(max(0, values.fileSize ?? 0)))
  }
}

enum LocalModelRuntimeSettings {
  static func selectedProfile(defaults: UserDefaults = .standard) -> LocalModelRuntimeProfile {
    LocalModelRuntimeProfiles.find(defaults.string(forKey: keyProfile) ?? LocalModelRuntimeProfiles.GEMMA_3_4B_Q4.id)
  }

  static func setSelectedProfile(_ profileId: String, defaults: UserDefaults = .standard) {
    defaults.set(LocalModelRuntimeProfiles.find(profileId).id, forKey: keyProfile)
  }

  static func contextTokens(defaults: UserDefaults = .standard) -> Int {
    let stored = defaults.object(forKey: keyContextTokens) as? Int ?? defaultContextTokens
    return stored.clamped(to: minContextTokens...maxContextTokens)
  }

  static func setContextTokens(_ value: Int, defaults: UserDefaults = .standard) {
    defaults.set(value.clamped(to: minContextTokens...maxContextTokens), forKey: keyContextTokens)
  }

  private static let keyProfile = "signalasi_local_model_runtime_v1.profile"
  private static let keyContextTokens = "signalasi_local_model_runtime_v1.context_tokens"
  private static let defaultContextTokens = 4_096
  private static let minContextTokens = 512
  private static let maxContextTokens = 32_768
}

private extension Int64 {
  func clamped(lower: Int64, upper: Int64) -> Int64 {
    Swift.min(Swift.max(self, lower), upper)
  }
}
