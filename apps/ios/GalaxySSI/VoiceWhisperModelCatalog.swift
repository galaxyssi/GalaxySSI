import Foundation

enum VoiceWhisperModelFamily: String, Codable, Equatable {
  case tiny = "TINY"
  case base = "BASE"
  case small = "SMALL"
  case medium = "MEDIUM"
  case largeV3 = "LARGE_V3"
  case largeV3Turbo = "LARGE_V3_TURBO"
}

enum VoiceWhisperQuantization: String, Codable, Equatable {
  case f16 = "F16"
  case f32 = "F32"
  case w8a16 = "W8A16"
  case q8_0 = "Q8_0"
  case q6_k = "Q6_K"
  case q5_1 = "Q5_1"
  case q5_0 = "Q5_0"
  case q4_1 = "Q4_1"
  case q4_0 = "Q4_0"
  case unknown = "UNKNOWN"
}

enum VoiceWhisperExecutionMode: String, Codable, Equatable {
  case realtimePartial = "REALTIME_PARTIAL"
  case finalOnly = "FINAL_ONLY"
  case secondPass = "SECOND_PASS"
  case remoteNode = "REMOTE_NODE"
}

enum VoiceWhisperArtifactFormat: String, Codable, Equatable {
  case gguf = "GGUF"
  case qnnContextBinary = "QNN_CONTEXT_BINARY"
}

struct VoiceWhisperModelProfile: Codable, Equatable, Identifiable {
  var id: String
  var family: VoiceWhisperModelFamily
  var displayName: String
  var fileName: String
  var sourceURLs: [String]
  var sizeLabel: String
  var bundled: Bool
  var minimumUsableBytes: Int64
  var expectedSizeBytes: Int64
  var sha256: String
  var minFreeStorageBytes: Int64
  var quantization: VoiceWhisperQuantization
  var multilingual: Bool
  var recommendedMode: VoiceWhisperExecutionMode
  var minAvailableRamBytes: Int64
  var defaultPartialIntervalMillis: Int64
  var maxWindowMillis: Int64
  var enabledByDefault: Bool
  var experimental: Bool
  var manifestVersion: Int
  var legacyIds: Set<String>
  var artifactFormat: VoiceWhisperArtifactFormat
  var targetChipset: String

  var supportsIOSRuntime: Bool {
    artifactFormat == .gguf
  }

  init(
    id: String,
    family: VoiceWhisperModelFamily = .tiny,
    displayName: String,
    fileName: String,
    sourceURLs: [String] = [],
    sizeLabel: String,
    bundled: Bool = false,
    minimumUsableBytes: Int64 = 0,
    expectedSizeBytes: Int64 = 0,
    sha256: String = "",
    minFreeStorageBytes: Int64 = 0,
    quantization: VoiceWhisperQuantization = .unknown,
    multilingual: Bool = true,
    recommendedMode: VoiceWhisperExecutionMode = .finalOnly,
    minAvailableRamBytes: Int64 = 0,
    defaultPartialIntervalMillis: Int64 = 1_000,
    maxWindowMillis: Int64 = 8_000,
    enabledByDefault: Bool = false,
    experimental: Bool = false,
    manifestVersion: Int = 2,
    legacyIds: Set<String> = [],
    artifactFormat: VoiceWhisperArtifactFormat = .gguf,
    targetChipset: String = ""
  ) {
    self.id = id.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank("tiny")
    self.family = family
    self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank(self.id)
    self.fileName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedSources = sourceURLs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter {
      $0.lowercased().hasPrefix("https://")
    }
    self.sourceURLs = normalizedSources.isEmpty && artifactFormat == .gguf
      ? Self.defaultSourceURLs(fileName: self.fileName)
      : normalizedSources
    self.sizeLabel = sizeLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    self.bundled = bundled
    self.expectedSizeBytes = max(0, expectedSizeBytes)
    self.minimumUsableBytes = max(
      0,
      minimumUsableBytes > 0 ? minimumUsableBytes : (expectedSizeBytes > 0 ? expectedSizeBytes : 1_000_000)
    )
    self.sha256 = sha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    self.minFreeStorageBytes = max(0, minFreeStorageBytes)
    self.quantization = quantization
    self.multilingual = multilingual
    self.recommendedMode = recommendedMode
    self.minAvailableRamBytes = max(0, minAvailableRamBytes)
    self.defaultPartialIntervalMillis = max(1, defaultPartialIntervalMillis)
    self.maxWindowMillis = max(1, maxWindowMillis)
    self.enabledByDefault = enabledByDefault
    self.experimental = experimental
    self.manifestVersion = max(1, manifestVersion)
    self.legacyIds = Set(
      legacyIds
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        .filter { !$0.isEmpty }
    )
    self.artifactFormat = artifactFormat
    self.targetChipset = targetChipset.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case family
    case displayName = "display_name"
    case fileName = "file_name"
    case sourceURLs = "source_urls"
    case sizeLabel = "size_label"
    case bundled
    case minimumUsableBytes = "minimum_usable_bytes"
    case expectedSizeBytes = "expected_size_bytes"
    case sha256
    case minFreeStorageBytes = "min_free_storage_bytes"
    case quantization
    case multilingual
    case recommendedMode = "recommended_mode"
    case minAvailableRamBytes = "min_available_ram_bytes"
    case defaultPartialIntervalMillis = "default_partial_interval_ms"
    case maxWindowMillis = "max_window_ms"
    case enabledByDefault = "enabled_by_default"
    case experimental
    case manifestVersion = "manifest_version"
    case legacyIds = "legacy_ids"
    case artifactFormat = "artifact_format"
    case targetChipset = "target_chipset"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decodeIfPresent(String.self, forKey: .id) ?? "tiny",
      family: try container.decodeIfPresent(VoiceWhisperModelFamily.self, forKey: .family) ?? .tiny,
      displayName: try container.decodeIfPresent(String.self, forKey: .displayName) ?? "Tiny",
      fileName: try container.decodeIfPresent(String.self, forKey: .fileName) ?? "ggml-tiny.bin",
      sourceURLs: try container.decodeIfPresent([String].self, forKey: .sourceURLs) ?? [],
      sizeLabel: try container.decodeIfPresent(String.self, forKey: .sizeLabel) ?? "",
      bundled: try container.decodeIfPresent(Bool.self, forKey: .bundled) ?? false,
      minimumUsableBytes: try container.decodeIfPresent(Int64.self, forKey: .minimumUsableBytes) ?? 0,
      expectedSizeBytes: try container.decodeIfPresent(Int64.self, forKey: .expectedSizeBytes) ?? 0,
      sha256: try container.decodeIfPresent(String.self, forKey: .sha256) ?? "",
      minFreeStorageBytes: try container.decodeIfPresent(Int64.self, forKey: .minFreeStorageBytes) ?? 0,
      quantization: try container.decodeIfPresent(VoiceWhisperQuantization.self, forKey: .quantization) ?? .unknown,
      multilingual: try container.decodeIfPresent(Bool.self, forKey: .multilingual) ?? true,
      recommendedMode: try container.decodeIfPresent(VoiceWhisperExecutionMode.self, forKey: .recommendedMode) ?? .finalOnly,
      minAvailableRamBytes: try container.decodeIfPresent(Int64.self, forKey: .minAvailableRamBytes) ?? 0,
      defaultPartialIntervalMillis: try container.decodeIfPresent(Int64.self, forKey: .defaultPartialIntervalMillis) ?? 1_000,
      maxWindowMillis: try container.decodeIfPresent(Int64.self, forKey: .maxWindowMillis) ?? 8_000,
      enabledByDefault: try container.decodeIfPresent(Bool.self, forKey: .enabledByDefault) ?? false,
      experimental: try container.decodeIfPresent(Bool.self, forKey: .experimental) ?? false,
      manifestVersion: try container.decodeIfPresent(Int.self, forKey: .manifestVersion) ?? 2,
      legacyIds: try container.decodeIfPresent(Set<String>.self, forKey: .legacyIds) ?? [],
      artifactFormat: try container.decodeIfPresent(VoiceWhisperArtifactFormat.self, forKey: .artifactFormat) ?? .gguf,
      targetChipset: try container.decodeIfPresent(String.self, forKey: .targetChipset) ?? ""
    )
  }

  private static func defaultSourceURLs(fileName: String) -> [String] {
    let fileName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !fileName.isEmpty else { return [] }
    return [
      "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)",
      "https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main/\(fileName)"
    ]
  }
}

struct VoiceWhisperModelDownloadState: Codable, Equatable {
  var status: VoiceWhisperModelDownloadStatus
  var progress: Int

  init(status: VoiceWhisperModelDownloadStatus, progress: Int = 0) {
    self.status = status
    self.progress = min(max(progress, 0), 100)
  }
}

enum VoiceWhisperModelDownloadStatus: String, Codable, Equatable {
  case notRequested = "NOT_REQUESTED"
  case pending = "PENDING"
  case running = "RUNNING"
  case paused = "PAUSED"
  case successful = "SUCCESSFUL"
  case failed = "FAILED"
}

enum VoiceWhisperModelCatalog {
  static let schemaVersion = 2
  static let catalogVersion = "2026.08.13"
  static let mirrorRoot = "https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main"
  private static let mib: Int64 = 1_048_576
  static let models: [VoiceWhisperModelProfile] = [
    profile(
      id: "tiny",
      family: .tiny,
      displayName: "Tiny",
      fileName: "ggml-tiny.bin",
      sizeLabel: "74.1 MiB",
      size: 77_691_713,
      sha: "be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21",
      quantization: .f16,
      mode: .realtimePartial,
      ram: 512 * mib,
      reserve: 256 * mib,
      partialMillis: 750,
      windowMillis: 8_000,
      enabled: true,
      bundled: true
    ),
    profile(
      id: "tiny_q5_1",
      family: .tiny,
      displayName: "Tiny Q5_1",
      fileName: "ggml-tiny-q5_1.bin",
      sizeLabel: "30.7 MiB",
      size: 32_152_673,
      sha: "818710568da3ca15689e31a743197b520007872ff9576237bda97bd1b469c3d7",
      quantization: .q5_1,
      mode: .realtimePartial,
      ram: 384 * mib,
      reserve: 192 * mib,
      partialMillis: 650,
      windowMillis: 8_000
    ),
    profile(
      id: "base",
      family: .base,
      displayName: "Base",
      fileName: "ggml-base.bin",
      sizeLabel: "141.1 MiB",
      size: 147_951_465,
      sha: "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe",
      quantization: .f16,
      mode: .realtimePartial,
      ram: 768 * mib,
      reserve: 384 * mib,
      partialMillis: 1_100,
      windowMillis: 10_000
    ),
    profile(
      id: "base_q5_1",
      family: .base,
      displayName: "Base Q5_1",
      fileName: "ggml-base-q5_1.bin",
      sizeLabel: "56.9 MiB",
      size: 59_707_625,
      sha: "422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898",
      quantization: .q5_1,
      mode: .realtimePartial,
      ram: 512 * mib,
      reserve: 256 * mib,
      partialMillis: 950,
      windowMillis: 10_000
    ),
    profile(
      id: "small",
      family: .small,
      displayName: "Small",
      fileName: "ggml-small.bin",
      sizeLabel: "465.0 MiB",
      size: 487_601_967,
      sha: "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b",
      quantization: .f16,
      mode: .finalOnly,
      ram: 1_340 * mib,
      reserve: 768 * mib,
      partialMillis: 2_200,
      windowMillis: 12_000
    ),
    profile(
      id: "small_q5_1",
      family: .small,
      displayName: "Small Q5_1",
      fileName: "ggml-small-q5_1.bin",
      sizeLabel: "181.3 MiB",
      size: 190_085_487,
      sha: "ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb",
      quantization: .q5_1,
      mode: .finalOnly,
      ram: 900 * mib,
      reserve: 512 * mib,
      partialMillis: 1_800,
      windowMillis: 12_000
    ),
    profile(
      id: "medium",
      family: .medium,
      displayName: "Medium",
      fileName: "ggml-medium.bin",
      sizeLabel: "1.4 GiB",
      size: 1_533_763_059,
      sha: "6c14d5adee5f86394037b4e4e8b59f1673b6cee10e3cf0b11bbdbee79c156208",
      quantization: .f16,
      mode: .secondPass,
      ram: 3_000 * mib,
      reserve: 2_000 * mib,
      partialMillis: 4_500,
      windowMillis: 16_000,
      experimental: true
    ),
    profile(
      id: "medium_q5_0",
      family: .medium,
      displayName: "Medium Q5_0",
      fileName: "ggml-medium-q5_0.bin",
      sizeLabel: "514.2 MiB",
      size: 539_212_467,
      sha: "19fea4b380c3a618ec4723c3eef2eb785ffba0d0538cf43f8f235e7b3b34220f",
      quantization: .q5_0,
      mode: .secondPass,
      ram: 1_700 * mib,
      reserve: 1_000 * mib,
      partialMillis: 3_500,
      windowMillis: 16_000,
      experimental: true
    ),
    profile(
      id: "large",
      family: .largeV3,
      displayName: "Large v3",
      fileName: "ggml-large-v3.bin",
      sizeLabel: "2.9 GiB",
      size: 3_095_033_483,
      sha: "64d182b440b98d5203c4f9bd541544d84c605196c4f7b845dfa11fb23594d1e2",
      quantization: .f16,
      mode: .secondPass,
      ram: 5_000 * mib,
      reserve: 4_000 * mib,
      partialMillis: 7_500,
      windowMillis: 20_000,
      experimental: true,
      legacyIds: ["large_v3"]
    ),
    profile(
      id: "large_v3_q5_0",
      family: .largeV3,
      displayName: "Large v3 Q5_0",
      fileName: "ggml-large-v3-q5_0.bin",
      sizeLabel: "1.0 GiB",
      size: 1_081_140_203,
      sha: "d75795ecff3f83b5faa89d1900604ad8c780abd5739fae406de19f23ecd98ad1",
      quantization: .q5_0,
      mode: .secondPass,
      ram: 2_600 * mib,
      reserve: 2_000 * mib,
      partialMillis: 6_000,
      windowMillis: 20_000,
      experimental: true
    ),
    profile(
      id: "large_v3_turbo",
      family: .largeV3Turbo,
      displayName: "Large v3 Turbo",
      fileName: "ggml-large-v3-turbo.bin",
      sizeLabel: "1.5 GiB",
      size: 1_624_555_275,
      sha: "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69",
      quantization: .f16,
      mode: .secondPass,
      ram: 3_200 * mib,
      reserve: 2_000 * mib,
      partialMillis: 2_800,
      windowMillis: 16_000,
      experimental: true
    ),
    profile(
      id: "large_v3_turbo_q5_0",
      family: .largeV3Turbo,
      displayName: "Large v3 Turbo Q5_0",
      fileName: "ggml-large-v3-turbo-q5_0.bin",
      sizeLabel: "547.4 MiB",
      size: 574_041_195,
      sha: "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2",
      quantization: .q5_0,
      mode: .secondPass,
      ram: 1_800 * mib,
      reserve: 1_000 * mib,
      partialMillis: 2_200,
      windowMillis: 16_000,
      experimental: true
    ),
    qnnProfile(
      id: "whisper-tiny-qnn-float-s26u",
      family: .tiny,
      displayName: "Whisper Tiny QNN Float (Android)",
      fileName: "whisper_tiny-qnn_context_binary-float-s26u.zip",
      sizeLabel: "101.0 MiB",
      size: 105_910_421,
      quantization: .f32,
      mode: .realtimePartial,
      ram: 512 * mib,
      reserve: 256 * mib
    ),
    qnnProfile(
      id: "whisper-base-qnn-float-s26u",
      family: .base,
      displayName: "Whisper Base QNN Float (Android)",
      fileName: "whisper_base-qnn_context_binary-float-s26u.zip",
      sizeLabel: "172.6 MiB",
      size: 180_939_859,
      quantization: .f32,
      mode: .realtimePartial,
      ram: 768 * mib,
      reserve: 384 * mib
    ),
    qnnProfile(
      id: "whisper-small-qnn-w8a16-s26u",
      family: .small,
      displayName: "Whisper Small QNN W8A16 (Android)",
      fileName: "whisper_small_quantized-qnn_context_binary-w8a16-s26u.zip",
      sizeLabel: "280.4 MiB",
      size: 293_970_633,
      quantization: .w8a16,
      mode: .finalOnly,
      ram: 1_340 * mib,
      reserve: 768 * mib
    ),
    qnnProfile(
      id: "whisper-small-qnn-float-s26u",
      family: .small,
      displayName: "Whisper Small QNN Float (Android)",
      fileName: "whisper_small-qnn_context_binary-float-s26u.zip",
      sizeLabel: "546.8 MiB",
      size: 573_246_593,
      quantization: .f32,
      mode: .finalOnly,
      ram: 1_340 * mib,
      reserve: 768 * mib
    )
  ]

  private static let byId: [String: VoiceWhisperModelProfile] = {
    Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })
  }()

  private static let aliases: [String: String] = {
    var values: [String: String] = ["large-v3": "large"]
    for profile in models {
      for legacyId in profile.legacyIds {
        values[legacyId] = profile.id
      }
    }
    return values
  }()

  static func model(_ id: String?) -> VoiceWhisperModelProfile {
    byId[normalizedModelId(id)] ?? models[0]
  }

  static func normalizedModelId(_ id: String?) -> String {
    let normalized = id?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    return byId[aliases[normalized] ?? normalized]?.id ?? models[0].id
  }

  private static func profile(
    id: String,
    family: VoiceWhisperModelFamily,
    displayName: String,
    fileName: String,
    sizeLabel: String,
    size: Int64,
    sha: String,
    quantization: VoiceWhisperQuantization,
    mode: VoiceWhisperExecutionMode,
    ram: Int64,
    reserve: Int64,
    partialMillis: Int64,
    windowMillis: Int64,
    enabled: Bool = false,
    bundled: Bool = false,
    experimental: Bool = false,
    legacyIds: Set<String> = [],
    artifactFormat: VoiceWhisperArtifactFormat = .gguf,
    targetChipset: String = ""
  ) -> VoiceWhisperModelProfile {
    VoiceWhisperModelProfile(
      id: id,
      family: family,
      displayName: displayName,
      fileName: fileName,
      sizeLabel: sizeLabel,
      bundled: bundled,
      expectedSizeBytes: size,
      sha256: sha,
      minFreeStorageBytes: reserve,
      quantization: quantization,
      multilingual: true,
      recommendedMode: mode,
      minAvailableRamBytes: ram,
      defaultPartialIntervalMillis: partialMillis,
      maxWindowMillis: windowMillis,
      enabledByDefault: enabled,
      experimental: experimental,
      manifestVersion: schemaVersion,
      legacyIds: legacyIds,
      artifactFormat: artifactFormat,
      targetChipset: targetChipset
    )
  }

  private static func qnnProfile(
    id: String,
    family: VoiceWhisperModelFamily,
    displayName: String,
    fileName: String,
    sizeLabel: String,
    size: Int64,
    quantization: VoiceWhisperQuantization,
    mode: VoiceWhisperExecutionMode,
    ram: Int64,
    reserve: Int64
  ) -> VoiceWhisperModelProfile {
    profile(
      id: id,
      family: family,
      displayName: displayName,
      fileName: fileName,
      sizeLabel: sizeLabel,
      size: size,
      sha: "",
      quantization: quantization,
      mode: mode,
      ram: ram,
      reserve: reserve,
      partialMillis: mode == .realtimePartial ? 1_000 : 2_200,
      windowMillis: mode == .realtimePartial ? 10_000 : 12_000,
      artifactFormat: .qnnContextBinary,
      targetChipset: "qualcomm-snapdragon-8-elite-gen5-for-galaxy"
    )
  }

  static func downloadURL(for model: VoiceWhisperModelProfile) -> URL? {
    guard model.supportsIOSRuntime else { return nil }
    return URL(string: "\(mirrorRoot)/\(model.fileName)")
  }

  static func downloadURL(
    for model: VoiceWhisperModelProfile,
    locale: Locale
  ) -> URL? {
    guard model.supportsIOSRuntime else { return nil }
    return VoiceWhisperModelDownloadPolicy.orderedSources(profile: model, locale: locale).compactMap(URL.init(string:)).first
  }

  static func defaultModelsDirectory(
    fileManager: FileManager = .default
  ) -> URL {
    let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ??
      fileManager.temporaryDirectory
    return root.appendingPathComponent("galaxyssi-asr", isDirectory: true)
  }

  static func downloadedFileURL(
    for model: VoiceWhisperModelProfile,
    modelsDirectory: URL = defaultModelsDirectory()
  ) -> URL {
    modelsDirectory.appendingPathComponent(model.fileName, isDirectory: false)
  }

  static func isAvailable(
    _ model: VoiceWhisperModelProfile,
    bundledResourceExists: Bool,
    downloadedFileBytes: Int64?,
    downloadState: VoiceWhisperModelDownloadState = VoiceWhisperModelDownloadState(status: .successful, progress: 100)
  ) -> Bool {
    guard model.supportsIOSRuntime else { return false }
    if model.bundled {
      return bundledResourceExists
    }
    guard downloadState.status == .successful,
          let downloadedFileBytes = downloadedFileBytes else {
      return false
    }
    return downloadedFileBytes >= model.minimumUsableBytes
  }

  static func isAvailable(
    _ model: VoiceWhisperModelProfile,
    bundle: Bundle = .main,
    fileManager: FileManager = .default,
    modelsDirectory: URL = defaultModelsDirectory()
  ) -> Bool {
    guard model.supportsIOSRuntime else { return false }
    let bundled = bundledResourceURL(for: model, bundle: bundle) != nil
    let downloaded = downloadedFileBytes(
      for: model,
      fileManager: fileManager,
      modelsDirectory: modelsDirectory
    )
    return isAvailable(model, bundledResourceExists: bundled, downloadedFileBytes: downloaded)
  }

  static func bundledResourceURL(
    for model: VoiceWhisperModelProfile,
    bundle: Bundle = .main
  ) -> URL? {
    let name = model.fileName.deletingPathExtension
    let extensionName = model.fileName.nonBlankPathExtension
    return bundle.url(forResource: name, withExtension: extensionName, subdirectory: "voice/models") ??
      bundle.url(forResource: name, withExtension: extensionName)
  }

  private static func downloadedFileBytes(
    for model: VoiceWhisperModelProfile,
    fileManager: FileManager,
    modelsDirectory: URL
  ) -> Int64? {
    let url = downloadedFileURL(for: model, modelsDirectory: modelsDirectory)
    guard url.isFileURL,
          let attributes = try? fileManager.attributesOfItem(atPath: url.path),
          let size = attributes[.size] as? NSNumber else {
      return nil
    }
    return size.int64Value
  }
}

private extension String {
  var pathExtension: String {
    (self as NSString).pathExtension
  }

  var nonBlankPathExtension: String? {
    pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : pathExtension
  }

  var deletingPathExtension: String {
    (self as NSString).deletingPathExtension
  }
}
