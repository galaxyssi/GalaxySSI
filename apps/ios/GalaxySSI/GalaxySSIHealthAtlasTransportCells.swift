import Foundation
import UIKit

extension GalaxySSIHealthAtlas {
  struct TransportCellPack: Decodable {
    let schema: Int
    let plates: [Plate]
    static let bundled: Result<Self?, Error> = Result { try read(bundle: .main) }
    static let owners = ["cell-type-i-pneumocyte", "cell-type-ii-pneumocyte", "cell-ciliated-airway-cell", "cell-goblet-cell", "cell-club-cell", "cell-podocyte", "cell-mesangial-cell", "cell-proximal-tubular-cell", "cell-distal-tubular-cell", "cell-collecting-duct-principal-cell", "cell-collecting-duct-intercalated-cell", "cell-urothelial-cell"]
    static func read(bundle: Bundle) throws -> Self? {
      guard let data = NSDataAsset(name: "HealthAtlasTransportCells", bundle: bundle)?.data else { return nil }
      guard data.count <= 128_000 else { throw Invalid.catalogue }
      return try JSONDecoder().decode(Self.self, from: data)
    }
    func validating(in atlas: GalaxySSIHealthAtlas, bundle: Bundle) throws {
      guard schema == 1, plates.count == 12, plates.compactMap(\.owner) == Self.owners,
        Set(plates.map(\.id)).count == 12, plates.flatMap(\.annotations).count == 25,
        plates.allSatisfy({ plate in
          guard let owner = plate.owner, atlas.entry(owner)?.kind == .cell,
            plate.id == owner, plate.entryIDs == [owner], plate.markers.isEmpty,
            plate.asset.hasPrefix("HealthAtlasTransport"), plate.aspectRatio == 360.0 / 280,
            UIImage(named: plate.asset, in: bundle, compatibleWith: nil) != nil,
            plate.source?.absoluteString == Self.source(owner), (2...3).contains(plate.annotations.count),
            Set(plate.annotations.map(\.id)).count == plate.annotations.count else { return false }
          let caption = owner == "cell-collecting-duct-intercalated-cell" ? "type_a_intercalated_view" :
            owner == "cell-urothelial-cell" ? "umbrella_view" : "cell_morphology"
          return plate.viewLabel == "health_atlas_" + caption && plate.annotations.allSatisfy { feature in
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
    private static func source(_ owner: String) -> String {
      let chapter: String
      if owners.prefix(5).contains(owner) { chapter = "22-1-organs-and-structures-of-the-respiratory-system" }
      else if ["cell-podocyte", "cell-mesangial-cell"].contains(owner) { chapter = "25-4-microscopic-anatomy-of-the-kidney" }
      else if owner == "cell-urothelial-cell" { chapter = "25-2-gross-anatomy-of-urine-transport" }
      else { chapter = "25-6-tubular-reabsorption" }
      return "https://openstax.org/books/anatomy-and-physiology-2e/pages/" + chapter
    }
  }
}

/// Qualitative drawing state; the three barrier layers remain visible in every stage.
struct GalaxySSIHealthAtlasFiltrationStage: Equatable {
  static let owner = "cell-podocyte"
  let stage: Int
  init?(stage: Int) {
    guard (0..<4).contains(stage) else { return nil }
    self.stage = stage
  }
  var arrowEnd: Int { [57, 116, 135, 181][stage] }
  var showsSlitDiaphragms: Bool { stage >= 2 }
}
