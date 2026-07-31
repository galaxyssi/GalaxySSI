import XCTest
@testable import SignalASI

final class VoiceWhisperModelCatalogTests: XCTestCase {
  func testCatalogMatchesAndroidWhisperModelChoices() {
    XCTAssertEqual(VoiceWhisperModelCatalog.models.map(\.id), ["tiny", "base", "small", "medium", "large"])
    XCTAssertEqual(VoiceWhisperModelCatalog.model("BASE").fileName, "ggml-base.bin")
    XCTAssertEqual(VoiceWhisperModelCatalog.model("unknown").id, "tiny")
    XCTAssertEqual(VoiceWhisperModelCatalog.normalizedModelId(" medium "), "medium")
    XCTAssertEqual(VoiceWhisperModelCatalog.model("large").family, .largeV3)
    XCTAssertEqual(VoiceWhisperModelCatalog.model("base").sourceURLs.count, 2)
    XCTAssertEqual(VoiceWhisperModelCatalog.downloadURL(for: VoiceWhisperModelCatalog.model("large"))?.absoluteString,
                   "https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin")
  }

  func testAvailabilityRequiresRealBundledResourceOrCompletedDownload() {
    let tiny = VoiceWhisperModelCatalog.model("tiny")
    let base = VoiceWhisperModelCatalog.model("base")

    XCTAssertTrue(
      VoiceWhisperModelCatalog.isAvailable(tiny, bundledResourceExists: true, downloadedFileBytes: nil)
    )
    XCTAssertFalse(
      VoiceWhisperModelCatalog.isAvailable(tiny, bundledResourceExists: false, downloadedFileBytes: 75_000_000)
    )
    XCTAssertFalse(
      VoiceWhisperModelCatalog.isAvailable(base, bundledResourceExists: false, downloadedFileBytes: 999_999)
    )
    XCTAssertFalse(
      VoiceWhisperModelCatalog.isAvailable(
        base,
        bundledResourceExists: false,
        downloadedFileBytes: 200_000_000,
        downloadState: VoiceWhisperModelDownloadState(status: .running, progress: 50)
      )
    )
    XCTAssertTrue(
      VoiceWhisperModelCatalog.isAvailable(base, bundledResourceExists: false, downloadedFileBytes: 200_000_000)
    )
  }
}
