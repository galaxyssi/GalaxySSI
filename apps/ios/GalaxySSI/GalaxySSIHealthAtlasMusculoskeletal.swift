import Foundation
import UIKit

extension GalaxySSIHealthAtlas {
  struct MusculoskeletalPack: Decodable {
    let schema: Int
    let plates: [Plate]
    static let keys = ["skeletal-anterior", "skeletal-posterior", "muscle-anterior", "muscle-posterior"]
    static let bundled: Result<Self?, Error> = Result { try read(bundle: .main) }
    static func read(bundle: Bundle) throws -> Self? {
      guard let data = NSDataAsset(name: "HealthAtlasMusculoskeletal", bundle: bundle)?.data else { return nil }
      guard data.count <= 128_000 else { throw Invalid.catalogue }
      return try JSONDecoder().decode(Self.self, from: data)
    }
    func validating(in atlas: GalaxySSIHealthAtlas, bundle: Bundle) throws {
      guard schema == 1, plates.map(\.id) == Self.keys, plates.map(\.viewKey) == Self.keys.map(Optional.some),
        plates.allSatisfy({ plate in
          guard let owner = plate.owner, ["skeletal", "muscle"].contains(owner), atlas.entry(owner)?.kind == .system,
            plate.entryIDs == [owner] + plate.markers.map(\.id),
            Set(plate.markers.map(\.id)).count == plate.markers.count,
            plate.markers.allSatisfy({ atlas.entry($0.id)?.kind == .organ &&
              $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }),
            plate.asset.hasPrefix("HealthAtlas"), UIImage(named: plate.asset, in: bundle, compatibleWith: nil) != nil,
            plate.aspectRatio.isFinite, (0.1...3).contains(plate.aspectRatio) else { return false }
          let chapter = owner == "skeletal" ? "7-1-divisions-of-the-skeletal-system" : "11-2-naming-skeletal-muscles"
          return plate.source?.absoluteString == "https://openstax.org/books/anatomy-and-physiology-2e/pages/" + chapter
        }) else { throw Invalid.catalogue }
    }
  }
}
