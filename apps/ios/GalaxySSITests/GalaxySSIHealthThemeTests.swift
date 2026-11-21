import UIKit
import XCTest
@testable import GalaxySSI

@MainActor
final class GalaxySSIHealthThemeTests: XCTestCase {
  func testFeatureMenuMatchesAndroidOrderWithoutDuplicateOverview() {
    XCTAssertEqual(GalaxySSIHealthFeature.allCases.map(\.rawValue), [
      "care", "agenda", "recordCenter", "originals", "manual", "records", "catalog", "weekly",
      "assistant", "sources", "files", "profile", "privacy", "body"
    ])
    XCTAssertEqual(Set(GalaxySSIHealthFeature.allCases.map(\.id)).count, 14)
    for feature in GalaxySSIHealthFeature.allCases {
      XCTAssertFalse(feature.label.key.isEmpty)
      XCTAssertFalse(feature.label.icon.isEmpty)
      XCTAssertFalse(feature.title(language: "en").isEmpty)
      XCTAssertNotEqual(feature.title(language: "zh-Hans"), feature.label.fallback)
    }
  }

  func testAdaptiveAccentAndActionInkMatchAndroidHealthColors() {
    let light = UITraitCollection(userInterfaceStyle: .light), dark = UITraitCollection(userInterfaceStyle: .dark)
    let lightAccent = components(GalaxySSIHealthTheme.accentUIColor.resolvedColor(with: light))
    let darkAccent = components(GalaxySSIHealthTheme.accentUIColor.resolvedColor(with: dark))
    XCTAssertEqual(lightAccent[0], 0, accuracy: 0.001)
    XCTAssertEqual(lightAccent[1], 108.0 / 255, accuracy: 0.001)
    XCTAssertEqual(lightAccent[2], 86.0 / 255, accuracy: 0.001)
    XCTAssertEqual(darkAccent[0], 135.0 / 255, accuracy: 0.001)
    XCTAssertEqual(darkAccent[1], 230.0 / 255, accuracy: 0.001)
    XCTAssertEqual(darkAccent[2], 191.0 / 255, accuracy: 0.001)
    for traits in [light, dark] {
      let accent = GalaxySSIHealthTheme.accentUIColor.resolvedColor(with: traits)
      let ink = GalaxySSIHealthTheme.actionInkUIColor.resolvedColor(with: traits)
      XCTAssertGreaterThanOrEqual(contrast(accent, ink), 4.5)
      XCTAssertGreaterThanOrEqual(contrast(accent, UIColor.systemBackground.resolvedColor(with: traits)), 4.5)
    }
  }

  private func components(_ color: UIColor) -> [Double] {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    XCTAssertTrue(color.getRed(&r, green: &g, blue: &b, alpha: &a))
    return [Double(r), Double(g), Double(b)]
  }
  private func luminance(_ color: UIColor) -> Double {
    let values = components(color).map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
    return values[0] * 0.2126 + values[1] * 0.7152 + values[2] * 0.0722
  }
  private func contrast(_ a: UIColor, _ b: UIColor) -> Double {
    let x = luminance(a), y = luminance(b)
    return (max(x, y) + 0.05) / (min(x, y) + 0.05)
  }
}
