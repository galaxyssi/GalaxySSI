import XCTest
@testable import GalaxySSI

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

  func testEnsureVerifiedFileReturnsInstalledModelForNativeLoad() throws {
    let env = try Environment()
    let manager = env.manager(requestId: "download-native")
    let source = try env.writeTemporaryFile(contents: "trusted-model")
    let model = try env.testModel(for: source)

    _ = try manager.enqueue(model)
    _ = try manager.recordCompleted(model, temporaryFileURL: source)

    XCTAssertEqual(try manager.ensureVerifiedFile(for: model), manager.downloadedFileURL(for: model))
  }

  func testEnsureVerifiedFileInvalidatesTamperedModelBeforeNativeLoad() throws {
    let env = try Environment()
    let manager = env.manager(requestId: "download-tampered")
    let source = try env.writeTemporaryFile(contents: "trusted-model")
    let model = try env.testModel(for: source)

    _ = try manager.enqueue(model)
    _ = try manager.recordCompleted(model, temporaryFileURL: source)
    let installed = manager.downloadedFileURL(for: model)
    let priorModified = try FileManager.default.attributesOfItem(atPath: installed.path)[.modificationDate] as? Date
    try Data("corrupt-model".utf8).write(to: installed)
    if let priorModified {
      try FileManager.default.setAttributes([.modificationDate: priorModified], ofItemAtPath: installed.path)
    }

    XCTAssertThrowsError(try manager.ensureVerifiedFile(for: model)) { error in
      XCTAssertEqual(
        error as? VoiceWhisperModelManagerError,
        .installFailed(modelId: model.id, failure: .sha256Mismatch)
      )
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: installed.path))
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

  func testDeleteProtectsManagerMarkedLoadedModel() throws {
    let env = try Environment()
    let manager = env.manager(requestId: "download-loaded")
    let model = testModel(minimumBytes: 8)

    _ = try manager.enqueue(model)
    _ = try manager.recordCompleted(model, temporaryFileURL: try env.writeTemporaryFile(bytes: 8))

    manager.markLoaded(model.id)
    XCTAssertTrue(manager.isLoaded(model.id))
    XCTAssertFalse(manager.delete(model))
    XCTAssertTrue(manager.isAvailable(model))

    manager.markUnloaded(model.id)
    XCTAssertFalse(manager.isLoaded(model.id))
    XCTAssertTrue(manager.delete(model))
    XCTAssertFalse(manager.isAvailable(model))
  }

  func testEnqueueEnforcesDownloadPolicyBeforeStartingRequest() throws {
    let env = try Environment()
    let meteredManager = env.manager(
      requestId: "download-metered",
      network: .metered,
      availableFreeBytes: Int64.max
    )
    let large = VoiceWhisperModelCatalog.model("large_v3_turbo_q5_0")

    XCTAssertThrowsError(try meteredManager.enqueue(large, allowsCellularAccess: false)) { error in
      XCTAssertEqual(
        error as? VoiceWhisperModelManagerError,
        .meteredDownloadConfirmationRequired(modelId: large.id)
      )
    }

    let confirmed = try meteredManager.enqueue(large, allowsCellularAccess: true)
    XCTAssertEqual(confirmed.requestId, "download-metered")

    let lowSpaceManager = env.manager(
      requestId: "download-low-space",
      network: .wifi,
      availableFreeBytes: 1
    )
    let medium = VoiceWhisperModelCatalog.model("medium")
    XCTAssertThrowsError(try lowSpaceManager.enqueue(medium)) { error in
      guard let managerError = error as? VoiceWhisperModelManagerError,
            case let .downloadUnavailable(modelId, decision, _, availableBytes) = managerError else {
        return XCTFail("Expected download unavailable")
      }
      XCTAssertEqual(modelId, medium.id)
      XCTAssertEqual(decision, .insufficientSpace)
      XCTAssertEqual(availableBytes, 1)
    }
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

    func manager(
      requestId: String = "download",
      now: Int64 = 2_000,
      network: VoiceWhisperNetworkClass = .unknown,
      availableFreeBytes: Int64 = -1
    ) -> VoiceWhisperModelManager {
      VoiceWhisperModelManager(
        store: store,
        modelsDirectory: models,
        sourceLocale: Locale(identifier: "zh_CN"),
        networkClass: { network },
        availableFreeBytes: { availableFreeBytes },
        requestIdFactory: { requestId },
        clockMillis: { now }
      )
    }

    func writeTemporaryFile(bytes: Int) throws -> URL {
      let url = root.appendingPathComponent(UUID().uuidString)
      try Data(repeating: 7, count: bytes).write(to: url)
      return url
    }

    func writeTemporaryFile(contents: String) throws -> URL {
      let url = root.appendingPathComponent(UUID().uuidString)
      try Data(contents.utf8).write(to: url)
      return url
    }

    func writeLegacyModelFile(_ model: VoiceWhisperModelProfile, bytes: Int) throws -> URL {
      try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
      let url = models.appendingPathComponent(model.fileName, isDirectory: false)
      try Data(repeating: 7, count: bytes).write(to: url)
      return url
    }

    func testModel(for fileURL: URL) throws -> VoiceWhisperModelProfile {
      VoiceWhisperModelProfile(
        id: "base",
        displayName: "Base",
        fileName: "ggml-base.bin",
        sizeLabel: "142 MB",
        expectedSizeBytes: Int64(try Data(contentsOf: fileURL).count),
        sha256: try VoiceWhisperModelVerifier.sha256(fileURL: fileURL)
      )
    }
  }
}
