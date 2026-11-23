import Foundation
import UIKit

enum GalaxySSIHealthAtlasHeartSection {
  static let anatomySource = URL(string: "https://openstax.org/books/anatomy-and-physiology-2e/pages/19-1-heart-anatomy")!
  static let cycleSource = URL(string: "https://openstax.org/books/anatomy-and-physiology-2e/pages/19-3-cardiac-cycle")!
  static let ejectionSource = URL(string: "https://openstax.org/books/anatomy-and-physiology-2e/pages/19-4-cardiac-physiology")!
  enum Valve: String, CaseIterable {
    case tricuspid, mitral, pulmonary, aortic
    var id: String { rawValue + "-valve" }
    var point: (x: Double, y: Double) {
      switch self {
      case .tricuspid: return (451, 707)
      case .mitral: return (859, 659)
      case .pulmonary: return (599, 603)
      case .aortic: return (708, 589)
      }
    }
    var marker: GalaxySSIHealthAtlas.Marker {
      GalaxySSIHealthAtlasHeartSection.marker(id, point.x, point.y)
    }
    func openAt(_ stage: Int) -> Bool? {
      guard (0..<4).contains(stage) else { return nil }
      return stage == (self == .tricuspid || self == .mitral ? 0 : 2)
    }
    static func supports(_ id: String) -> Bool { id == "heart-valves" || allCases.contains { $0.id == id } }
  }
  private static func marker(_ id: String, _ x: Double, _ y: Double) -> GalaxySSIHealthAtlas.Marker {
    .init(id: id, x: x / 1254, y: y / 1254)
  }
  static let exterior = GalaxySSIHealthAtlas.Plate(id: "heart-exterior", asset: "HealthAtlasHeart", owner: "heart",
    viewLabel: "health_atlas_view_external", entryIDs: ["heart", "atria", "ventricles", "coronary-vessels"],
    aspectRatio: 3.0 / 4, markers: [.init(id: "atria", x: 0.28, y: 0.46),
      .init(id: "coronary-vessels", x: 0.57, y: 0.68), .init(id: "ventricles", x: 0.61, y: 0.84)],
    source: anatomySource, viewKey: "heart-exterior", selectorLabel: "health_atlas_cardiac_exterior")
  static let section = GalaxySSIHealthAtlas.Plate(id: "heart-section", asset: "HealthAtlasHeartSection", owner: "heart",
    viewLabel: "health_atlas_view_cardiac_section", entryIDs: ["heart", "aorta", "pulmonary-trunk", "left-atrium", "right-atrium",
      "right-ventricle", "left-ventricle"], aspectRatio: 1,
    markers: [marker("aorta", 885, 177), marker("pulmonary-trunk", 613, 459), marker("left-atrium", 860, 531),
      marker("right-atrium", 423, 563), marker("right-ventricle", 443, 838), marker("left-ventricle", 788, 885)],
    source: anatomySource, viewKey: "heart-section", selectorLabel: "health_atlas_cardiac_section")
  static let valves = GalaxySSIHealthAtlas.Plate(id: "heart-valves", asset: "HealthAtlasHeartSection", owner: "heart",
    viewLabel: "health_atlas_view_cardiac_valves", entryIDs: ["heart-valves"] + Valve.allCases.map(\.id),
    aspectRatio: 1, markers: Valve.allCases.map(\.marker), source: anatomySource)
  static func plate(for id: String) -> GalaxySSIHealthAtlas.Plate? {
    if Valve.supports(id) { return valves }
    return section.markers.contains { $0.id == id } ? section : nil
  }
  static func phase(_ stage: Int, language: String) -> String? {
    guard (0..<4).contains(stage) else { return nil }
    return GalaxySSIHealthAtlasText.get("health_atlas_valves_" + ["filling", "contraction", "ejection", "relaxation"][stage], language)
  }
  static func label(_ valve: Valve, stage: Int, atlas: GalaxySSIHealthAtlas, language: String) -> String? {
    guard let open = valve.openAt(stage), let entry = atlas.entry(valve.id) else { return nil }
    return String(format: GalaxySSIHealthAtlasText.get("health_atlas_valve_state", language),
      GalaxySSIHealthAtlasText.get(entry.name, language),
      GalaxySSIHealthAtlasText.get(open ? "health_atlas_valve_open" : "health_atlas_valve_closed", language))
  }
  static func context(_ id: String, stage: Int, atlas: GalaxySSIHealthAtlas, language: String) -> String? {
    guard Valve.supports(id), let phase = phase(stage, language: language) else { return nil }
    let labels = Valve.allCases.filter { id == "heart-valves" || $0.id == id }
      .compactMap { label($0, stage: stage, atlas: atlas, language: language) }
    return ([GalaxySSIHealthAtlasText.get("health_atlas_valves_scope", language), phase] + labels +
      [cycleSource.absoluteString]).joined(separator: "\n")
  }
}

extension GalaxySSIHealthAtlas {
  struct HeartSectionPack: Decodable {
    let schema: Int
    let entries: [Entry]
    let mechanisms: [Mechanism]
    static func read(bundle: Bundle) throws -> Self? {
      guard let data = NSDataAsset(name: "HealthAtlasHeartSectionPack", bundle: bundle)?.data else { return nil }
      guard data.count <= 128_000 else { throw Invalid.catalogue }
      return try JSONDecoder().decode(Self.self, from: data)
    }
    func applying(to base: GalaxySSIHealthAtlas, bundle: Bundle) throws -> GalaxySSIHealthAtlas {
      let revised = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
      let additions = entries.filter { base.entry($0.id) == nil }
      guard schema == 1, entries.count == 17, revised.count == entries.count, additions.count == 10,
        additions.allSatisfy({ $0.kind == .organ && $0.systems == ["cardio"] && $0.mechanism == $0.id }),
        entries.allSatisfy({ entry in base.entry(entry.id).map { $0.kind == entry.kind && $0.systems == entry.systems } ?? true }),
        mechanisms.count == 11, Set(mechanisms.map(\.id)) == Set(additions.map(\.id) + ["heart-valves"]),
        mechanisms.allSatisfy({ $0.kind == "organ" && $0.chapter == "19-3-cardiac-cycle" && $0.reference == nil }),
        Set(mechanisms.map(\.id)).isDisjoint(with: Set(base.mechanisms.map(\.id))),
        UIImage(named: GalaxySSIHealthAtlasHeartSection.section.asset, in: bundle, compatibleWith: nil) != nil
      else { throw Invalid.catalogue }
      return try GalaxySSIHealthAtlas.validated(.init(schema: base.schema,
        entries: additions + base.entries.map { revised[$0.id] ?? $0 }, mechanisms: mechanisms + base.mechanisms))
    }
  }
}
