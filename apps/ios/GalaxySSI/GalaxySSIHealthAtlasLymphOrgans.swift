import Foundation
import UIKit

extension GalaxySSIHealthAtlas {
  struct LymphPack: Decodable {
    let schema: Int
    let entries: [Entry]
    let mechanisms: [Mechanism]
    let plates: [Plate]
    let stageFeatures: [String: [Int]]
    let routes: [String: [GalaxySSIHealthAtlasLymphLesson.Route]]
    static let bundled: Result<Self?, Error> = Result { try read(bundle: .main) }
    static let owners = ["bone-marrow", "thymus", "spleen", "lymph-nodes", "lymphatic-vessels", "thoracic-duct", "tonsils", "adenoids", "gut-associated-lymphoid-tissue"]
    static let stems = ["bone-marrow": "marrow", "thymus": "thymus", "spleen": "spleen", "lymph-nodes": "node",
      "lymphatic-vessels": "vessel", "thoracic-duct": "duct", "tonsils": "tonsil", "adenoids": "adenoid", "gut-associated-lymphoid-tissue": "galt"]
    static func read(bundle: Bundle) throws -> Self? {
      guard let data = NSDataAsset(name: "HealthAtlasLymphOrgans", bundle: bundle)?.data else { return nil }
      guard data.count <= 128_000 else { throw Invalid.catalogue }
      return try JSONDecoder().decode(Self.self, from: data)
    }
    func applying(to base: GalaxySSIHealthAtlas, bundle: Bundle) throws -> GalaxySSIHealthAtlas {
      let ids = Set(Self.owners)
      guard schema == 1, entries.count == 9, Set(entries.map(\.id)) == ids,
        entries.allSatisfy({ entry in
          guard let original = base.entry(entry.id), let plate = plates.first(where: { $0.owner == entry.id }) else { return false }
          return original.kind == .organ && entry.kind == original.kind && entry.systems == original.systems &&
            entry.mechanism == entry.id && entry.related == plate.markers.map(\.id)
        }), mechanisms.count == 9, Set(mechanisms.map(\.id)) == ids, ids.isDisjoint(with: Set(base.mechanisms.map(\.id))),
        mechanisms.allSatisfy({ model in
          guard let stem = Self.stems[model.id] else { return false }
          let prefix = "health_atlas_lymph_" + stem
          return model.kind == "lymphoid-organ" && model.title == prefix + "_title" &&
            model.stages == (0..<4).map { prefix + "_stage_" + String($0) } && model.reference == nil &&
            model.chapter == (model.id == "thymus" ? "21-3-the-adaptive-immune-response-t-lymphocytes-and-their-functional-types" :
              "21-1-anatomy-of-the-lymphatic-and-immune-systems")
        }), Set(stageFeatures.keys) == ids, Set(routes.keys) == ["lymph-nodes", "thoracic-duct"],
        routes.values.allSatisfy({ $0.count == 4 && $0.allSatisfy(\.valid) }) else { throw Invalid.catalogue }
      let related = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.related) })
      let atlas = try GalaxySSIHealthAtlas.validated(.init(schema: base.schema,
        entries: base.entries.map { ids.contains($0.id) ? $0.replacing(mechanism: $0.id, related: related[$0.id]) : $0 },
        mechanisms: mechanisms + base.mechanisms), requireCompleteMicroscopic: true)
      guard plates.count == 9, plates.compactMap(\.owner) == Self.owners, Set(plates.map(\.id)).count == 9,
        plates.flatMap(\.annotations).count == 30, plates.flatMap(\.markers).count == 12,
        plates.allSatisfy({ plate in
          guard let owner = plate.owner, let stem = Self.stems[owner], let stages = stageFeatures[owner],
            plate.id == owner, plate.entryIDs == [owner] + plate.markers.map(\.id),
            plate.source == GalaxySSIHealthAtlasLymphLesson.source, plate.viewLabel == "health_atlas_lymph_" + stem + "_view",
            plate.asset.hasPrefix("HealthAtlasLymph"), UIImage(named: plate.asset, in: bundle, compatibleWith: nil) != nil,
            plate.aspectRatio == 360.0 / 280, (3...5).contains(plate.annotations.count),
            stages.count == 4, stages.allSatisfy(plate.annotations.indices.contains),
            Set(plate.markers.map(\.id) + plate.annotations.map(\.id)).count == plate.markers.count + plate.annotations.count
          else { return false }
          return plate.markers.allSatisfy { atlas.entry($0.id) != nil } && plate.annotations.enumerated().allSatisfy { index, feature in
            let prefix = "health_atlas_lymph_" + stem
            return feature.id == stem + "-" + String(index) && atlas.entry(feature.id) == nil &&
              feature.title == prefix + "_feature_" + String(index) && feature.explanation == prefix + "_detail_" + String(index) &&
              ["en", "zh-Hans"].allSatisfy { language in
                GalaxySSIHealthAtlasText.get(feature.title, language) != feature.title &&
                  GalaxySSIHealthAtlasText.get(feature.explanation, language) != feature.explanation
              }
          }
        }) else { throw Invalid.catalogue }
      return atlas
    }
  }
}
