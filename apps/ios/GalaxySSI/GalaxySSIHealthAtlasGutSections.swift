import Foundation
import UIKit

extension GalaxySSIHealthAtlas {
  struct GutPack: Decodable {
    let schema: Int
    let entries: [Entry]
    let mechanisms: [Mechanism]
    let plates: [Plate]
    let stageFeatures: [String: [Int]]
    let routes: [String: [GalaxySSIHealthAtlasSectionLesson.Route]]
    let notes: [String: [String]]
    static let owners = ["oral-cavity","teeth","esophagus","stomach","small-intestine","duodenum","jejunum","ileum","large-intestine","cecum","appendix","colon","rectum","anal-canal"]
    static let paintedAssets = ["teeth": "HealthAtlasFunctionGutTooth", "jejunum": "HealthAtlasFunctionGutJejunum"]
    static let bundled: Result<Self?, Error> = Result { try read(bundle: .main) }
    static func read(bundle: Bundle) throws -> Self? {
      guard let data = NSDataAsset(name: "HealthAtlasGutSections", bundle: bundle)?.data else { return nil }
      guard data.count <= 192_000 else { throw Invalid.catalogue }
      return try JSONDecoder().decode(Self.self, from: data)
    }
    func applying(to base: GalaxySSIHealthAtlas, bundle: Bundle) throws -> GalaxySSIHealthAtlas {
      let ids = Set(Self.owners), moving: Set<String> = ["esophagus", "stomach", "small-intestine", "duodenum", "large-intestine", "cecum"]
      guard schema == 1, entries.count == 14, Set(entries.map(\.id)) == ids,
        mechanisms.count == 14, Set(mechanisms.map(\.id)) == ids,
        ids.isDisjoint(with: Set(base.mechanisms.map(\.id))),
        entries.allSatisfy({ entry in
          guard let original = base.entry(entry.id), let plate = plates.first(where: { $0.owner == entry.id }) else { return false }
          return original.kind == .organ && entry.kind == original.kind && entry.systems == original.systems &&
            entry.mechanism == entry.id && entry.related == plate.markers.map(\.id)
        }), mechanisms.allSatisfy({ model in
          model.kind == "alimentary-organ" && model.title.hasPrefix("health_atlas_gut_section_") &&
            model.stages.count == 4 && model.stages.allSatisfy { $0.hasPrefix("health_atlas_gut_section_") } &&
            model.reference == nil && ["23-3-the-mouth-pharynx-and-esophagus", "23-4-the-stomach", "23-5-the-small-and-large-intestines"].contains(model.chapter)
        }), Set(stageFeatures.keys) == ids, Set(routes.keys) == moving, Set(notes.keys) == ids,
        routes.values.allSatisfy({ $0.count == 4 && $0.allSatisfy(\.valid) }) else { throw Invalid.catalogue }
      let changes = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.related) })
      let atlas = try GalaxySSIHealthAtlas.validated(.init(schema: base.schema,
        entries: base.entries.map { ids.contains($0.id) ? $0.replacing(mechanism: $0.id, related: changes[$0.id]) : $0 },
        mechanisms: mechanisms + base.mechanisms), requireCompleteMicroscopic: true)
      guard plates.count == 14, plates.compactMap(\.owner) == Self.owners, Set(plates.map(\.id)).count == 14,
        plates.flatMap(\.annotations).count == 47, plates.flatMap(\.markers).count == 29,
        plates.allSatisfy({ plate in
          guard let owner = plate.owner, plate.id == owner, let entry = atlas.entry(owner), let steps = stageFeatures[owner], let scope = notes[owner],
            steps.count == 4, steps.allSatisfy(plate.annotations.indices.contains),
            plate.entryIDs == [owner] + plate.markers.map(\.id),
            plate.aspectRatio == (Self.paintedAssets[owner] == nil ? 360.0 / 280 : 1),
            plate.source == atlas.model(entry).source,
            (Self.paintedAssets[owner].map { plate.asset == $0 } ?? plate.asset.hasPrefix("HealthAtlasGut")),
            UIImage(named: plate.asset, in: bundle, compatibleWith: nil) != nil,
            plate.viewLabel.hasPrefix("health_atlas_gut_section_"), (3...4).contains(plate.annotations.count),
            scope.first == "health_atlas_gut_section_" + (moving.contains(owner) ? "motion_scope" : "regional_scope"),
            (1...2).contains(scope.count),
            Set(plate.markers.map(\.id) + plate.annotations.map(\.id)).count == plate.markers.count + plate.annotations.count
          else { return false }
          let keys = scope + [plate.viewLabel] + plate.annotations.flatMap { [$0.title, $0.explanation] }
          return plate.markers.allSatisfy { atlas.entry($0.id) != nil } &&
            plate.annotations.allSatisfy { atlas.entry($0.id) == nil } &&
            keys.allSatisfy { key in
              key.hasPrefix("health_atlas_gut_section_") && ["en", "zh-Hans"].allSatisfy {
                GalaxySSIHealthAtlasText.get(key, $0) != key
              }
            }
        }) else { throw Invalid.catalogue }
      return atlas
    }
  }
}
