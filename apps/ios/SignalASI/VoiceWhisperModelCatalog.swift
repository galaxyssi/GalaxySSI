import Foundation

struct VoiceWhisperModelProfile: Codable, Equatable, Identifiable {
  var id: String
  var displayName: String
  var fileName: String
  var sizeLabel: String
  var bundled: Bool
  var minimumUsableBytes: Int64
  var expectedSizeBytes: Int64
  var sha256: String
  var minFreeStorageBytes: Int64

  init(
    id: String,
    displayName: String,
    fileName: String,
    sizeLabel: String,
    bundled: Bool = false,
    minimumUsableBytes: Int64 = 0,
    expectedSizeBytes: Int64 = 0,
    sha256: String = "",
    minFreeStorageBytes: Int64 = 0
  ) {
    self.id = id.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank("tiny")
    self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank(self.id)
    self.fileName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
    self.sizeLabel = sizeLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    self.bundled = bundled
    self.expectedSizeBytes = max(0, expectedSizeBytes)
    self.minimumUsableBytes = max(
      0,
      minimumUsableBytes > 0 ? minimumUsableBytes : (expectedSizeBytes > 0 ? expectedSizeBytes : 1_000_000)
    )
    self.sha256 = sha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    self.minFreeStorageBytes = max(0, minFreeStorageBytes)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case displayName = "display_name"
    case fileName = "file_name"
    case sizeLabel = "size_label"
    case bundled
    case minimumUsableBytes = "minimum_usable_bytes"
    case expectedSizeBytes = "expected_size_bytes"
    case sha256
    case minFreeStorageBytes = "min_free_storage_bytes"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decodeIfPresent(String.self, forKey: .id) ?? "tiny",
      displayName: try container.decodeIfPresent(String.self, forKey: .displayName) ?? "Tiny",
      fileName: try container.decodeIfPresent(String.self, forKey: .fileName) ?? "ggml-tiny.bin",
      sizeLabel: try container.decodeIfPresent(String.self, forKey: .sizeLabel) ?? "",
      bundled: try container.decodeIfPresent(Bool.self, forKey: .bundled) ?? false,
      minimumUsableBytes: try container.decodeIfPresent(Int64.self, forKey: .minimumUsableBytes) ?? 0,
      expectedSizeBytes: try container.decodeIfPresent(Int64.self, forKey: .expectedSizeBytes) ?? 0,
      sha256: try container.decodeIfPresent(String.self, forKey: .sha256) ?? "",
      minFreeStorageBytes: try container.decodeIfPresent(Int64.self, forKey: .minFreeStorageBytes) ?? 0
    )
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
  static let catalogVersion = "2026.08.01"
  static let mirrorRoot = "https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main"

  static let models: [VoiceWhisperModelProfile] = [
    VoiceWhisperModelProfile(
      id: "tiny",
      displayName: "Tiny",
      fileName: "ggml-tiny.bin",
      sizeLabel: "74.1 MiB",
      bundled: true,
      expectedSizeBytes: 77_691_713,
      sha256: "be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21",
      minFreeStorageBytes: 256 * 1_048_576
    ),
    VoiceWhisperModelProfile(
      id: "base",
      displayName: "Base",
      fileName: "ggml-base.bin",
      sizeLabel: "141.1 MiB",
      expectedSizeBytes: 147_951_465,
      sha256: "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe",
      minFreeStorageBytes: 384 * 1_048_576
    ),
    VoiceWhisperModelProfile(
      id: "small",
      displayName: "Small",
      fileName: "ggml-small.bin",
      sizeLabel: "465.0 MiB",
      expectedSizeBytes: 487_601_967,
      sha256: "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b",
      minFreeStorageBytes: 768 * 1_048_576
    ),
    VoiceWhisperModelProfile(
      id: "medium",
      displayName: "Medium",
      fileName: "ggml-medium.bin",
      sizeLabel: "1.4 GiB",
      expectedSizeBytes: 1_533_763_059,
      sha256: "6c14d5adee5f86394037b4e4e8b59f1673b6cee10e3cf0b11bbdbee79c156208",
      minFreeStorageBytes: 2_000 * 1_048_576
    ),
    VoiceWhisperModelProfile(
      id: "large",
      displayName: "Large v3",
      fileName: "ggml-large-v3.bin",
      sizeLabel: "2.9 GiB",
      expectedSizeBytes: 3_095_033_483,
      sha256: "64d182b440b98d5203c4f9bd541544d84c605196c4f7b845dfa11fb23594d1e2",
      minFreeStorageBytes: 4_000 * 1_048_576
    ),
  ]

  static func model(_ id: String?) -> VoiceWhisperModelProfile {
    let normalized = normalizedModelId(id)
    return models.first { $0.id == normalized } ?? models[0]
  }

  static func normalizedModelId(_ id: String?) -> String {
    let normalized = id?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    return models.first { $0.id == normalized }?.id ?? models[0].id
  }

  static func downloadURL(for model: VoiceWhisperModelProfile) -> URL? {
    URL(string: "\(mirrorRoot)/\(model.fileName)")
  }

  static func defaultModelsDirectory(
    fileManager: FileManager = .default
  ) -> URL {
    let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ??
      fileManager.temporaryDirectory
    return root.appendingPathComponent("signalasi-asr", isDirectory: true)
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
    let bundled = bundle.url(
      forResource: model.fileName.deletingPathExtension,
      withExtension: model.fileName.nonBlankPathExtension
    ) != nil
    let downloaded = downloadedFileBytes(
      for: model,
      fileManager: fileManager,
      modelsDirectory: modelsDirectory
    )
    return isAvailable(model, bundledResourceExists: bundled, downloadedFileBytes: downloaded)
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
