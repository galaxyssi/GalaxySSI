import XCTest
@testable import GalaxySSI

final class MicrosoftTTSVoiceCatalogTests: XCTestCase {
  func testCatalogMatchesAndroidXiaoxiaoChoices() {
    XCTAssertEqual(
      MicrosoftTTSVoiceCatalog.voices,
      [
        "zh-CN-XiaoxiaoNeural",
        "zh-CN-Xiaoxiao:DragonHDFlashLatestNeural",
        "zh-CN-Xiaoxiao2:DragonHDFlashLatestNeural",
      ]
    )
  }

  func testCanonicalKeepsSupportedVoiceAndFallsBackForUnknownVoice() {
    XCTAssertEqual(
      MicrosoftTTSVoiceCatalog.canonical(" ZH-CN-XIAOXIAO:DRAGONHDFLASHLATESTNEURAL "),
      MicrosoftTTSVoiceCatalog.xiaoxiaoDragonHDFlash
    )
    XCTAssertEqual(
      MicrosoftTTSVoiceCatalog.canonical("en-US-AriaNeural"),
      MicrosoftTTSVoiceCatalog.xiaoxiao
    )
  }
}
