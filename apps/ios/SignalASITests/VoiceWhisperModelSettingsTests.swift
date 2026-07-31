import XCTest
@testable import SignalASI

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
    XCTAssertEqual(rows.first { $0.model.id == tiny.id }?.action, .current)
    XCTAssertEqual(rows.first { $0.model.id == base.id }?.action, .use)
    XCTAssertEqual(rows.first { $0.model.id == small.id }?.action, .waiting(progress: 42))
    XCTAssertEqual(rows.first { $0.model.id == medium.id }?.action, .retry)
    XCTAssertEqual(rows.first { $0.model.id == large.id }?.action, .waiting(progress: 0))
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
    XCTAssertEqual(manager.downloadState(for: model).status, .failed)
    XCTAssertFalse(manager.isAvailable(model))
  }

  private final class FakeDownloader: VoiceWhisperModelDownloading {
    var requests: [VoiceWhisperModelDownloadRequest] = []
    var result: Result<VoiceWhisperModelDownloadedFile, Error>

    init(result: Result<VoiceWhisperModelDownloadedFile, Error>) {
      self.result = result
    }

    func download(_ request: VoiceWhisperModelDownloadRequest) async throws -> VoiceWhisperModelDownloadedFile {
      requests.append(request)
      return try result.get()
    }
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
