import XCTest
@testable import GalaxySSI

final class LanguagePolicySettingsTests: XCTestCase {
  func testAutomaticInterfaceLanguageUsesChineseSystemLanguage() {
    XCTAssertEqual(
      LanguagePolicySettings.automaticInterfaceLanguage(
        locale: Locale(identifier: "zh_Hans_US"),
        timeZone: Self.timeZone("America/Los_Angeles")
      ),
      LanguagePolicySettings.zhCN
    )
  }

  func testAutomaticInterfaceLanguageUsesChineseRegion() {
    XCTAssertEqual(
      LanguagePolicySettings.automaticInterfaceLanguage(
        locale: Locale(identifier: "en_CN"),
        timeZone: Self.timeZone("America/Los_Angeles")
      ),
      LanguagePolicySettings.zhCN
    )
  }

  func testAutomaticInterfaceLanguageUsesChineseTimeZoneFallback() {
    XCTAssertEqual(
      LanguagePolicySettings.automaticInterfaceLanguage(
        locale: Locale(identifier: "en_US"),
        timeZone: Self.timeZone("Asia/Shanghai")
      ),
      LanguagePolicySettings.zhCN
    )
  }

  func testAutomaticInterfaceLanguageDefaultsToEnglish() {
    XCTAssertEqual(
      LanguagePolicySettings.automaticInterfaceLanguage(
        locale: Locale(identifier: "en_US"),
        timeZone: Self.timeZone("America/Los_Angeles")
      ),
      LanguagePolicySettings.en
    )
  }

  func testExplicitInterfaceLanguageWinsOverTimeZone() {
    XCTAssertEqual(
      LanguagePolicySettings.resolveInterface(
        LanguagePolicySettings.en,
        locale: Locale(identifier: "zh_CN"),
        timeZone: Self.timeZone("Asia/Shanghai")
      ),
      LanguagePolicySettings.en
    )
  }

  private static func timeZone(_ identifier: String) -> TimeZone {
    guard let timeZone = TimeZone(identifier: identifier) else {
      XCTFail("Missing time zone: \(identifier)")
      return TimeZone(secondsFromGMT: 0)!
    }
    return timeZone
  }
}
