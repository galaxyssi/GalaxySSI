import Foundation
import UIKit

extension GalaxySSIHealthAtlas {
  struct DigestivePack: Decodable {
    let schema: Int
    let plates: [Plate]
    let mechanisms: [Mechanism]
    static let bundled: Result<Self?, Error> = Result { try read(bundle: .main) }
    static let owners = ["cell-gastric-parietal-cell", "cell-gastric-chief-cell", "cell-paneth-cell", "cell-enteroendocrine-cell", "cell-intestinal-stem-cell", "cell-cholangiocyte", "cell-pancreatic-acinar-cell", "cell-pancreatic-ductal-cell", "cell-salivary-acinar-cell", "cell-pancreatic-alpha-cell", "cell-pancreatic-delta-cell", "cell-pancreatic-pp-cell", "cell-myoepithelial-cell", "pancreatic-islets"]
    static let sources = [
      "cell-gastric-parietal-cell": "https://openstax.org/books/anatomy-and-physiology-2e/pages/23-4-the-stomach",
      "cell-gastric-chief-cell": "https://openstax.org/books/anatomy-and-physiology-2e/pages/23-4-the-stomach",
      "cell-paneth-cell": "https://openstax.org/books/anatomy-and-physiology-2e/pages/23-5-the-small-and-large-intestines",
      "cell-enteroendocrine-cell": "https://openstax.org/books/anatomy-and-physiology-2e/pages/23-5-the-small-and-large-intestines",
      "cell-intestinal-stem-cell": "https://pubmed.ncbi.nlm.nih.gov/32586946/",
      "cell-cholangiocyte": "https://pubmed.ncbi.nlm.nih.gov/27563020/",
      "cell-pancreatic-acinar-cell": "https://openstax.org/books/anatomy-and-physiology-2e/pages/23-6-accessory-organs-in-digestion-the-liver-pancreas-and-gallbladder",
      "cell-pancreatic-ductal-cell": "https://openstax.org/books/anatomy-and-physiology-2e/pages/23-6-accessory-organs-in-digestion-the-liver-pancreas-and-gallbladder",
      "cell-salivary-acinar-cell": "https://openstax.org/books/anatomy-and-physiology-2e/pages/23-3-the-mouth-pharynx-and-esophagus",
      "cell-pancreatic-alpha-cell": "https://openstax.org/books/anatomy-and-physiology-2e/pages/17-9-the-endocrine-pancreas",
      "cell-pancreatic-delta-cell": "https://openstax.org/books/anatomy-and-physiology-2e/pages/17-9-the-endocrine-pancreas",
      "cell-pancreatic-pp-cell": "https://openstax.org/books/anatomy-and-physiology-2e/pages/17-9-the-endocrine-pancreas",
      "cell-myoepithelial-cell": "https://openstax.org/books/anatomy-and-physiology-2e/pages/28-6-lactation",
      "pancreatic-islets": "https://pubmed.ncbi.nlm.nih.gov/16461897/"
    ]
    static let paperSources: Set<URL> = Set(["32586946", "27563020", "16461897"].map {
      URL(string: "https://pubmed.ncbi.nlm.nih.gov/" + $0 + "/")!
    })
    static func read(bundle: Bundle) throws -> Self? {
      guard let data = NSDataAsset(name: "HealthAtlasDigestiveCells", bundle: bundle)?.data else { return nil }
      guard data.count <= 128_000 else { throw Invalid.catalogue }
      return try JSONDecoder().decode(Self.self, from: data)
    }
    func applying(to base: GalaxySSIHealthAtlas, bundle: Bundle) throws -> GalaxySSIHealthAtlas {
      let targets: Set<String> = ["pancreas", "pancreatic-islets"]
      guard schema == 1, mechanisms.count == 2, Set(mechanisms.map(\.id)) == targets,
        targets.allSatisfy({ base.entry($0)?.kind == .organ }),
        targets.isDisjoint(with: Set(base.mechanisms.map(\.id))),
        mechanisms.allSatisfy({ model in
          let stem = "health_atlas_digestive_" + (model.id == "pancreas" ? "pancreas" : "islets")
          return model.kind == "secretion" && model.reference == nil && model.title == stem + "_title" &&
            model.stages == (0..<4).map { stem + "_" + String($0) } &&
            model.chapter == (model.id == "pancreas" ? "23-6-accessory-organs-in-digestion-the-liver-pancreas-and-gallbladder" : "17-9-the-endocrine-pancreas")
        }) else { throw Invalid.catalogue }
      let atlas = try GalaxySSIHealthAtlas.validated(.init(schema: base.schema,
        entries: base.entries.map { targets.contains($0.id) ? $0.replacing(mechanism: $0.id) : $0 },
        mechanisms: mechanisms + base.mechanisms), requireCompleteMicroscopic: true)
      guard plates.count == 14, plates.compactMap(\.owner) == Self.owners, Set(plates.map(\.id)).count == 14,
        plates.flatMap(\.annotations).count == 27, plates.flatMap(\.markers).count == 4,
        plates.allSatisfy({ plate in
          guard let owner = plate.owner, atlas.entry(owner)?.kind == (owner == "pancreatic-islets" ? .organ : .cell),
            plate.id == owner, plate.entryIDs == [owner] + plate.markers.map(\.id),
            plate.source?.absoluteString == Self.sources[owner], plate.asset.hasPrefix("HealthAtlasDigestive"),
            UIImage(named: plate.asset, in: bundle, compatibleWith: nil) != nil, plate.aspectRatio == 360.0 / 280,
            (1...2).contains(plate.annotations.count),
            Set(plate.markers.map(\.id) + plate.annotations.map(\.id)).count == plate.markers.count + plate.annotations.count,
            (owner == "pancreatic-islets" ? Set(plate.markers.map(\.id)) == Set(GalaxySSIHealthAtlasPancreatic.isletCells) : plate.markers.isEmpty)
          else { return false }
          return plate.markers.allSatisfy { atlas.entry($0.id)?.kind == .cell } && plate.annotations.allSatisfy { feature in
            atlas.entry(feature.id) == nil && feature.title.hasPrefix("health_atlas_digestive_") &&
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
