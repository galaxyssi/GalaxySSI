import XCTest
@testable import GalaxySSI

final class VoiceWhisperModelDownloadPolicyTests: XCTestCase {
  func testLargeModelsRequireMeteredConfirmationButTinyDoesNot() {
    let free = Int64.max

    XCTAssertEqual(
      VoiceWhisperModelDownloadPolicy.evaluate(
        profile: VoiceWhisperModelCatalog.model("large_v3_turbo_q5_0"),
        network: .metered,
        availableFreeBytes: free
      ).decision,
      .requireMeteredConfirmation
    )
    XCTAssertEqual(
      VoiceWhisperModelDownloadPolicy.evaluate(
        profile: VoiceWhisperModelCatalog.model("large_v3_turbo_q5_0"),
        network: .metered,
        availableFreeBytes: free,
        meteredConfirmed: true
      ).decision,
      .allow
    )
    XCTAssertEqual(
      VoiceWhisperModelDownloadPolicy.evaluate(
        profile: VoiceWhisperModelCatalog.model("tiny"),
        network: .metered,
        availableFreeBytes: free
      ).decision,
      .allow
    )
  }

  func testOfflineAndInsufficientSpaceAreRejectedBeforeDownload() {
    let profile = VoiceWhisperModelCatalog.model("medium")

    XCTAssertEqual(
      VoiceWhisperModelDownloadPolicy.evaluate(
        profile: profile,
        network: .offline,
        availableFreeBytes: Int64.max
      ).decision,
      .waitForNetwork
    )

    let result = VoiceWhisperModelDownloadPolicy.evaluate(
      profile: profile,
      network: .wifi,
      availableFreeBytes: 1
    )
    XCTAssertEqual(result.decision, .insufficientSpace)
    XCTAssertGreaterThan(result.requiredFreeBytes, profile.expectedSizeBytes)
  }

  func testSourcePriorityFollowsLocaleWithoutChangingTrustList() {
    let profile = VoiceWhisperModelCatalog.model("base")
    let chinese = VoiceWhisperModelDownloadPolicy.orderedSources(
      profile: profile,
      locale: Locale(identifier: "zh_CN")
    )
    let english = VoiceWhisperModelDownloadPolicy.orderedSources(
      profile: profile,
      locale: Locale(identifier: "en_US")
    )

    XCTAssertTrue(chinese.first?.contains("hf-mirror.com") == true)
    XCTAssertTrue(english.first?.contains("huggingface.co") == true)
    XCTAssertEqual(Set(chinese), Set(profile.sourceURLs))
    XCTAssertEqual(Set(english), Set(profile.sourceURLs))
  }

  func testCatalogLocaleDownloadURLUsesPolicyOrder() {
    XCTAssertEqual(
      VoiceWhisperModelCatalog.downloadURL(
        for: VoiceWhisperModelCatalog.model("base"),
        locale: Locale(identifier: "en_US")
      )?.host,
      "huggingface.co"
    )
    XCTAssertEqual(
      VoiceWhisperModelCatalog.downloadURL(
        for: VoiceWhisperModelCatalog.model("base"),
        locale: Locale(identifier: "zh_CN")
      )?.host,
      "hf-mirror.com"
    )
  }
}
