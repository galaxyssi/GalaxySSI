import XCTest
@testable import GalaxySSI

final class VoiceWhisperModelSettingsTests: XCTestCase {
  func testPresenterMatchesAndroidStyleModelActions() {
    let tiny = VoiceWhisperModelCatalog.model("tiny")
    let base = VoiceWhisperModelCatalog.model("base")
    let small = VoiceWhisperModelCatalog.model("small")
    let medium = VoiceWhisperModelCatalog.model("medium")
    let large = VoiceWhisperModelCatalog.model("large")

    let rows = VoiceWhisperModelSettingsPresenter.rows(
      selectedModelId: "tiny",
      downloadState: { model in
        switch model.id {
        case base.id:
          return VoiceWhisperModelDownloadState(status: .successful, progress: 100)
        case small.id:
          return VoiceWhisperModelDownloadState(status: .running, progress: 42)
        case medium.id:
          return VoiceWhisperModelDownloadState(status: .failed, progress: 12)
        default:
          return VoiceWhisperModelDownloadState(status: .notRequested)
        }
      },
      isAvailable: { $0.id == tiny.id || $0.id == base.id },
      activeDownloadIds: [large.id]
    )

    XCTAssertEqual(rows.map(\.model.id), VoiceWhisperModelCatalog.models.map(\.id))
    XCTAssertEqual(rows.first { $0.model.id == tiny.id }?.action, .useAndTest)
    XCTAssertEqual(rows.first { $0.model.id == base.id }?.action, .useAndTest)
    XCTAssertEqual(rows.first { $0.model.id == small.id }?.action, .waiting(progress: 42))
    XCTAssertEqual(rows.first { $0.model.id == medium.id }?.action, .retry)
    XCTAssertEqual(rows.first { $0.model.id == large.id }?.action, .waiting(progress: 0))
    XCTAssertEqual(rows.first { $0.model.id == tiny.id }?.detail.contains("Included with the app"), true)
    XCTAssertEqual(rows.first { $0.model.id == base.id }?.detail.contains(base.quantization.rawValue), true)
    XCTAssertEqual(rows.first { $0.model.id == base.id }?.detail.contains("Benchmark required"), true)
    XCTAssertEqual(rows.first { $0.model.id == small.id }?.detail.contains("Downloading 42%"), true)
    XCTAssertEqual(rows.first { $0.model.id == medium.id }?.detail.contains("Install failed"), true)
    XCTAssertEqual(rows.first { $0.model.id == large.id }?.detail.contains("Waiting to download"), true)
    XCTAssertEqual(rows.first { $0.model.id == base.id }?.removable, true)
    XCTAssertEqual(rows.first { $0.model.id == tiny.id }?.removable, false)
    XCTAssertEqual(rows.first { $0.model.id == small.id }?.removable, false)
  }

  func testPresenterDoesNotOfferRemoveForSelectedDownloadedModel() {
    let base = VoiceWhisperModelCatalog.model("base")
    let rows = VoiceWhisperModelSettingsPresenter.rows(
      selectedModelId: base.id,
      downloadState: { _ in VoiceWhisperModelDownloadState(status: .successful, progress: 100) },
      isAvailable: { $0.id == base.id },
      benchmarkRecord: { model in
        model.id == base.id ? Self.benchmarkRecord(for: model, level: .realtime) : nil
      }
    )

    XCTAssertEqual(rows.first { $0.model.id == base.id }?.action, .current)
    XCTAssertEqual(rows.first { $0.model.id == base.id }?.removable, false)
  }

  func testPresenterShowsBenchmarkCertificationProgressAndStaleStates() {
    let tiny = VoiceWhisperModelCatalog.model("tiny")
    let base = VoiceWhisperModelCatalog.model("base")
    let small = VoiceWhisperModelCatalog.model("small")
    let rows = VoiceWhisperModelSettingsPresenter.rows(
      models: [tiny, base, small],
      selectedModelId: "tiny",
      downloadState: { _ in VoiceWhisperModelDownloadState(status: .successful, progress: 100) },
      isAvailable: { _ in true },
      benchmarkRecord: { model in
        model.id == tiny.id ? Self.benchmarkRecord(for: model, level: .realtime) : nil
      },
      latestBenchmarkRecord: { model in
        model.id == base.id ? Self.benchmarkRecord(for: model, level: .final) : nil
      },
      benchmarkProgress: { model in
        if model.id == small.id {
          return VoiceWhisperBenchmarkProgress(stage: .searchingThreads, completedSteps: 3, totalSteps: 6)
        }
        return nil
      }
    )

    XCTAssertEqual(rows.first { $0.model.id == tiny.id }?.action, .current)
    XCTAssertEqual(rows.first { $0.model.id == tiny.id }?.detail.contains("Real-time certified"), true)
    XCTAssertEqual(rows.first { $0.model.id == base.id }?.action, .useAndTest)
    XCTAssertEqual(rows.first { $0.model.id == base.id }?.detail.contains("Previous result is stale"), true)
    XCTAssertEqual(rows.first { $0.model.id == small.id }?.action, .waiting(progress: 50))
    XCTAssertEqual(rows.first { $0.model.id == small.id }?.detail.contains("Searching threads 50%"), true)
  }

  func testDownloadServiceCompletesModelThroughInjectedDownloader() async throws {
    let env = try Environment()
    let model = env.testModel(minimumBytes: 8)
    let manager = env.manager(requestId: "download-1")
    let downloader = FakeDownloader(
      result: .success(
        VoiceWhisperModelDownloadedFile(
          temporaryFileURL: try env.writeTemporaryFile(bytes: 8),
          statusCode: 200,
          byteCount: 8
        )
      )
    )
    let service = VoiceWhisperModelDownloadService(manager: manager, downloader: downloader)

    let state = try await service.start(model, allowsCellularAccess: false)

    XCTAssertEqual(state, VoiceWhisperModelDownloadState(status: .successful, progress: 100))
    XCTAssertEqual(downloader.requests.first?.requestId, "download-1")
    XCTAssertFalse(downloader.requests.first?.allowsCellularAccess ?? true)
    XCTAssertEqual(downloader.requests.count, 1)
    XCTAssertTrue(manager.isAvailable(model))
  }

  func testDownloadServiceRetriesNextTrustedSourceAfterHttpFailure() async throws {
    let env = try Environment()
    let model = env.testModel(minimumBytes: 8)
    let manager = env.manager(requestId: "download-retry")
    let downloader = FakeDownloader(
      results: [
        .success(
          VoiceWhisperModelDownloadedFile(
            temporaryFileURL: try env.writeTemporaryFile(bytes: 8),
            statusCode: 503,
            byteCount: 8
          )
        ),
        .success(
          VoiceWhisperModelDownloadedFile(
            temporaryFileURL: try env.writeTemporaryFile(bytes: 8),
            statusCode: 200,
            byteCount: 8
          )
        ),
      ]
    )
    let service = VoiceWhisperModelDownloadService(manager: manager, downloader: downloader)

    let state = try await service.start(model)

    XCTAssertEqual(state, VoiceWhisperModelDownloadState(status: .successful, progress: 100))
    XCTAssertEqual(downloader.requests.compactMap(\.sourceURL.host), ["hf-mirror.com", "huggingface.co"])
    XCTAssertEqual(Set(downloader.requests.map(\.requestId)), ["download-retry"])
    XCTAssertTrue(manager.isAvailable(model))
  }

  func testDownloadServiceRecordsHttpFailure() async throws {
    let env = try Environment()
    let model = env.testModel(minimumBytes: 8)
    let manager = env.manager(requestId: "download-2")
    let downloader = FakeDownloader(
      result: .success(
        VoiceWhisperModelDownloadedFile(
          temporaryFileURL: try env.writeTemporaryFile(bytes: 8),
          statusCode: 503,
          byteCount: 8
        )
      )
    )
    let service = VoiceWhisperModelDownloadService(manager: manager, downloader: downloader)

    do {
      _ = try await service.start(model)
      XCTFail("Expected HTTP failure")
    } catch {
      XCTAssertEqual(error as? VoiceWhisperModelDownloadServiceError, .httpStatus(503))
    }
    XCTAssertEqual(downloader.requests.count, 2)
    XCTAssertEqual(manager.downloadState(for: model).status, .failed)
    XCTAssertFalse(manager.isAvailable(model))
  }

  private final class FakeDownloader: VoiceWhisperModelDownloading {
    var requests: [VoiceWhisperModelDownloadRequest] = []
    var results: [Result<VoiceWhisperModelDownloadedFile, Error>]

    init(result: Result<VoiceWhisperModelDownloadedFile, Error>) {
      self.results = [result]
    }

    init(results: [Result<VoiceWhisperModelDownloadedFile, Error>]) {
      self.results = results
    }

    func download(_ request: VoiceWhisperModelDownloadRequest) async throws -> VoiceWhisperModelDownloadedFile {
      requests.append(request)
      if results.count > 1 {
        return try results.removeFirst().get()
      }
      return try XCTUnwrap(results.first).get()
    }
  }

  private static func benchmarkRecord(
    for model: VoiceWhisperModelProfile,
    level: VoiceWhisperCertificationLevel
  ) -> VoiceWhisperBenchmarkRecord {
    VoiceWhisperBenchmarkRecord(
      certification: VoiceWhisperCertification(
        key: VoiceWhisperBenchmarkKey(
          manufacturer: "Apple",
          device: "iPhone",
          soc: "A17",
          osVersion: "17.0",
          appVersionCode: 1,
          whisperNativeVersion: "test",
          nativeBuildFingerprint: "test",
          modelProfileId: model.id,
          modelSha256: model.sha256,
          benchmarkAudioVersion: "test"
        ),
        level: level,
        recommendedMode: level == .realtime ? .realtimePartial : .finalOnly,
        recommendedThreadCount: 4,
        recommendedPartialIntervalMillis: model.defaultPartialIntervalMillis,
        warmRtfP50: 0.25,
        warmRtfP95: 0.5,
        createdAtEpochMillis: 2_000
      )
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
      defaultsSuiteName = "VoiceWhisperModelSettingsTests-\(UUID().uuidString)"
      defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
      defaults.removePersistentDomain(forName: defaultsSuiteName)
      store = UserDefaultsVoiceWhisperModelDownloadRecordStore(defaults: defaults)
    }

    func manager(requestId: String) -> VoiceWhisperModelManager {
      VoiceWhisperModelManager(
        store: store,
        modelsDirectory: models,
        sourceLocale: Locale(identifier: "zh_CN"),
        availableFreeBytes: { -1 },
        requestIdFactory: { requestId },
        clockMillis: { 2_000 }
      )
    }

    func testModel(minimumBytes: Int64) -> VoiceWhisperModelProfile {
      VoiceWhisperModelProfile(
        id: "base",
        displayName: "Base",
        fileName: "ggml-base.bin",
        sizeLabel: "142 MB",
        minimumUsableBytes: minimumBytes,
        expectedSizeBytes: minimumBytes
      )
    }

    func writeTemporaryFile(bytes: Int) throws -> URL {
      let url = root.appendingPathComponent(UUID().uuidString)
      try Data(repeating: 7, count: bytes).write(to: url)
      return url
    }
  }
}
