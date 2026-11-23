import Foundation
import UIKit

extension GalaxySSIHealthAtlas {
  struct EndocrinePack: Decodable {
    let schema: Int
    let plates: [Plate]
    let mechanisms: [Mechanism]
    let paths: [String: GalaxySSIHealthAtlasEndocrinePath]
    static let bundled: Result<Self?, Error> = Result { try read(bundle: .main) }
    static let owners = ["cell-thyroid-follicular-cell", "cell-thyroid-parafollicular-cell", "cell-parathyroid-chief-cell", "cell-adrenocortical-cell", "cell-chromaffin-cell", "cell-somatotroph", "cell-lactotroph", "cell-corticotroph", "cell-thyrotroph", "cell-gonadotroph", "cell-pinealocyte", "cell-leydig-cell", "cell-granulosa-cell", "cell-theca-cell", "thyroid-gland", "parathyroid-glands", "adrenal-glands", "pituitary-gland"]
    static let sources = [
      "cell-thyroid-follicular-cell": "https://openstax.org/books/anatomy-and-physiology-2e/pages/17-4-the-thyroid-gland",
      "cell-thyroid-parafollicular-cell": "https://openstax.org/books/anatomy-and-physiology-2e/pages/17-4-the-thyroid-gland",
      "cell-parathyroid-chief-cell": "https://openstax.org/books/anatomy-and-physiology-2e/pages/17-5-the-parathyroid-glands",
      "cell-adrenocortical-cell": "https://openstax.org/books/anatomy-and-physiology-2e/pages/17-6-the-adrenal-glands",
      "cell-chromaffin-cell": "https://openstax.org/books/anatomy-and-physiology-2e/pages/17-6-the-adrenal-glands",
      "cell-somatotroph": "https://openstax.org/books/anatomy-and-physiology-2e/pages/17-3-the-pituitary-gland-and-hypothalamus",
      "cell-lactotroph": "https://openstax.org/books/anatomy-and-physiology-2e/pages/17-3-the-pituitary-gland-and-hypothalamus",
      "cell-corticotroph": "https://openstax.org/books/anatomy-and-physiology-2e/pages/17-3-the-pituitary-gland-and-hypothalamus",
      "cell-thyrotroph": "https://openstax.org/books/anatomy-and-physiology-2e/pages/17-3-the-pituitary-gland-and-hypothalamus",
      "cell-gonadotroph": "https://openstax.org/books/anatomy-and-physiology-2e/pages/17-3-the-pituitary-gland-and-hypothalamus",
      "cell-pinealocyte": "https://openstax.org/books/anatomy-and-physiology-2e/pages/17-7-the-pineal-gland",
      "cell-leydig-cell": "https://openstax.org/books/anatomy-and-physiology-2e/pages/27-1-anatomy-and-physiology-of-the-testicular-reproductive-system",
      "cell-granulosa-cell": "https://openstax.org/books/anatomy-and-physiology-2e/pages/27-2-anatomy-and-physiology-of-the-ovarian-reproductive-system",
      "cell-theca-cell": "https://openstax.org/books/anatomy-and-physiology-2e/pages/27-2-anatomy-and-physiology-of-the-ovarian-reproductive-system",
      "thyroid-gland": "https://openstax.org/books/anatomy-and-physiology-2e/pages/17-4-the-thyroid-gland",
      "parathyroid-glands": "https://openstax.org/books/anatomy-and-physiology-2e/pages/17-5-the-parathyroid-glands",
      "adrenal-glands": "https://openstax.org/books/anatomy-and-physiology-2e/pages/17-6-the-adrenal-glands",
      "pituitary-gland": "https://openstax.org/books/anatomy-and-physiology-2e/pages/17-3-the-pituitary-gland-and-hypothalamus"
    ]
    static let stems = ["thyroid-gland": "thyroid", "parathyroid-glands": "parathyroid", "adrenal-glands": "adrenal", "pituitary-gland": "pituitary"]
    static func read(bundle: Bundle) throws -> Self? {
      guard let data = NSDataAsset(name: "HealthAtlasEndocrineCells", bundle: bundle)?.data else { return nil }
      guard data.count <= 128_000 else { throw Invalid.catalogue }
      return try JSONDecoder().decode(Self.self, from: data)
    }
    func applying(to base: GalaxySSIHealthAtlas, bundle: Bundle) throws -> GalaxySSIHealthAtlas {
      let targets = Set(Self.stems.keys)
      guard schema == 1, mechanisms.count == 4, Set(mechanisms.map(\.id)) == targets, Set(paths.keys) == targets,
        targets.allSatisfy({ base.entry($0)?.kind == .organ }), targets.isDisjoint(with: Set(base.mechanisms.map(\.id))),
        mechanisms.allSatisfy({ model in
          guard let stem = Self.stems[model.id] else { return false }
          let prefix = "health_atlas_endocrine_" + stem + "_path"
          return model.kind == "secretion" && model.reference == nil && model.title == prefix + "_title" &&
            model.stages == (0..<4).map { prefix + "_" + String($0) } &&
            model.source.absoluteString == Self.sources[model.id]
        }), paths.allSatisfy({ id, path in
          path.scope == "health_atlas_endocrine_" + Self.stems[id]! + "_scope" && path.steps.count == 4 &&
            path.separateBranches == ["adrenal-glands", "pituitary-gland"].contains(id) &&
            path.steps.allSatisfy { step in
              step.label.hasPrefix("health_atlas_endocrine_stage_") &&
                (step.destination == nil || base.entry(step.destination!) != nil)
            }
        }) else { throw Invalid.catalogue }
      let atlas = try GalaxySSIHealthAtlas.validated(.init(schema: base.schema,
        entries: base.entries.map { targets.contains($0.id) ? $0.replacing(mechanism: $0.id) : $0 },
        mechanisms: mechanisms + base.mechanisms), requireCompleteMicroscopic: true)
      guard plates.count == 18, plates.compactMap(\.owner) == Self.owners, Set(plates.map(\.id)).count == 18,
        plates.flatMap(\.annotations).count == 37, plates.flatMap(\.markers).count == 4,
        plates.allSatisfy({ plate in
          guard let owner = plate.owner, atlas.entry(owner)?.kind == (targets.contains(owner) ? .organ : .cell),
            plate.id == owner, plate.entryIDs == [owner] + plate.markers.map(\.id),
            plate.source?.absoluteString == Self.sources[owner], plate.asset.hasPrefix("HealthAtlasEndocrine"),
            UIImage(named: plate.asset, in: bundle, compatibleWith: nil) != nil, plate.aspectRatio == 360.0 / 280,
            (1...3).contains(plate.annotations.count),
            Set(plate.markers.map(\.id) + plate.annotations.map(\.id)).count == plate.markers.count + plate.annotations.count
          else { return false }
          return plate.markers.allSatisfy { atlas.entry($0.id) != nil } && plate.annotations.allSatisfy { feature in
            atlas.entry(feature.id) == nil && feature.title.hasPrefix("health_atlas_endocrine_") &&
              feature.explanation == feature.title + "_detail" &&
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
