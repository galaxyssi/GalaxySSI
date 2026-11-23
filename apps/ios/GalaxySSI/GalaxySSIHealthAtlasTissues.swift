import Foundation
import UIKit

extension GalaxySSIHealthAtlas {
  struct TissuePack: Decodable {
    let schema: Int
    let entries: [Entry]
    let mechanisms: [Mechanism]
    let plates: [Plate]
    static let bundled: Result<Self?, Error> = Result { try read(bundle: .main) }
    static func read(bundle: Bundle) throws -> Self? {
      guard let data = NSDataAsset(name: "HealthAtlasTissues", bundle: bundle)?.data else { return nil }
      guard data.count <= 256_000 else { throw Invalid.catalogue }
      return try JSONDecoder().decode(Self.self, from: data)
    }
    func applying(to base: GalaxySSIHealthAtlas, bundle: Bundle) throws -> GalaxySSIHealthAtlas {
      let ids = Set(entries.map(\.id)), modelIDs = Set(mechanisms.map(\.id))
      guard schema == 1, entries.count == 14, ids.count == entries.count, modelIDs == ids,
        mechanisms.count == entries.count, plates.count == entries.count,
        ids.isDisjoint(with: Set(base.entries.map(\.id))),
        modelIDs.isDisjoint(with: Set(base.mechanisms.map(\.id))),
        entries.allSatisfy({ $0.kind == .tissue }), mechanisms.allSatisfy({ $0.kind == "tissue" }),
        Set(plates.compactMap(\.owner)) == ids, Set(plates.map(\.id)) == ids,
        plates.allSatisfy({ plate in
          guard let owner = entries.first(where: { $0.id == plate.owner }) else { return false }
          return plate.entryIDs == [owner.id] && plate.viewLabel == "health_atlas_view_tissue" &&
            plate.asset.hasPrefix("HealthAtlasTissue") && plate.source == nil &&
            plate.aspectRatio.isFinite && (0.1...3).contains(plate.aspectRatio) &&
            UIImage(named: plate.asset, in: bundle, compatibleWith: nil) != nil &&
            Set(plate.markers.map(\.id)).count == plate.markers.count &&
            plate.markers.allSatisfy({ owner.related.contains($0.id) && $0.x.isFinite && $0.y.isFinite &&
              (0...1).contains($0.x) && (0...1).contains($0.y) })
        }) else { throw Invalid.catalogue }
      return try GalaxySSIHealthAtlas.validated(.init(schema: base.schema, entries: entries + base.entries,
        mechanisms: mechanisms + base.mechanisms))
    }
  }
  func tissueContext(_ entry: Entry, language: String) -> [String] {
    guard entry.kind == .tissue else { return [] }
    let name = { (item: Entry) in GalaxySSIHealthAtlasText.get(item.name, language) }
    return [GalaxySSIHealthAtlasText.get("health_atlas_tissue_locations", language) + ": " +
      entry.locations.compactMap(self.entry).map(name).joined(separator: ", "),
      GalaxySSIHealthAtlasText.get("health_atlas_tissue_cell_examples", language) + ": " +
      cells(entry).map(name).joined(separator: ", ")]
  }
}
