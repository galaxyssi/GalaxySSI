import XCTest
@testable import GalaxySSI

final class VoiceWhisperModelCatalogTests: XCTestCase {
  func testCatalogMatchesAndroidWhisperModelChoices() {
    XCTAssertEqual(
      VoiceWhisperModelCatalog.models.map(\.id),
      [
        "tiny",
        "tiny_q5_1",
        "base",
        "base_q5_1",
        "small",
        "small_q5_1",
        "medium",
        "medium_q5_0",
        "large",
        "large_v3_q5_0",
        "large_v3_turbo",
        "large_v3_turbo_q5_0",
        "whisper-tiny-qnn-float-s26u",
        "whisper-base-qnn-float-s26u",
        "whisper-small-qnn-w8a16-s26u",
        "whisper-small-qnn-float-s26u",
      ]
    )
    XCTAssertEqual(VoiceWhisperModelCatalog.model("BASE").fileName, "ggml-base.bin")
    XCTAssertEqual(VoiceWhisperModelCatalog.model("large-v3").id, "large")
    XCTAssertEqual(VoiceWhisperModelCatalog.model("large_v3").id, "large")
    XCTAssertEqual(VoiceWhisperModelCatalog.model("tiny_q5_1").quantization, .q5_1)
    XCTAssertEqual(VoiceWhisperModelCatalog.model("large_v3_turbo_q5_0").recommendedMode, .secondPass)
    XCTAssertEqual(VoiceWhisperModelCatalog.model("unknown").id, "tiny")
    XCTAssertEqual(VoiceWhisperModelCatalog.normalizedModelId(" medium "), "medium")
    XCTAssertEqual(VoiceWhisperModelCatalog.model("large").family, .largeV3)
    XCTAssertEqual(VoiceWhisperModelCatalog.model("base").sourceURLs.count, 2)
    XCTAssertEqual(VoiceWhisperModelCatalog.downloadURL(for: VoiceWhisperModelCatalog.model("large"))?.absoluteString,
                   "https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin")
  }

  func testAndroidQnnProfilesRemainVisibleButUnavailableOnIOS() {
    let qnn = VoiceWhisperModelCatalog.model("whisper-tiny-qnn-float-s26u")

    XCTAssertEqual(qnn.artifactFormat, .qnnContextBinary)
    XCTAssertEqual(qnn.targetChipset, "qualcomm-snapdragon-8-elite-gen5-for-galaxy")
    XCTAssertFalse(qnn.supportsIOSRuntime)
    XCTAssertNil(VoiceWhisperModelCatalog.downloadURL(for: qnn))
    XCTAssertFalse(
      VoiceWhisperModelCatalog.isAvailable(
        qnn,
        bundledResourceExists: true,
        downloadedFileBytes: qnn.expectedSizeBytes
      )
    )
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
