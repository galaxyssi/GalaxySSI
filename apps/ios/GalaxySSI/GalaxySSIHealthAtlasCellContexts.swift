import Foundation
import UIKit

extension GalaxySSIHealthAtlas {
  struct TissueContextPack: Decodable {
    let schema: Int
    let plates: [Plate]
    let mechanisms: [Mechanism]
    static let bundled: Result<Self?, Error> = Result { try read(bundle: .main) }
    static let owners = ["cell-mast-cell", "cell-hematopoietic-stem-cell", "cell-helper-t-cell", "cell-cytotoxic-t-cell", "cell-regulatory-t-cell", "cell-pericyte", "cell-lymphatic-endothelial-cell", "cell-sertoli-cell", "cell-spermatogonium", "cell-spermatocyte", "cell-ciliated-oviduct-cell", "cell-endometrial-epithelial-cell", "cell-endometrial-stromal-cell", "cell-mammary-luminal-cell", "cell-trophoblast", "cell-langerhans-cell", "cell-sebocyte", "cell-sweat-gland-secretory-cell", "cell-hair-matrix-cell", "cell-muscle-satellite-cell", "cell-tenocyte", "sweat-glands", "hair-follicles"]
    static let sources = [
      "cell-mast-cell": "https://openstax.org/books/anatomy-and-physiology-2e/pages/21-6-diseases-associated-with-depressed-or-overactive-immune-responses",
      "cell-hematopoietic-stem-cell": "https://openstax.org/books/anatomy-and-physiology-2e/pages/18-2-production-of-the-formed-elements",
      "cell-helper-t-cell": "https://openstax.org/books/anatomy-and-physiology-2e/pages/21-3-the-adaptive-immune-response-t-lymphocytes-and-their-functional-types",
      "cell-cytotoxic-t-cell": "https://openstax.org/books/anatomy-and-physiology-2e/pages/21-3-the-adaptive-immune-response-t-lymphocytes-and-their-functional-types",
      "cell-regulatory-t-cell": "https://openstax.org/books/anatomy-and-physiology-2e/pages/21-3-the-adaptive-immune-response-t-lymphocytes-and-their-functional-types",
      "cell-pericyte": "https://pubmed.ncbi.nlm.nih.gov/16166562/",
      "cell-lymphatic-endothelial-cell": "https://openstax.org/books/anatomy-and-physiology-2e/pages/21-1-anatomy-of-the-lymphatic-and-immune-systems",
      "cell-sertoli-cell": "https://openstax.org/books/anatomy-and-physiology-2e/pages/27-1-anatomy-and-physiology-of-the-testicular-reproductive-system",
      "cell-spermatogonium": "https://openstax.org/books/anatomy-and-physiology-2e/pages/27-1-anatomy-and-physiology-of-the-testicular-reproductive-system",
      "cell-spermatocyte": "https://openstax.org/books/anatomy-and-physiology-2e/pages/27-1-anatomy-and-physiology-of-the-testicular-reproductive-system",
      "cell-ciliated-oviduct-cell": "https://openstax.org/books/anatomy-and-physiology-2e/pages/27-2-anatomy-and-physiology-of-the-ovarian-reproductive-system",
      "cell-endometrial-epithelial-cell": "https://openstax.org/books/anatomy-and-physiology-2e/pages/27-2-anatomy-and-physiology-of-the-ovarian-reproductive-system",
      "cell-endometrial-stromal-cell": "https://pubmed.ncbi.nlm.nih.gov/25141152/",
      "cell-mammary-luminal-cell": "https://openstax.org/books/anatomy-and-physiology-2e/pages/28-6-lactation",
      "cell-trophoblast": "https://openstax.org/books/anatomy-and-physiology-2e/pages/28-2-embryonic-development",
      "cell-langerhans-cell": "https://pubmed.ncbi.nlm.nih.gov/23246038/",
      "cell-sebocyte": "https://openstax.org/books/anatomy-and-physiology-2e/pages/5-2-accessory-structures-of-the-skin",
      "cell-sweat-gland-secretory-cell": "https://openstax.org/books/anatomy-and-physiology-2e/pages/5-2-accessory-structures-of-the-skin",
      "cell-hair-matrix-cell": "https://openstax.org/books/anatomy-and-physiology-2e/pages/5-2-accessory-structures-of-the-skin",
      "cell-muscle-satellite-cell": "https://openstax.org/books/anatomy-and-physiology-2e/pages/10-9-development-and-regeneration-of-muscle-tissue",
      "cell-tenocyte": "https://pubmed.ncbi.nlm.nih.gov/24571576/",
      "sweat-glands": "https://openstax.org/books/anatomy-and-physiology-2e/pages/5-2-accessory-structures-of-the-skin",
      "hair-follicles": "https://openstax.org/books/anatomy-and-physiology-2e/pages/5-2-accessory-structures-of-the-skin"
    ]
    static let paperSources = Set(["16166562", "25141152", "23246038", "24571576"].map {
      URL(string: "https://pubmed.ncbi.nlm.nih.gov/" + $0 + "/")!
    })
    static func read(bundle: Bundle) throws -> Self? {
      guard let data = NSDataAsset(name: "HealthAtlasCellContexts", bundle: bundle)?.data else { return nil }
      guard data.count <= 128_000 else { throw Invalid.catalogue }
      return try JSONDecoder().decode(Self.self, from: data)
    }
    func applying(to base: GalaxySSIHealthAtlas, bundle: Bundle) throws -> GalaxySSIHealthAtlas {
      let targets: Set<String> = ["sweat-glands", "hair-follicles"]
      guard schema == 1, mechanisms.count == 2, Set(mechanisms.map(\.id)) == targets,
        targets.allSatisfy({ base.entry($0)?.kind == .organ }), targets.isDisjoint(with: Set(base.mechanisms.map(\.id))),
        mechanisms.allSatisfy({ model in
          let stem = "health_atlas_context_" + (model.id == "sweat-glands" ? "sweat" : "hair")
          return model.kind == "skin" && model.reference == nil && model.title == stem + "_title" &&
            model.stages == (0..<4).map { stem + "_stage_" + String($0) } &&
            model.chapter == "5-2-accessory-structures-of-the-skin"
        }) else { throw Invalid.catalogue }
      let atlas = try GalaxySSIHealthAtlas.validated(.init(schema: base.schema,
        entries: base.entries.map { targets.contains($0.id) ? $0.replacing(mechanism: $0.id) : $0 },
        mechanisms: mechanisms + base.mechanisms), requireCompleteMicroscopic: true)
      guard plates.count == 23, plates.compactMap(\.owner) == Self.owners, Set(plates.map(\.id)).count == 23,
        plates.flatMap(\.annotations).count == 46, plates.flatMap(\.markers).count == 2,
        plates.allSatisfy({ plate in
          guard let owner = plate.owner, atlas.entry(owner)?.kind == (targets.contains(owner) ? .organ : .cell),
            plate.id == owner, plate.entryIDs == [owner] + plate.markers.map(\.id),
            plate.source?.absoluteString == Self.sources[owner], plate.asset.hasPrefix("HealthAtlasContext"),
            UIImage(named: plate.asset, in: bundle, compatibleWith: nil) != nil, plate.aspectRatio == 360.0 / 280,
            plate.annotations.count == 2,
            Set(plate.markers.map(\.id) + plate.annotations.map(\.id)).count == plate.markers.count + plate.annotations.count
          else { return false }
          return plate.markers.allSatisfy { atlas.entry($0.id)?.kind == .cell } && plate.annotations.allSatisfy { feature in
            atlas.entry(feature.id) == nil && feature.title.hasPrefix("health_atlas_context_") &&
              feature.explanation == feature.title + "_detail" && ["en", "zh-Hans"].allSatisfy { language in
                GalaxySSIHealthAtlasText.get(feature.title, language) != feature.title &&
                  GalaxySSIHealthAtlasText.get(feature.explanation, language) != feature.explanation
              }
          }
        }) else { throw Invalid.catalogue }
      let microscopic = atlas.entries.filter { $0.kind == .cell || $0.kind == .fragment }
      let pictures = microscopic.compactMap { atlas.plate(for: $0.id) }
      guard pictures.count == microscopic.count, Set(pictures.map(\.asset)).count == microscopic.count,
        zip(microscopic, pictures).allSatisfy({ entry, picture in
          entry.id == picture.owner && UIImage(named: picture.asset, in: bundle, compatibleWith: nil) != nil
        }) else { throw Invalid.catalogue }
      return atlas
    }
  }
}
