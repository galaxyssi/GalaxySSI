import Foundation

struct VoiceWhisperModelProfile: Codable, Equatable, Identifiable {
  var id: String
  var displayName: String
  var fileName: String
  var sizeLabel: String
  var bundled: Bool
  var minimumUsableBytes: Int64

  init(
    id: String,
    displayName: String,
    fileName: String,
    sizeLabel: String,
    bundled: Bool = false,
    minimumUsableBytes: Int64 = 1_000_000
  ) {
    self.id = id.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank("tiny")
    self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank(self.id)
    self.fileName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
    self.sizeLabel = sizeLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    self.bundled = bundled
    self.minimumUsableBytes = max(0, minimumUsableBytes)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case displayName = "display_name"
    case fileName = "file_name"
    case sizeLabel = "size_label"
    case bundled
    case minimumUsableBytes = "minimum_usable_bytes"
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
  static let mirrorRoot = "https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main"

  static let models: [VoiceWhisperModelProfile] = [
    VoiceWhisperModelProfile(id: "tiny", displayName: "Tiny", fileName: "ggml-tiny.bin", sizeLabel: "75 MB", bundled: true),
    VoiceWhisperModelProfile(id: "base", displayName: "Base", fileName: "ggml-base.bin", sizeLabel: "142 MB"),
    VoiceWhisperModelProfile(id: "small", displayName: "Small", fileName: "ggml-small.bin", sizeLabel: "466 MB"),
    VoiceWhisperModelProfile(id: "medium", displayName: "Medium", fileName: "ggml-medium.bin", sizeLabel: "1.5 GB"),
    VoiceWhisperModelProfile(id: "large", displayName: "Large", fileName: "ggml-large-v3.bin", sizeLabel: "3.1 GB"),
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
