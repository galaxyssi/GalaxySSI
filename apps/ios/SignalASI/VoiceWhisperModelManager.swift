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
  case installFailed(modelId: String, failure: VoiceWhisperModelInstallFailure)

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
    case .installFailed(let modelId, let failure):
      return "Whisper model install failed: \(modelId), \(failure.rawValue)"
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
  private let storage: VoiceWhisperModelStorage
  private let bundle: Bundle
  private let sourceLocale: Locale
  private let requestIdFactory: () -> String
  private let clockMillis: () -> Int64

  init(
    store: VoiceWhisperModelDownloadRecordStore = UserDefaultsVoiceWhisperModelDownloadRecordStore(),
    fileManager: FileManager = .default,
    modelsDirectory: URL = VoiceWhisperModelCatalog.defaultModelsDirectory(),
    storage: VoiceWhisperModelStorage? = nil,
    bundle: Bundle = .main,
    sourceLocale: Locale = .current,
    requestIdFactory: @escaping () -> String = { UUID().uuidString },
    clockMillis: @escaping () -> Int64 = VoiceWhisperModelManager.defaultClockMillis
  ) {
    self.store = store
    self.fileManager = fileManager
    self.modelsDirectory = modelsDirectory
    self.storage = storage ?? VoiceWhisperModelStorage(
      rootDirectory: modelsDirectory,
      fileManager: fileManager,
      clockMillis: clockMillis
    )
    self.bundle = bundle
    self.sourceLocale = sourceLocale
    self.requestIdFactory = requestIdFactory
    self.clockMillis = clockMillis
  }

  func downloadedFileURL(for model: VoiceWhisperModelProfile) -> URL {
    storage.finalFileURL(for: model)
  }

  func downloadState(for model: VoiceWhisperModelProfile) -> VoiceWhisperModelDownloadState {
    if model.bundled, bundledResourceExists(for: model) {
      return VoiceWhisperModelDownloadState(status: .successful, progress: 100)
    }
    _ = migrateLegacyInstallIfNeeded(model)
    let snapshot = storage.inspect(model)
    if snapshot.installed {
      return VoiceWhisperModelDownloadState(status: .successful, progress: 100)
    }
    return store.record(for: model.id)?.state ?? VoiceWhisperModelDownloadState(status: .notRequested)
  }

  func isAvailable(_ model: VoiceWhisperModelProfile) -> Bool {
    if model.bundled, bundledResourceExists(for: model) {
      return true
    }
    _ = migrateLegacyInstallIfNeeded(model)
    return storage.inspect(model).installed
  }

  func enqueue(
    _ model: VoiceWhisperModelProfile,
    allowsCellularAccess: Bool = true
  ) throws -> VoiceWhisperModelDownloadRequest {
    guard !model.bundled else {
      throw VoiceWhisperModelManagerError.bundledModelDoesNotNeedDownload(model.id)
    }
    guard let sourceURL = VoiceWhisperModelCatalog.downloadURL(for: model, locale: sourceLocale) else {
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
    storage.invalidate(model)
    removeLegacyCandidates(for: model)
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
    guard let temporaryFileURL = temporaryFileURL else {
      if storage.inspect(model).installed {
        return VoiceWhisperModelDownloadState(status: .successful, progress: 100)
      }
      throw VoiceWhisperModelManagerError.temporaryFileMissing
    }
    guard fileManager.fileExists(atPath: temporaryFileURL.path) else {
      throw VoiceWhisperModelManagerError.temporaryFileMissing
    }
    let metadata: VoiceWhisperModelInstallMetadata
    do {
      metadata = try storage.install(
        sourceFileURL: temporaryFileURL,
        profile: model,
        sourceLabel: "download:\(temporaryFileURL.lastPathComponent)"
      )
    } catch let error as VoiceWhisperModelInstallError {
      _ = recordFailure(model, errorCode: error.failure.rawValue)
      if error.failure == .sizeMismatch {
        throw VoiceWhisperModelManagerError.downloadedFileTooSmall(
          modelId: model.id,
          bytes: downloadedFileBytes(at: temporaryFileURL) ?? 0
        )
      }
      throw VoiceWhisperModelManagerError.installFailed(modelId: model.id, failure: error.failure)
    }
    let record = VoiceWhisperModelDownloadRecord(
      modelId: model.id,
      requestId: store.record(for: model.id)?.requestId ?? requestIdFactory(),
      status: .successful,
      progress: 100,
      downloadedBytes: metadata.expectedSizeBytes,
      totalBytes: metadata.expectedSizeBytes,
      updatedAtMillis: clockMillis()
    )
    store.save(record)
    return record.state
  }

  @discardableResult
  func delete(_ model: VoiceWhisperModelProfile) -> Bool {
    (try? delete(model, active: false)) ?? false
  }

  @discardableResult
  func delete(_ model: VoiceWhisperModelProfile, active: Bool) throws -> Bool {
    let hadState = store.record(for: model.id) != nil
    let hadInstall = storage.inspect(model).state != .notInstalled
    do {
      _ = try storage.delete(model, active: active)
    } catch let error as VoiceWhisperModelInstallError {
      throw VoiceWhisperModelManagerError.installFailed(modelId: model.id, failure: error.failure)
    }
    store.remove(modelId: model.id)
    return hadState || hadInstall
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

  @discardableResult
  private func migrateLegacyInstallIfNeeded(_ model: VoiceWhisperModelProfile) -> VoiceWhisperLegacyMigrationResult {
    VoiceWhisperLegacyMigration.migrate(
      profile: model,
      candidates: legacyModelCandidates(for: model),
      storage: storage,
      fileManager: fileManager,
      deleteMigratedSource: true
    )
  }

  private func legacyModelCandidates(for model: VoiceWhisperModelProfile) -> [URL] {
    [
      modelsDirectory.appendingPathComponent(model.fileName, isDirectory: false),
      VoiceWhisperModelCatalog.downloadedFileURL(for: model, modelsDirectory: modelsDirectory)
    ]
  }

  private func removeLegacyCandidates(for model: VoiceWhisperModelProfile) {
    let currentURL = downloadedFileURL(for: model).standardizedFileURL.path
    for candidate in legacyModelCandidates(for: model) where candidate.standardizedFileURL.path != currentURL {
      try? fileManager.removeItem(at: candidate)
    }
  }

  private func downloadedFileBytes(for model: VoiceWhisperModelProfile) -> Int64? {
    downloadedFileBytes(at: downloadedFileURL(for: model))
  }

  private func downloadedFileBytes(at url: URL) -> Int64? {
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
