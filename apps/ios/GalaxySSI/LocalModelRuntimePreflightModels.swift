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
  case unsupportedPlatform = "UNSUPPORTED_PLATFORM"
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
    case .unsupportedPlatform, .modelFileMissing, .modelFileInvalid, .systemLowMemory, .insufficientMemory, .deviceTooHot:
      return true
    case .contextReduced, .thermalPressure, .lowBattery, .criticalBattery, .powerSaveMode:
      return false
    }
  }

  static func fromWireValue(_ value: String?) -> LocalModelRuntimeIssue? {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    return allCases.first { $0.rawValue == normalized }
  }
}

enum LocalModelSourceTrust: String, Codable {
  case curated = "CURATED"
  case hubVerified = "HUB_VERIFIED"
  case signedDeployment = "SIGNED_DEPLOYMENT"
}

enum LocalModelArtifactFormat: String, Codable {
  case gguf = "GGUF"
  case qairt = "QAIRT"
}

enum LocalModelHubSource: String, Codable {
  case huggingFace = "HUGGING_FACE"
  case modelScope = "MODELSCOPE"
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
  var repositoryId: String
  var fileName: String
  var sha256: String
  var parameterCountBillions: Double
  var defaultNoThink: Bool
  var visionCapable: Bool
  var sourceTrust: LocalModelSourceTrust
  var sourceHub: LocalModelHubSource
  var preferredAccelerator: LocalModelAcceleratorKind
  var artifactFormat: LocalModelArtifactFormat
  var targetChipset: String

  var supportsIOSRuntime: Bool {
    artifactFormat == .gguf
  }

  var catalogPersistable: Bool {
    repositoryId.range(of: #"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil &&
      expectedModelFileBytes > 0 &&
      (artifactFormat == .qairt
        ? targetChipset.range(of: #"^SM[0-9]{4}$"#, options: .regularExpression) != nil
        : !fileName.isEmpty &&
          !fileName.contains("\\") &&
          !fileName.split(separator: "/").contains { $0.isEmpty || $0 == "." || $0 == ".." })
  }

  var downloadable: Bool {
    repositoryId.range(of: #"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil &&
      fileName.lowercased().hasSuffix(".gguf") &&
      !fileName.contains("\\") &&
      !fileName.split(separator: "/").contains { $0.isEmpty || $0 == "." || $0 == ".." } &&
      expectedModelFileBytes > 0 &&
      sha256.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil &&
      supportsIOSRuntime
  }

  init(
    id: String,
    displayName: String,
    expectedModelFileBytes: Int64,
    layerCount: Int,
    keyValueHeadCount: Int,
    headDimension: Int,
    defaultContextTokens: Int,
    maximumContextTokens: Int,
    quantizationLabel: String,
    repositoryId: String = "",
    fileName: String = "",
    sha256: String = "",
    parameterCountBillions: Double = 0,
    defaultNoThink: Bool = false,
    visionCapable: Bool = false,
    sourceTrust: LocalModelSourceTrust = .curated,
    sourceHub: LocalModelHubSource = .huggingFace,
    preferredAccelerator: LocalModelAcceleratorKind = .cpu,
    artifactFormat: LocalModelArtifactFormat = .gguf,
    targetChipset: String = ""
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
    self.repositoryId = repositoryId
    self.fileName = fileName
    self.sha256 = sha256.lowercased()
    self.parameterCountBillions = max(0, parameterCountBillions)
    self.defaultNoThink = defaultNoThink
    self.visionCapable = visionCapable
    self.sourceTrust = sourceTrust
    self.sourceHub = sourceHub
    self.preferredAccelerator = preferredAccelerator
    self.artifactFormat = artifactFormat
    self.targetChipset = targetChipset.trimmingCharacters(in: .whitespacesAndNewlines)
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
    case repositoryId = "repository_id"
    case fileName = "file_name"
    case sha256
    case parameterCountBillions = "parameter_count_billions"
    case defaultNoThink = "default_no_think"
    case visionCapable = "vision_capable"
    case sourceTrust = "source_trust"
    case sourceHub = "source_hub"
    case preferredAccelerator = "preferred_accelerator"
    case artifactFormat = "artifact_format"
    case targetChipset = "target_chipset"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    displayName = try container.decode(String.self, forKey: .displayName)
    expectedModelFileBytes = try container.decode(Int64.self, forKey: .expectedModelFileBytes)
    layerCount = try container.decode(Int.self, forKey: .layerCount)
    keyValueHeadCount = try container.decode(Int.self, forKey: .keyValueHeadCount)
    headDimension = try container.decode(Int.self, forKey: .headDimension)
    defaultContextTokens = try container.decode(Int.self, forKey: .defaultContextTokens)
    maximumContextTokens = try container.decode(Int.self, forKey: .maximumContextTokens)
    quantizationLabel = try container.decode(String.self, forKey: .quantizationLabel)
    repositoryId = try container.decodeIfPresent(String.self, forKey: .repositoryId) ?? ""
    fileName = try container.decodeIfPresent(String.self, forKey: .fileName) ?? ""
    sha256 = (try container.decodeIfPresent(String.self, forKey: .sha256) ?? "").lowercased()
    parameterCountBillions = max(0, try container.decodeIfPresent(Double.self, forKey: .parameterCountBillions) ?? 0)
    defaultNoThink = try container.decodeIfPresent(Bool.self, forKey: .defaultNoThink) ?? false
    visionCapable = try container.decodeIfPresent(Bool.self, forKey: .visionCapable) ?? false
    sourceTrust = try container.decodeIfPresent(LocalModelSourceTrust.self, forKey: .sourceTrust) ?? .curated
    sourceHub = try container.decodeIfPresent(LocalModelHubSource.self, forKey: .sourceHub) ?? .huggingFace
    preferredAccelerator = try container.decodeIfPresent(LocalModelAcceleratorKind.self, forKey: .preferredAccelerator) ?? .cpu
    artifactFormat = try container.decodeIfPresent(LocalModelArtifactFormat.self, forKey: .artifactFormat) ?? .gguf
    targetChipset = try container.decodeIfPresent(String.self, forKey: .targetChipset) ?? ""
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
  static let GEMMA_3_1B_Q4 = profile(
    id: "gemma-3-1b-it-q4-k-m",
    displayName: "Gemma 3 1B Instruct",
    repositoryId: "ggml-org/gemma-3-1b-it-GGUF",
    fileName: "gemma-3-1b-it-Q4_K_M.gguf",
    expectedModelFileBytes: 806_058_240,
    sha256: "8ccc5cd1f1b3602548715ae25a66ed73fd5dc68a210412eea643eb20eb75a135",
    parameterCountBillions: 1,
    layerCount: 26,
    keyValueHeadCount: 4,
    headDimension: 128,
    maximumContextTokens: 32_768
  )

  static let GEMMA_3_4B_Q4 = profile(
    id: "gemma-3-4b-it-q4-k-m",
    displayName: "Gemma 3 4B Instruct",
    repositoryId: "ggml-org/gemma-3-4b-it-GGUF",
    fileName: "gemma-3-4b-it-Q4_K_M.gguf",
    expectedModelFileBytes: 2_489_757_856,
    sha256: "882e8d2db44dc554fb0ea5077cb7e4bc49e7342a1f0da57901c0802ea21a0863",
    parameterCountBillions: 4,
    layerCount: 34,
    keyValueHeadCount: 4,
    headDimension: 256,
    maximumContextTokens: 128_000,
    visionCapable: true
  )

  static let QWEN_3_4B_Q4_K_M = profile(
    id: "qwen3-4b-q4-k-m",
    displayName: "Qwen3 4B",
    repositoryId: "Qwen/Qwen3-4B-GGUF",
    fileName: "Qwen3-4B-Q4_K_M.gguf",
    expectedModelFileBytes: 2_497_280_256,
    sha256: "7485fe6f11af29433bc51cab58009521f205840f5b4ae3a32fa7f92e8534fdf5",
    parameterCountBillions: 4,
    layerCount: 36,
    keyValueHeadCount: 8,
    headDimension: 128,
    maximumContextTokens: 32_768,
    defaultNoThink: true
  )

  static let LFM_2_5_2_6B_QAIRT = profile(
    id: "lfm2-5-2-6b-qnn-w4a8-sm8850",
    displayName: "LFM2.5 2.6B QNN (NPU)",
    repositoryId: "LiquidAI/LFM2.5-2.6B",
    fileName: "lfm2.5-2.6b-qnn-w4a8-sm8850.zip",
    expectedModelFileBytes: 1_900_000_000,
    sha256: "",
    parameterCountBillions: 2.6,
    layerCount: 30,
    keyValueHeadCount: 8,
    headDimension: 64,
    maximumContextTokens: 4_096,
    quantizationLabel: "W4A8",
    defaultNoThink: true,
    preferredAccelerator: .vendorSDK,
    sourceTrust: .curated,
    artifactFormat: .qairt,
    targetChipset: "SM8850",
    defaultContextTokens: 2_048
  )

  static let QWEN_3_1_7B_QNN = profile(
    id: "qwen3-1-7b-qnn",
    displayName: "Qwen3 1.7B QNN (Hybrid)",
    repositoryId: "unsloth/Qwen3-1.7B-GGUF",
    fileName: "Qwen3-1.7B-Q4_0.gguf",
    expectedModelFileBytes: 1_056_782_912,
    sha256: "c876f159707a4e4f70e045106c69db15bfc935a4981706fd4f65c6e7ea1e81c5",
    parameterCountBillions: 1.7,
    layerCount: 36,
    keyValueHeadCount: 8,
    headDimension: 128,
    maximumContextTokens: 32_768,
    quantizationLabel: "Q4_0",
    defaultNoThink: true,
    preferredAccelerator: .vendorSDK,
    defaultContextTokens: 2_048
  )

  static let QWEN_3_1_7B_QAIRT = profile(
    id: "qwen3-1-7b-qairt",
    displayName: "Qwen3 1.7B QNN (NPU)",
    repositoryId: "qualcomm/Qwen3-1.7B",
    fileName: "",
    expectedModelFileBytes: 1_761_061_334,
    sha256: "",
    parameterCountBillions: 1.7,
    layerCount: 36,
    keyValueHeadCount: 8,
    headDimension: 128,
    maximumContextTokens: 4_096,
    quantizationLabel: "W4A16",
    defaultNoThink: true,
    preferredAccelerator: .vendorSDK,
    sourceTrust: .curated,
    artifactFormat: .qairt,
    targetChipset: "SM8850",
    defaultContextTokens: 4_096
  )

  static let GEMMA_4_E4B_QNN = profile(
    id: "gemma-4-e4b-qnn",
    displayName: "Gemma 4 E4B QNN (Hybrid)",
    repositoryId: "unsloth/gemma-4-E4B-it-GGUF",
    fileName: "gemma-4-E4B-it-Q4_0.gguf",
    expectedModelFileBytes: 4_836_002_944,
    sha256: "4a403d2e4d80281063e4f517b1c061ded8476b4011a4fc2ba7dbff707075547e",
    parameterCountBillions: 4.0,
    layerCount: 36,
    keyValueHeadCount: 8,
    headDimension: 128,
    maximumContextTokens: 128_000,
    quantizationLabel: "Q4_0",
    visionCapable: true,
    preferredAccelerator: .vendorSDK,
    defaultContextTokens: 2_048
  )

  static let QWEN_3_8B_Q4_K_M = profile(
    id: "qwen3-8b-q4-k-m",
    displayName: "Qwen3 8B",
    repositoryId: "Qwen/Qwen3-8B-GGUF",
    fileName: "Qwen3-8B-Q4_K_M.gguf",
    expectedModelFileBytes: 5_027_783_488,
    sha256: "d98cdcbd03e17ce47681435b5150e34c1417f50b5c0019dd560e4882c5745785",
    parameterCountBillions: 8.2,
    layerCount: 36,
    keyValueHeadCount: 8,
    headDimension: 128,
    maximumContextTokens: 32_768,
    defaultNoThink: true
  )

  static let QWEN_3_5_9B_Q4_K_M = profile(
    id: "qwen3-5-9b-q4-k-m",
    displayName: "Qwen3.5 9B",
    repositoryId: "bartowski/Qwen_Qwen3.5-9B-GGUF",
    fileName: "Qwen_Qwen3.5-9B-Q4_K_M.gguf",
    expectedModelFileBytes: 6_169_341_984,
    sha256: "d784ce9eda1a5a7b51e8f705a9e6310844bf4f173654d115823c775fdea56d43",
    parameterCountBillions: 9,
    layerCount: 32,
    keyValueHeadCount: 4,
    headDimension: 256,
    maximumContextTokens: 262_144,
    visionCapable: true
  )

  static let LFM_2_5_350M_Q8_0 = profile(
    id: "lfm2-5-350m-q8-0",
    displayName: "LFM2.5 350M",
    repositoryId: "LiquidAI/LFM2.5-350M-GGUF",
    fileName: "LFM2.5-350M-Q8_0.gguf",
    expectedModelFileBytes: 379_217_632,
    sha256: "be036a757295e550098b85e13f6af2735d0fa73b41e1156a40c7d8e8e32a5766",
    parameterCountBillions: 0.35,
    layerCount: 16,
    keyValueHeadCount: 8,
    headDimension: 64,
    maximumContextTokens: 32_768,
    quantizationLabel: "Q8_0",
    defaultNoThink: true
  )

  static let LLAMA_3_1_8B_Q4_K_M = profile(
    id: "llama-3-1-8b-instruct-q4-k-m",
    displayName: "Llama 3.1 8B Instruct",
    repositoryId: "bartowski/Meta-Llama-3.1-8B-Instruct-GGUF",
    fileName: "Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf",
    expectedModelFileBytes: 4_920_739_232,
    sha256: "7b064f5842bf9532c91456deda288a1b672397a54fa729aa665952863033557c",
    parameterCountBillions: 8,
    layerCount: 32,
    keyValueHeadCount: 8,
    headDimension: 128,
    maximumContextTokens: 128_000
  )

  static let DEEPSEEK_R1_DISTILL_LLAMA_8B_Q4_K_M = profile(
    id: "deepseek-r1-distill-llama-8b-q4-k-m",
    displayName: "DeepSeek R1 Distill Llama 8B",
    repositoryId: "unsloth/DeepSeek-R1-Distill-Llama-8B-GGUF",
    fileName: "DeepSeek-R1-Distill-Llama-8B-Q4_K_M.gguf",
    expectedModelFileBytes: 4_920_737_216,
    sha256: "0addb1339a82385bcd973186cd80d18dcc71885d45eabd899781a118d03827d9",
    parameterCountBillions: 8,
    layerCount: 32,
    keyValueHeadCount: 8,
    headDimension: 128,
    maximumContextTokens: 128_000
  )

  static let GEMMA_3_12B_Q4_K_M = profile(
    id: "gemma-3-12b-it-q4-k-m",
    displayName: "Gemma 3 12B Instruct",
    repositoryId: "ggml-org/gemma-3-12b-it-GGUF",
    fileName: "gemma-3-12b-it-Q4_K_M.gguf",
    expectedModelFileBytes: 7_300_574_976,
    sha256: "7bb69bff3f48a7b642355d64a90e481182a7794707b3133890646b1efa778ff5",
    parameterCountBillions: 12,
    layerCount: 48,
    keyValueHeadCount: 8,
    headDimension: 256,
    maximumContextTokens: 128_000,
    visionCapable: true
  )

  @available(*, deprecated, message: "Use QWEN_3_8B_Q4_K_M")
  static let QWEN_2_5_7B_Q4 = QWEN_3_8B_Q4_K_M

  static let all: [LocalModelRuntimeProfile] = [
    GEMMA_3_1B_Q4,
    GEMMA_3_4B_Q4,
    LFM_2_5_2_6B_QAIRT,
    QWEN_3_1_7B_QNN,
    QWEN_3_1_7B_QAIRT,
    QWEN_3_4B_Q4_K_M,
    QWEN_3_8B_Q4_K_M,
    GEMMA_4_E4B_QNN,
    QWEN_3_5_9B_Q4_K_M,
    LFM_2_5_350M_Q8_0,
    LLAMA_3_1_8B_Q4_K_M,
    DEEPSEEK_R1_DISTILL_LLAMA_8B_Q4_K_M,
    GEMMA_3_12B_Q4_K_M,
  ]

  static func find(_ id: String) -> LocalModelRuntimeProfile {
    switch id {
    case "gemma-3-1b-q4":
      return GEMMA_3_1B_Q4
    case "gemma-3-4b-q4":
      return GEMMA_3_4B_Q4
    case "qwen-2.5-7b-q4":
      return QWEN_2_5_7B_Q4
    case "lfm2-5-350m-q8-0":
      return LFM_2_5_350M_Q8_0
    default:
      return all.first { $0.id == id } ?? GEMMA_3_4B_Q4
    }
  }

  private static func profile(
    id: String,
    displayName: String,
    repositoryId: String,
    fileName: String,
    expectedModelFileBytes: Int64,
    sha256: String,
    parameterCountBillions: Double,
    layerCount: Int,
    keyValueHeadCount: Int,
    headDimension: Int,
    maximumContextTokens: Int,
    quantizationLabel: String = "Q4_K_M",
    defaultNoThink: Bool = false,
    visionCapable: Bool = false,
    preferredAccelerator: LocalModelAcceleratorKind = .cpu,
    sourceTrust: LocalModelSourceTrust = .curated,
    artifactFormat: LocalModelArtifactFormat = .gguf,
    targetChipset: String = "",
    defaultContextTokens: Int = 4_096
  ) -> LocalModelRuntimeProfile {
    LocalModelRuntimeProfile(
      id: id,
      displayName: displayName,
      expectedModelFileBytes: expectedModelFileBytes,
      layerCount: layerCount,
      keyValueHeadCount: keyValueHeadCount,
      headDimension: headDimension,
      defaultContextTokens: defaultContextTokens,
      maximumContextTokens: maximumContextTokens,
      quantizationLabel: quantizationLabel,
      repositoryId: repositoryId,
      fileName: fileName,
      sha256: sha256,
      parameterCountBillions: parameterCountBillions,
      defaultNoThink: defaultNoThink,
      visionCapable: visionCapable,
      sourceTrust: sourceTrust,
      preferredAccelerator: preferredAccelerator,
      artifactFormat: artifactFormat,
      targetChipset: targetChipset
    )
  }

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

    if !profile.supportsIOSRuntime {
      issues.insert(.unsupportedPlatform)
    }

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
    return thermalStatus >= THERMAL_STATUS_MODERATE
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
    if defaults.string(forKey: keyProfile) == nil {
      let bundled = LocalModelRuntimeProfiles.LFM_2_5_350M_Q8_0
      if LocalModelRuntimeStorage().inspect(bundled).installed {
        return bundled
      }
    }
    let candidate = LocalModelRuntimeCatalog.find(
      defaults.string(forKey: keyProfile) ?? LocalModelRuntimeProfiles.GEMMA_3_4B_Q4.id,
      defaults: defaults
    )
    return candidate.supportsIOSRuntime ? candidate : LocalModelRuntimeProfiles.GEMMA_3_4B_Q4
  }

  static func setSelectedProfile(_ profileId: String, defaults: UserDefaults = .standard) {
    let profile = LocalModelRuntimeCatalog.find(profileId, defaults: defaults)
    guard profile.supportsIOSRuntime else { return }
    defaults.set(profile.id, forKey: keyProfile)
  }

  static func enabledProfileIds(defaults: UserDefaults = .standard) -> Set<String> {
    let knownIds = Set(
      LocalModelRuntimeCatalog.profiles(defaults: defaults)
        .filter(\.supportsIOSRuntime)
        .map(\.id)
    )
    if let stored = defaults.array(forKey: keyEnabledProfiles) as? [String] {
      return Set(stored).intersection(knownIds)
    }
    let selected = selectedProfile(defaults: defaults)
    return LocalModelRuntimeStorage().inspect(selected).installed ? [selected.id] : []
  }

  static func isProfileEnabled(
    _ profile: LocalModelRuntimeProfile,
    defaults: UserDefaults = .standard
  ) -> Bool {
    enabledProfileIds(defaults: defaults).contains(profile.id)
  }

  static func setProfileEnabled(
    _ profile: LocalModelRuntimeProfile,
    enabled: Bool,
    defaults: UserDefaults = .standard
  ) {
    let knownIds = Set(LocalModelRuntimeCatalog.profiles(defaults: defaults).map(\.id))
    guard knownIds.contains(profile.id), profile.supportsIOSRuntime else { return }
    var updated = enabledProfileIds(defaults: defaults)
    if enabled {
      updated.insert(profile.id)
      setSelectedProfile(profile.id, defaults: defaults)
    } else {
      updated.remove(profile.id)
      if selectedProfile(defaults: defaults).id == profile.id,
         let fallback = updated.sorted().first {
        setSelectedProfile(fallback, defaults: defaults)
      }
    }
    defaults.set(Array(updated).sorted(), forKey: keyEnabledProfiles)
  }

  static func removeProfile(_ profileId: String, defaults: UserDefaults = .standard) {
    var updated = enabledProfileIds(defaults: defaults)
    updated.remove(profileId)
    defaults.set(Array(updated).sorted(), forKey: keyEnabledProfiles)
    if defaults.string(forKey: keyProfile) == profileId {
      defaults.set(LocalModelRuntimeProfiles.GEMMA_3_4B_Q4.id, forKey: keyProfile)
    }
  }

  static func activeProfiles(defaults: UserDefaults = .standard) -> [LocalModelRuntimeProfile] {
    let selectedId = selectedProfile(defaults: defaults).id
    let storage = LocalModelRuntimeStorage()
    return LocalModelRuntimeCatalog.profiles(defaults: defaults)
      .filter { enabledProfileIds(defaults: defaults).contains($0.id) }
      .filter(\.supportsIOSRuntime)
      .filter { storage.inspect($0).installed }
      .sorted { left, right in
        if left.id == selectedId { return true }
        if right.id == selectedId { return false }
        return left.displayName.localizedCaseInsensitiveCompare(right.displayName) == .orderedAscending
      }
  }

  static func contextTokens(defaults: UserDefaults = .standard) -> Int {
    let stored = defaults.object(forKey: keyContextTokens) as? Int ?? defaultContextTokens
    return stored.clamped(to: minContextTokens...maxContextTokens)
  }

  static func setContextTokens(_ value: Int, defaults: UserDefaults = .standard) {
    defaults.set(value.clamped(to: minContextTokens...maxContextTokens), forKey: keyContextTokens)
  }

  private static let keyProfile = "galaxyssi_local_model_runtime_v1.profile"
  private static let keyEnabledProfiles = "galaxyssi_local_model_runtime_v1.enabled_profiles"
  private static let keyContextTokens = "galaxyssi_local_model_runtime_v1.context_tokens"
  private static let defaultContextTokens = 4_096
  private static let minContextTokens = 512
  private static let maxContextTokens = 32_768
}

private extension Int64 {
  func clamped(lower: Int64, upper: Int64) -> Int64 {
    Swift.min(Swift.max(self, lower), upper)
  }
}
