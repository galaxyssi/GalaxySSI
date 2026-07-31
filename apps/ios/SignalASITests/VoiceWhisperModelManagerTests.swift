import XCTest
@testable import SignalASI

final class VoiceWhisperModelManagerTests: XCTestCase {
  func testEnqueueCreatesMirrorRequestAndPersistsPendingState() throws {
    let env = try Environment()
    let manager = env.manager(requestId: "download-1", now: 1_000)
    let model = VoiceWhisperModelCatalog.model("base")

    let request = try manager.enqueue(model, allowsCellularAccess: false)
    let duplicate = try manager.enqueue(model, allowsCellularAccess: false)

    XCTAssertEqual(request.requestId, "download-1")
    XCTAssertEqual(duplicate.requestId, "download-1")
    XCTAssertFalse(request.allowsCellularAccess)
    XCTAssertFalse(duplicate.allowsCellularAccess)
    XCTAssertEqual(request.sourceURL.absoluteString, "https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main/ggml-base.bin")
    XCTAssertEqual(request.destinationURL.lastPathComponent, "ggml-base.bin")
    XCTAssertEqual(request.createdAtMillis, 1_000)
    XCTAssertEqual(manager.downloadState(for: model), VoiceWhisperModelDownloadState(status: .pending, progress: 0))
  }

  func testProgressCompletionAndAvailabilityRequireSuccessfulUsableFile() throws {
    let env = try Environment()
    let manager = env.manager(requestId: "download-2")
    let model = testModel(minimumBytes: 8)

    _ = try manager.enqueue(model)
    XCTAssertEqual(
      manager.recordProgress(model, downloadedBytes: 4, totalBytes: 10),
      VoiceWhisperModelDownloadState(status: .running, progress: 40)
    )
    XCTAssertFalse(manager.isAvailable(model))

    let temp = try env.writeTemporaryFile(bytes: 8)
    XCTAssertEqual(
      try manager.recordCompleted(model, temporaryFileURL: temp),
      VoiceWhisperModelDownloadState(status: .successful, progress: 100)
    )

    XCTAssertTrue(manager.isAvailable(model))
    XCTAssertTrue(FileManager.default.fileExists(atPath: manager.downloadedFileURL(for: model).path))
  }

  func testCompletionRejectsTooSmallModelAndRecordsFailure() throws {
    let env = try Environment()
    let manager = env.manager(requestId: "download-3")
    let model = testModel(minimumBytes: 16)

    _ = try manager.enqueue(model)
    let temp = try env.writeTemporaryFile(bytes: 4)

    XCTAssertThrowsError(try manager.recordCompleted(model, temporaryFileURL: temp)) { error in
      XCTAssertEqual(
        error as? VoiceWhisperModelManagerError,
        .downloadedFileTooSmall(modelId: model.id, bytes: 4)
      )
    }
    XCTAssertEqual(manager.downloadState(for: model).status, .failed)
    XCTAssertFalse(manager.isAvailable(model))
  }

  func testAvailabilityMigratesVerifiedLegacyFlatFile() throws {
    let env = try Environment()
    let manager = env.manager(requestId: "download-legacy")
    let model = testModel(minimumBytes: 8)
    let legacy = try env.writeLegacyModelFile(model, bytes: 8)

    XCTAssertTrue(manager.isAvailable(model))
    XCTAssertEqual(manager.downloadState(for: model), VoiceWhisperModelDownloadState(status: .successful, progress: 100))
    XCTAssertTrue(FileManager.default.fileExists(atPath: manager.downloadedFileURL(for: model).path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
  }

  func testDeleteRemovesDownloadedFileAndState() throws {
    let env = try Environment()
    let manager = env.manager(requestId: "download-4")
    let model = testModel(minimumBytes: 4)

    _ = try manager.enqueue(model)
    _ = try manager.recordCompleted(model, temporaryFileURL: try env.writeTemporaryFile(bytes: 8))

    XCTAssertTrue(manager.delete(model))
    XCTAssertEqual(manager.downloadState(for: model), VoiceWhisperModelDownloadState(status: .notRequested))
    XCTAssertFalse(manager.isAvailable(model))
    XCTAssertFalse(FileManager.default.fileExists(atPath: manager.downloadedFileURL(for: model).path))
  }

  func testDeleteProtectsActiveModel() throws {
    let env = try Environment()
    let manager = env.manager(requestId: "download-5")
    let model = testModel(minimumBytes: 8)

    _ = try manager.enqueue(model)
    _ = try manager.recordCompleted(model, temporaryFileURL: try env.writeTemporaryFile(bytes: 8))

    XCTAssertThrowsError(try manager.delete(model, active: true)) { error in
      XCTAssertEqual(
        error as? VoiceWhisperModelManagerError,
        .installFailed(modelId: model.id, failure: .modelInUse)
      )
    }
    XCTAssertTrue(manager.isAvailable(model))
  }

  func testBundledModelDoesNotEnqueueDownload() throws {
    let env = try Environment()
    let manager = env.manager()

    XCTAssertThrowsError(try manager.enqueue(VoiceWhisperModelCatalog.model("tiny"))) { error in
      XCTAssertEqual(
        error as? VoiceWhisperModelManagerError,
        .bundledModelDoesNotNeedDownload("tiny")
      )
    }
  }

  private func testModel(minimumBytes: Int64) -> VoiceWhisperModelProfile {
    VoiceWhisperModelProfile(
      id: "base",
      displayName: "Base",
      fileName: "ggml-base.bin",
      sizeLabel: "142 MB",
      minimumUsableBytes: minimumBytes,
      expectedSizeBytes: minimumBytes
    )
  }

  private final class Environment {
    let root: URL
    let models: URL
    let store: UserDefaultsVoiceWhisperModelDownloadRecordStore
    let defaults: UserDefaults
    let defaultsSuiteName: String

    init() throws {
      root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
      models = root.appendingPathComponent("models", isDirectory: true)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      defaultsSuiteName = "VoiceWhisperModelManagerTests-\(UUID().uuidString)"
      defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
      defaults.removePersistentDomain(forName: defaultsSuiteName)
      store = UserDefaultsVoiceWhisperModelDownloadRecordStore(defaults: defaults)
    }

    func manager(requestId: String = "download", now: Int64 = 2_000) -> VoiceWhisperModelManager {
      VoiceWhisperModelManager(
        store: store,
        modelsDirectory: models,
        sourceLocale: Locale(identifier: "zh_CN"),
        requestIdFactory: { requestId },
        clockMillis: { now }
      )
    }

    func writeTemporaryFile(bytes: Int) throws -> URL {
      let url = root.appendingPathComponent(UUID().uuidString)
      try Data(repeating: 7, count: bytes).write(to: url)
      return url
    }

    func writeLegacyModelFile(_ model: VoiceWhisperModelProfile, bytes: Int) throws -> URL {
      try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
      let url = models.appendingPathComponent(model.fileName, isDirectory: false)
      try Data(repeating: 7, count: bytes).write(to: url)
      return url
    }
  }
}
