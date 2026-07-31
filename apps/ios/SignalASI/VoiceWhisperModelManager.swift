import Foundation

struct VoiceWhisperModelDownloadRecord: Codable, Equatable {
  var modelId: String
  var requestId: String
  var status: VoiceWhisperModelDownloadStatus
  var progress: Int
  var downloadedBytes: Int64
  var totalBytes: Int64
  var updatedAtMillis: Int64
  var errorCode: String?

  init(
    modelId: String,
    requestId: String,
    status: VoiceWhisperModelDownloadStatus,
    progress: Int = 0,
    downloadedBytes: Int64 = 0,
    totalBytes: Int64 = 0,
    updatedAtMillis: Int64,
    errorCode: String? = nil
  ) {
    self.modelId = VoiceWhisperModelCatalog.normalizedModelId(modelId)
    self.requestId = requestId.trimmingCharacters(in: .whitespacesAndNewlines)
    self.status = status
    self.progress = min(max(progress, 0), 100)
    self.downloadedBytes = max(0, downloadedBytes)
    self.totalBytes = max(0, totalBytes)
    self.updatedAtMillis = max(0, updatedAtMillis)
    self.errorCode = errorCode?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
  }

  var state: VoiceWhisperModelDownloadState {
    VoiceWhisperModelDownloadState(status: status, progress: progress)
  }

  enum CodingKeys: String, CodingKey {
    case modelId = "model_id"
    case requestId = "request_id"
    case status
    case progress
    case downloadedBytes = "downloaded_bytes"
    case totalBytes = "total_bytes"
    case updatedAtMillis = "updated_at_millis"
    case errorCode = "error_code"
  }
}

struct VoiceWhisperModelDownloadRequest: Equatable {
  var requestId: String
  var model: VoiceWhisperModelProfile
  var sourceURL: URL
  var destinationURL: URL
  var allowsCellularAccess: Bool
  var createdAtMillis: Int64
}

enum VoiceWhisperModelManagerError: LocalizedError, Equatable {
  case bundledModelDoesNotNeedDownload(String)
  case missingDownloadURL(String)
  case temporaryFileMissing
  case downloadedFileTooSmall(modelId: String, bytes: Int64)

  var errorDescription: String? {
    switch self {
    case .bundledModelDoesNotNeedDownload(let modelId):
      return "Bundled Whisper model does not need downloading: \(modelId)"
    case .missingDownloadURL(let modelId):
      return "Whisper model download URL is missing: \(modelId)"
    case .temporaryFileMissing:
      return "Completed Whisper model temporary file is missing."
    case .downloadedFileTooSmall(let modelId, let bytes):
      return "Downloaded Whisper model is too small: \(modelId), \(bytes) bytes"
    }
  }
}

protocol VoiceWhisperModelDownloadRecordStore {
  func record(for modelId: String) -> VoiceWhisperModelDownloadRecord?
  func save(_ record: VoiceWhisperModelDownloadRecord)
  func remove(modelId: String)
}

final class UserDefaultsVoiceWhisperModelDownloadRecordStore: VoiceWhisperModelDownloadRecordStore {
  private let defaults: UserDefaults
  private let key: String

  init(
    defaults: UserDefaults = .standard,
    key: String = "signalasi.voice.whisper_model_downloads.v1"
  ) {
    self.defaults = defaults
    self.key = key
  }

  func record(for modelId: String) -> VoiceWhisperModelDownloadRecord? {
    records()[VoiceWhisperModelCatalog.normalizedModelId(modelId)]
  }

  func save(_ record: VoiceWhisperModelDownloadRecord) {
    var values = records()
    values[record.modelId] = record
    persist(values)
  }

  func remove(modelId: String) {
    var values = records()
    values.removeValue(forKey: VoiceWhisperModelCatalog.normalizedModelId(modelId))
    persist(values)
  }

  private func records() -> [String: VoiceWhisperModelDownloadRecord] {
    guard let data = defaults.data(forKey: key),
          let values = try? JSONDecoder().decode([String: VoiceWhisperModelDownloadRecord].self, from: data) else {
      return [:]
    }
    return values
  }

  private func persist(_ records: [String: VoiceWhisperModelDownloadRecord]) {
    defaults.set(try? JSONEncoder().encode(records), forKey: key)
  }
}

final class VoiceWhisperModelManager {
  private let store: VoiceWhisperModelDownloadRecordStore
  private let fileManager: FileManager
  private let modelsDirectory: URL
  private let bundle: Bundle
  private let requestIdFactory: () -> String
  private let clockMillis: () -> Int64

  init(
    store: VoiceWhisperModelDownloadRecordStore = UserDefaultsVoiceWhisperModelDownloadRecordStore(),
    fileManager: FileManager = .default,
    modelsDirectory: URL = VoiceWhisperModelCatalog.defaultModelsDirectory(),
    bundle: Bundle = .main,
    requestIdFactory: @escaping () -> String = { UUID().uuidString },
    clockMillis: @escaping () -> Int64 = VoiceWhisperModelManager.defaultClockMillis
  ) {
    self.store = store
    self.fileManager = fileManager
    self.modelsDirectory = modelsDirectory
    self.bundle = bundle
    self.requestIdFactory = requestIdFactory
    self.clockMillis = clockMillis
  }

  func downloadedFileURL(for model: VoiceWhisperModelProfile) -> URL {
    VoiceWhisperModelCatalog.downloadedFileURL(for: model, modelsDirectory: modelsDirectory)
  }

  func downloadState(for model: VoiceWhisperModelProfile) -> VoiceWhisperModelDownloadState {
    if model.bundled, bundledResourceExists(for: model) {
      return VoiceWhisperModelDownloadState(status: .successful, progress: 100)
    }
    return store.record(for: model.id)?.state ?? VoiceWhisperModelDownloadState(status: .notRequested)
  }

  func isAvailable(_ model: VoiceWhisperModelProfile) -> Bool {
    VoiceWhisperModelCatalog.isAvailable(
      model,
      bundledResourceExists: bundledResourceExists(for: model),
      downloadedFileBytes: downloadedFileBytes(for: model),
      downloadState: downloadState(for: model)
    )
  }

  func enqueue(
    _ model: VoiceWhisperModelProfile,
    allowsCellularAccess: Bool = true
  ) throws -> VoiceWhisperModelDownloadRequest {
    guard !model.bundled else {
      throw VoiceWhisperModelManagerError.bundledModelDoesNotNeedDownload(model.id)
    }
    guard let sourceURL = VoiceWhisperModelCatalog.downloadURL(for: model) else {
      throw VoiceWhisperModelManagerError.missingDownloadURL(model.id)
    }
    if let current = store.record(for: model.id),
       [.pending, .running, .paused].contains(current.status),
       !current.requestId.isEmpty {
      return request(
        for: model,
        sourceURL: sourceURL,
        requestId: current.requestId,
        allowsCellularAccess: allowsCellularAccess,
        createdAtMillis: current.updatedAtMillis
      )
    }
    try prepareDirectory()
    try? fileManager.removeItem(at: downloadedFileURL(for: model))
    let record = VoiceWhisperModelDownloadRecord(
      modelId: model.id,
      requestId: requestIdFactory(),
      status: .pending,
      updatedAtMillis: clockMillis()
    )
    store.save(record)
    return request(
      for: model,
      sourceURL: sourceURL,
      requestId: record.requestId,
      allowsCellularAccess: allowsCellularAccess,
      createdAtMillis: record.updatedAtMillis
    )
  }

  @discardableResult
  func recordProgress(
    _ model: VoiceWhisperModelProfile,
    downloadedBytes: Int64,
    totalBytes: Int64
  ) -> VoiceWhisperModelDownloadState {
    let progress = totalBytes > 0 ? Int((max(0, downloadedBytes) * 100) / max(1, totalBytes)) : 0
    let current = store.record(for: model.id)
    let record = VoiceWhisperModelDownloadRecord(
      modelId: model.id,
      requestId: current?.requestId ?? requestIdFactory(),
      status: .running,
      progress: progress,
      downloadedBytes: downloadedBytes,
      totalBytes: totalBytes,
      updatedAtMillis: clockMillis()
    )
    store.save(record)
    return record.state
  }

  @discardableResult
  func recordPaused(_ model: VoiceWhisperModelProfile) -> VoiceWhisperModelDownloadState {
    let record = recordWithStatus(model, status: .paused, progressFallback: downloadState(for: model).progress)
    store.save(record)
    return record.state
  }

  @discardableResult
  func recordFailure(
    _ model: VoiceWhisperModelProfile,
    errorCode: String
  ) -> VoiceWhisperModelDownloadState {
    let record = recordWithStatus(
      model,
      status: .failed,
      progressFallback: downloadState(for: model).progress,
      errorCode: errorCode
    )
    store.save(record)
    return record.state
  }

  @discardableResult
  func recordCompleted(
    _ model: VoiceWhisperModelProfile,
    temporaryFileURL: URL? = nil
  ) throws -> VoiceWhisperModelDownloadState {
    try prepareDirectory()
    let destination = downloadedFileURL(for: model)
    if let temporaryFileURL = temporaryFileURL {
      guard fileManager.fileExists(atPath: temporaryFileURL.path) else {
        throw VoiceWhisperModelManagerError.temporaryFileMissing
      }
      try? fileManager.removeItem(at: destination)
      try fileManager.moveItem(at: temporaryFileURL, to: destination)
    }
    let bytes = downloadedFileBytes(for: model) ?? 0
    guard bytes >= model.minimumUsableBytes else {
      _ = recordFailure(model, errorCode: "MODEL_FILE_TOO_SMALL")
      throw VoiceWhisperModelManagerError.downloadedFileTooSmall(modelId: model.id, bytes: bytes)
    }
    let record = VoiceWhisperModelDownloadRecord(
      modelId: model.id,
      requestId: store.record(for: model.id)?.requestId ?? requestIdFactory(),
      status: .successful,
      progress: 100,
      downloadedBytes: bytes,
      totalBytes: bytes,
      updatedAtMillis: clockMillis()
    )
    store.save(record)
    return record.state
  }

  @discardableResult
  func delete(_ model: VoiceWhisperModelProfile) -> Bool {
    let destination = downloadedFileURL(for: model)
    let hadState = store.record(for: model.id) != nil
    let hadFile = fileManager.fileExists(atPath: destination.path)
    if hadFile {
      try? fileManager.removeItem(at: destination)
    }
    store.remove(modelId: model.id)
    return hadState || hadFile
  }

  private func request(
    for model: VoiceWhisperModelProfile,
    sourceURL: URL,
    requestId: String,
    allowsCellularAccess: Bool,
    createdAtMillis: Int64
  ) -> VoiceWhisperModelDownloadRequest {
    VoiceWhisperModelDownloadRequest(
      requestId: requestId,
      model: model,
      sourceURL: sourceURL,
      destinationURL: downloadedFileURL(for: model),
      allowsCellularAccess: allowsCellularAccess,
      createdAtMillis: createdAtMillis
    )
  }

  private func recordWithStatus(
    _ model: VoiceWhisperModelProfile,
    status: VoiceWhisperModelDownloadStatus,
    progressFallback: Int,
    errorCode: String? = nil
  ) -> VoiceWhisperModelDownloadRecord {
    let current = store.record(for: model.id)
    return VoiceWhisperModelDownloadRecord(
      modelId: model.id,
      requestId: current?.requestId ?? requestIdFactory(),
      status: status,
      progress: progressFallback,
      downloadedBytes: current?.downloadedBytes ?? 0,
      totalBytes: current?.totalBytes ?? 0,
      updatedAtMillis: clockMillis(),
      errorCode: errorCode
    )
  }

  private func prepareDirectory() throws {
    try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
  }

  private func downloadedFileBytes(for model: VoiceWhisperModelProfile) -> Int64? {
    let url = downloadedFileURL(for: model)
    guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
          let size = attributes[.size] as? NSNumber else {
      return nil
    }
    return size.int64Value
  }

  private func bundledResourceExists(for model: VoiceWhisperModelProfile) -> Bool {
    bundle.url(
      forResource: model.fileName.deletingPathExtensionForWhisperManager,
      withExtension: model.fileName.nonBlankPathExtensionForWhisperManager
    ) != nil
  }

  private static func defaultClockMillis() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1_000)
  }
}

private extension String {
  var deletingPathExtensionForWhisperManager: String {
    (self as NSString).deletingPathExtension
  }

  var nonBlankPathExtensionForWhisperManager: String? {
    let value = (self as NSString).pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }

  var nilIfBlank: String? {
    isEmpty ? nil : self
  }
}
