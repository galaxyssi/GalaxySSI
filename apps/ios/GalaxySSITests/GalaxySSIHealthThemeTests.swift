import UIKit
import XCTest
@testable import GalaxySSI

@MainActor
final class GalaxySSIHealthThemeTests: XCTestCase {
  func testOrganPlateResourcePackCanShipWithoutTheUnmergedAtlasTypes() throws {
    let bundle = Bundle(for: GalaxySSIStore.self)
    let data = try XCTUnwrap(NSDataAsset(name: "HealthAtlasOrganPlates", bundle: bundle)?.data)
    let pack = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(pack["schema"] as? Int, 1)
    let entries = try XCTUnwrap(pack["entries"] as? [[String: Any]])
    XCTAssertEqual(entries.compactMap { $0["id"] as? String }, ["renal-cortex", "renal-medulla", "renal-pelvis"])
    let plates = try XCTUnwrap(pack["plates"] as? [[String: Any]])
    XCTAssertEqual(plates.count, 7)
    for plate in plates {
      for marker in try XCTUnwrap(plate["markers"] as? [[String: Any]]) {
        XCTAssertTrue((0.0...1.0).contains(try XCTUnwrap(marker["x"] as? Double)))
        XCTAssertTrue((0.0...1.0).contains(try XCTUnwrap(marker["y"] as? Double)))
      }
    }
    let english = try XCTUnwrap(pack["english"] as? [String: String])
    XCTAssertEqual(english.count, 17)
    let chinesePath = try XCTUnwrap(bundle.path(forResource: "zh-Hans", ofType: "lproj"))
    let chinese = try XCTUnwrap(Bundle(path: chinesePath))
    for key in english.keys {
      XCTAssertNotEqual(chinese.localizedString(forKey: key, value: key, table: nil), key)
    }
    for name in ["Brain", "Lungs", "Liver", "Kidney"] {
      let image = try XCTUnwrap(UIImage(named: "HealthAtlas" + name, in: bundle, compatibleWith: nil)?.cgImage)
      XCTAssertEqual(image.width, 1254); XCTAssertEqual(image.height, 1254)
    }
  }

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

  func testOwnedCellResourcePackResolvesStagesCaptionsAndImageRatios() throws {
    let bundle = Bundle(for: GalaxySSIStore.self)
    let data = try XCTUnwrap(NSDataAsset(name: "HealthAtlasCellProcesses", bundle: bundle)?.data)
    let pack = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(pack["schema"] as? Int, 1)
    let mechanisms = try XCTUnwrap(pack["mechanisms"] as? [[String: Any]])
    let assignments = try XCTUnwrap(pack["entryMechanisms"] as? [String: String])
    let english = try XCTUnwrap(pack["english"] as? [String: String])
    XCTAssertEqual(mechanisms.count, 30); XCTAssertEqual(assignments.count, 30); XCTAssertEqual(english.count, 152)
    let chinese = try XCTUnwrap(Bundle(path: XCTUnwrap(bundle.path(forResource: "zh-Hans", ofType: "lproj"))))
    for mechanism in mechanisms {
      let id = try XCTUnwrap(mechanism["id"] as? String)
      XCTAssertEqual(mechanism["kind"] as? String, "cell"); XCTAssertEqual(assignments[id], id)
      let title = try XCTUnwrap(mechanism["title"] as? String)
      let stages = try XCTUnwrap(mechanism["stages"] as? [String]); XCTAssertEqual(stages.count, 4)
      for key in [title] + stages {
        XCTAssertFalse(try XCTUnwrap(english[key]).isEmpty)
        XCTAssertNotEqual(chinese.localizedString(forKey: key, value: key, table: nil), key)
      }
    }
    let plates = try XCTUnwrap(pack["plates"] as? [[String: Any]])
    XCTAssertEqual(plates.compactMap { $0["owner"] as? String }, ["cell-erythrocyte", "cell-neuron"])
    for plate in plates {
      let owner = try XCTUnwrap(plate["owner"] as? String), name = try XCTUnwrap(plate["asset"] as? String)
      XCTAssertEqual(plate["entryIDs"] as? [String], [owner])
      let image = try XCTUnwrap(UIImage(named: name, in: bundle, compatibleWith: nil)?.cgImage)
      XCTAssertEqual(try XCTUnwrap(plate["aspectRatio"] as? Double), Double(image.width) / Double(image.height), accuracy: 1e-9)
      let caption = try XCTUnwrap(plate["viewLabel"] as? String)
      XCTAssertNotNil(english[caption]); XCTAssertNotEqual(chinese.localizedString(forKey: caption, value: caption, table: nil), caption)
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

  func testSexEditorHasOnlyTwoChoicesWithoutConvertingLegacyValues() throws {
    typealias Sex = GalaxySSIHealthProfile.ReferenceSex
    XCTAssertEqual(Sex.editorChoices, [.male, .female])
    XCTAssertEqual(Sex.male.editorSelection, .male)
    XCTAssertEqual(Sex.female.editorSelection, .female)
    XCTAssertNil(Sex.other.editorSelection)
    XCTAssertNil(Sex.unspecified.editorSelection)
    for legacy in [Sex.other, .unspecified] {
      var profile = GalaxySSIHealthProfile()
      profile.referenceSex = legacy; profile.context = "Retained legacy context"
      profile.selectEditorSex(nil)
      XCTAssertEqual(profile.referenceSex, legacy)
      profile.selectEditorSex(.other)
      XCTAssertEqual(profile.referenceSex, legacy)
      let decoded = try JSONDecoder().decode(GalaxySSIHealthProfile.self, from: JSONEncoder().encode(profile))
      XCTAssertEqual(decoded.referenceSex, legacy)
      XCTAssertEqual(decoded.context, profile.context)
    }
  }

  func testBothChoicesAndUnrelatedEditsPreserveEncryptedLegacyContext() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let records = GalaxySSIHealthRecords(owner: "profile-fixture", secrets: HealthThemeProfileSecrets(),
      isolatedFile: root.appendingPathComponent("records"))
    var profile = GalaxySSIHealthProfile()
    profile.name = "Fixture"; profile.context = "Previously recorded context"; profile.referenceSex = .other
    try records.writeProfile(profile)
    profile = try records.loadProfile()
    profile.name = "Updated fixture"; profile.selectEditorSex(nil)
    try records.writeProfile(profile)
    XCTAssertEqual(try records.loadProfile().referenceSex, .other)
    for choice in GalaxySSIHealthProfile.ReferenceSex.editorChoices {
      profile = try records.loadProfile()
      profile.selectEditorSex(choice)
      try records.writeProfile(profile)
      let saved = try records.loadProfile()
      XCTAssertEqual(saved.referenceSex.editorSelection, choice)
      XCTAssertEqual(saved.context, "Previously recorded context")
      XCTAssertEqual(saved.name, "Updated fixture")
    }
  }

  func testSystemPlatePackHasMacroscopicRoutesAndReferenceSources() throws {
    let bundle = Bundle(for: GalaxySSIStore.self)
    let data = try XCTUnwrap(NSDataAsset(name: "HealthAtlasSystemPlates", bundle: bundle)?.data)
    let pack = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(pack["schema"] as? Int, 1)
    let plates = try XCTUnwrap(pack["plates"] as? [[String: Any]])
    XCTAssertEqual(plates.count, 3)
    var routes = [String: String]()
    for plate in plates {
      let id = try XCTUnwrap(plate["id"] as? String)
      let asset = try XCTUnwrap(plate["asset"] as? String)
      let image = try XCTUnwrap(UIImage(named: asset, in: bundle, compatibleWith: nil))
      XCTAssertEqual(Double(image.size.width / image.size.height), try XCTUnwrap(plate["aspectRatio"] as? Double), accuracy: 0.001)
      let source = try XCTUnwrap(URL(string: try XCTUnwrap(plate["source"] as? String)))
      XCTAssertEqual(source.scheme, "https"); XCTAssertEqual(source.host, "openstax.org")
      for target in try XCTUnwrap(plate["entryIDs"] as? [String]) {
        XCTAssertNil(routes.updateValue(id, forKey: target))
        XCTAssertFalse(target.hasPrefix("cell-"))
      }
      for marker in try XCTUnwrap(plate["markers"] as? [[String: Any]]) {
        XCTAssertTrue((0.0...1.0).contains(try XCTUnwrap(marker["x"] as? Double)))
        XCTAssertTrue((0.0...1.0).contains(try XCTUnwrap(marker["y"] as? Double)))
      }
    }
    XCTAssertEqual(routes["ureters"], "urinary")
    XCTAssertNil(routes["kidneys"])
    XCTAssertEqual(routes["pancreatic-duct"], "pancreas")
    XCTAssertNil(routes["pancreatic-islets"])
    XCTAssertNil(routes["pancreatic-acini"])
  }

  func testHealthFeatureSymbolsAreDistinctAndAvailable() {
    let icons = [GalaxySSIHealthFeature.care, .profile, .body].map { $0.label.icon }
    XCTAssertEqual(icons, ["waveform.path.ecg", "person.text.rectangle", "figure.stand"])
    XCTAssertEqual(Set(icons).count, 3)
    for icon in icons { XCTAssertNotNil(UIImage(systemName: icon)) }
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

private final class HealthThemeProfileSecrets: GalaxySSISecretStore {
  private var values: [String: String] = [:]
  func string(account: String) -> String? { values[account] }
  func setString(_ value: String, account: String) throws { values[account] = value }
  func delete(account: String) { values.removeValue(forKey: account) }
}
