import Foundation
import UIKit

/// Lossless, frequency-independent teaching transformer, not measured hearing.
struct GalaxySSIHealthAtlasMiddleEar: Equatable, Sendable {
  let membraneAreaMm2: Double
  let footplateAreaMm2: Double
  let leverRatio: Double
  static let source = URL(string: "https://pmc.ncbi.nlm.nih.gov/articles/PMC4570511/")!
  static let measurementSource = URL(string: "https://pubmed.ncbi.nlm.nih.gov/28079680/")!
  static let anatomySource = URL(string: "https://www.nidcd.nih.gov/health/how-do-we-hear")!
  init?(membraneAreaMm2: Double = 55, footplateAreaMm2: Double = 3.2, leverRatio: Double = 1.3) {
    guard membraneAreaMm2.isFinite, (35...75).contains(membraneAreaMm2),
      footplateAreaMm2.isFinite, (2...5).contains(footplateAreaMm2),
      leverRatio.isFinite, (1...1.6).contains(leverRatio) else { return nil }
    self.membraneAreaMm2 = membraneAreaMm2; self.footplateAreaMm2 = footplateAreaMm2; self.leverRatio = leverRatio
  }
  var areaRatio: Double { membraneAreaMm2 / footplateAreaMm2 }
  var pressureRatio: Double { areaRatio * leverRatio }
  var pressureGainDb: Double { 20 * log10(pressureRatio) }
  var volumeVelocityRatio: Double { 1 / pressureRatio }
  static let ids = ["ear", "external-ear", "middle-ear", "inner-ear", "cochlea", "vestibular-apparatus"]
  static let plate = GalaxySSIHealthAtlas.Plate(id: "ear", asset: "HealthAtlasEarSection", owner: "ear",
    viewLabel: "health_atlas_view_ear_section", entryIDs: ids, aspectRatio: 3.0 / 2,
    markers: [.init(id: "external-ear", x: 0.105, y: 0.251), .init(id: "middle-ear", x: 0.531, y: 0.420),
      .init(id: "inner-ear", x: 0.656, y: 0.426), .init(id: "cochlea", x: 0.759, y: 0.556),
      .init(id: "vestibular-apparatus", x: 0.742, y: 0.111)], source: anatomySource)
}

extension GalaxySSIHealthAtlas {
  struct EarPack: Decodable {
    let schema: Int
    let entries: [Entry]
    let mechanisms: [Mechanism]
    static func read(bundle: Bundle) throws -> Self? {
      guard let data = NSDataAsset(name: "HealthAtlasEar", bundle: bundle)?.data else { return nil }
      guard data.count <= 64_000 else { throw Invalid.catalogue }
      return try JSONDecoder().decode(Self.self, from: data)
    }
    func applying(to base: GalaxySSIHealthAtlas, bundle: Bundle) throws -> GalaxySSIHealthAtlas {
      let ids = Set(GalaxySSIHealthAtlasMiddleEar.ids)
      guard schema == 1, entries.count == 6, mechanisms.count == 6,
        Set(entries.map(\.id)) == ids, Set(mechanisms.map(\.id)) == ids,
        ids.isDisjoint(with: Set(base.mechanisms.map(\.id))),
        entries.allSatisfy({ entry in
          guard let old = base.entry(entry.id) else { return false }
          return entry.kind == .organ && old.kind == entry.kind && entry.systems == old.systems && entry.mechanism == entry.id
        }), mechanisms.allSatisfy({ $0.kind == "organ" && $0.chapter == "14-1-sensory-perception" && $0.reference == nil }),
        UIImage(named: GalaxySSIHealthAtlasMiddleEar.plate.asset, in: bundle, compatibleWith: nil) != nil
      else { throw Invalid.catalogue }
      let revised = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
      return try GalaxySSIHealthAtlas.validated(.init(schema: base.schema,
        entries: base.entries.map { revised[$0.id] ?? $0 }, mechanisms: base.mechanisms + mechanisms))
    }
  }
}
