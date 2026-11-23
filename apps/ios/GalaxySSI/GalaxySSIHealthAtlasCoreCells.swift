import Foundation
import UIKit

extension GalaxySSIHealthAtlas {
  struct CoreCellPack: Decodable {
    let schema: Int
    let plates: [Plate]
    static let bundled: Result<Self?, Error> = Result { try read(bundle: .main) }
    static let owners = ["cell-astrocyte", "cell-schwann-cell", "cell-skeletal-myocyte", "cell-cardiomyocyte", "cell-smooth-muscle-cell", "cell-keratinocyte", "cell-melanocyte", "cell-fibroblast", "cell-adipocyte", "cell-osteoblast", "cell-osteocyte", "cell-osteoclast", "cell-chondrocyte", "cell-vascular-endothelial-cell", "cell-hepatocyte", "cell-enterocyte", "cell-spermatozoon", "cell-oocyte-or-ovum"]
    static func read(bundle: Bundle) throws -> Self? {
      guard let data = NSDataAsset(name: "HealthAtlasCoreCells", bundle: bundle)?.data else { return nil }
      guard data.count <= 128_000 else { throw Invalid.catalogue }
      return try JSONDecoder().decode(Self.self, from: data)
    }
    func validating(in atlas: GalaxySSIHealthAtlas, bundle: Bundle) throws {
      guard schema == 1, plates.count == Self.owners.count, plates.compactMap(\.owner) == Self.owners,
        Set(plates.map(\.id)).count == 18, plates.flatMap(\.annotations).count == 39,
        plates.allSatisfy({ plate in
          guard let owner = plate.owner, atlas.entry(owner)?.kind == .cell,
            plate.id == owner, plate.entryIDs == [owner], plate.markers.isEmpty,
            plate.viewLabel == "health_atlas_cell_morphology", plate.aspectRatio == 360.0 / 280,
            plate.asset.hasPrefix("HealthAtlasCore"), UIImage(named: plate.asset, in: bundle, compatibleWith: nil) != nil,
            let source = plate.source, Self.trusted(source), (2...3).contains(plate.annotations.count),
            Set(plate.annotations.map(\.id)).count == plate.annotations.count else { return false }
          return plate.annotations.allSatisfy { feature in
            atlas.entry(feature.id) == nil && !feature.id.isEmpty && feature.title.hasPrefix("health_atlas_feature_") &&
              feature.explanation == feature.title + "_detail" && feature.marker.x.isFinite && feature.marker.y.isFinite &&
              (0...1).contains(feature.marker.x) && (0...1).contains(feature.marker.y) &&
              ["en", "zh-Hans"].allSatisfy { language in
                GalaxySSIHealthAtlasText.get(feature.title, language) != feature.title &&
                  GalaxySSIHealthAtlasText.get(feature.explanation, language) != feature.explanation
              }
          }
        }) else { throw Invalid.catalogue }
    }
    private static func trusted(_ source: URL) -> Bool {
      source.scheme == "https" && source.host == "openstax.org" && source.query == nil && source.fragment == nil &&
        source.path.hasPrefix("/books/anatomy-and-physiology-2e/pages/")
    }
  }
}
