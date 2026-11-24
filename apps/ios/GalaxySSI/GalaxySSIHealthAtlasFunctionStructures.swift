import Foundation
import UIKit

extension GalaxySSIHealthAtlas {
  struct FunctionStructurePack: Decodable {
    let schema: Int
    let source: GalaxySSIHealthAtlasFunctionCatalogue.Source
    let plates: [Plate]
    static let bundled: Result<Self?, Error> = Result { try read(bundle: .main) }
    static let owners = ["rectus-abdominis", "oblique-abdominal-muscles", "erector-spinae", "appendix", "autonomic-nerves", "ligaments", "placenta", "hair", "limb-bones", "cranial-nerves", "radius", "olfactory-mucosa", "deltoid", "trapezius", "cell-microglia", "cell-ependymal-cell", "ribs", "cartilage", "joints", "pineal-gland", "biliary-tract", "blood-vessels", "arteries", "blood", "hypothalamus", "bronchioles", "taste-buds", "paranasal-sinuses", "pleura", "cell-mast-cell", "cell-hematopoietic-stem-cell", "cell-helper-t-cell", "cell-cytotoxic-t-cell", "cell-regulatory-t-cell", "cell-pericyte", "cell-lymphatic-endothelial-cell", "cell-sertoli-cell", "cell-spermatogonium", "cell-spermatocyte", "cell-ciliated-oviduct-cell", "cell-endometrial-epithelial-cell", "cell-endometrial-stromal-cell", "cell-mammary-luminal-cell", "cell-trophoblast", "cell-langerhans-cell", "cell-sebocyte", "cell-sweat-gland-secretory-cell", "cell-hair-matrix-cell", "cell-muscle-satellite-cell", "cell-tenocyte", "sweat-glands", "hair-follicles", "nails", "sebaceous-glands"]
    static let sources = Set([
      "https://openstax.org/books/anatomy-and-physiology-2e/pages/11-4-axial-muscles-of-the-abdominal-wall-and-thorax",
      "https://openstax.org/books/anatomy-and-physiology-2e/pages/11-3-axial-muscles-of-the-head-neck-and-back",
      "https://histology.leeds.ac.uk/home/digestive/appendix/",
      "https://openstax.org/books/anatomy-and-physiology-2e/pages/15-1-divisions-of-the-autonomic-nervous-system",
      "https://openstax.org/books/anatomy-and-physiology-2e/pages/9-6-anatomy-of-selected-synovial-joints",
      "https://openstax.org/books/anatomy-and-physiology-2e/pages/28-2-embryonic-development",
      "https://pmc.ncbi.nlm.nih.gov/articles/PMC12272604/",
      "https://openstax.org/books/anatomy-and-physiology-2e/pages/8-introduction",
      "https://pmc.ncbi.nlm.nih.gov/articles/PMC9431917/",
      "https://openstax.org/books/anatomy-and-physiology-2e/pages/8-2-bones-of-the-upper-limb",
      "https://pmc.ncbi.nlm.nih.gov/articles/PMC9232960/",
      "https://temple.manifoldapp.org/read/hands-on-anatomy-c6538f97-bc62-44ae-96ff-0f1f97d6c977/section/9967a151-8e94-450d-90e8-c84aad0aca9f",
      "https://openstax.org/books/anatomy-and-physiology/pages/11-5-muscles-of-the-pectoral-girdle-and-upper-limbs",
      "https://nba.uth.tmc.edu/neuroscience/m/s1/chapter08.html",
      "https://openstax.org/books/anatomy-and-physiology-2e/pages/7-4-the-thoracic-cage",
      "https://pubmed.ncbi.nlm.nih.gov/24455780/",
      "https://openstax.org/books/anatomy-and-physiology-2e/pages/9-4-synovial-joints",
      "https://pmc.ncbi.nlm.nih.gov/articles/PMC3675249/",
      "https://www.ncbi.nlm.nih.gov/books/NBK459246/",
      "https://openstax.org/books/anatomy-and-physiology-2e/pages/20-1-structure-and-function-of-blood-vessels",
      "https://www.hematology.org/resources/patients/blood-basics",
      "https://www.ncbi.nlm.nih.gov/books/NBK279126/",
      "https://histology.oit.duke.edu/NormalBody/Respiratory/Respiratory.html",
      "https://openstax.org/books/introduction-behavioral-neuroscience/pages/8-2-the-gustatory-system",
      "https://pmc.ncbi.nlm.nih.gov/articles/PMC7944018/",
      "https://pubmed.ncbi.nlm.nih.gov/5693173/",
      "https://openstax.org/books/anatomy-and-physiology-2e/pages/21-6-diseases-associated-with-depressed-or-overactive-immune-responses",
      "https://openstax.org/books/anatomy-and-physiology-2e/pages/18-2-production-of-the-formed-elements",
      "https://openstax.org/books/anatomy-and-physiology-2e/pages/21-3-the-adaptive-immune-response-t-lymphocytes-and-their-functional-types",
      "https://pubmed.ncbi.nlm.nih.gov/16166562/",
      "https://openstax.org/books/anatomy-and-physiology-2e/pages/21-1-anatomy-of-the-lymphatic-and-immune-systems",
      "https://openstax.org/books/anatomy-and-physiology-2e/pages/27-1-anatomy-and-physiology-of-the-testicular-reproductive-system",
      "https://openstax.org/books/anatomy-and-physiology-2e/pages/27-2-anatomy-and-physiology-of-the-ovarian-reproductive-system",
      "https://pubmed.ncbi.nlm.nih.gov/25141152/",
      "https://openstax.org/books/anatomy-and-physiology-2e/pages/28-6-lactation",
      "https://pubmed.ncbi.nlm.nih.gov/23246038/",
      "https://openstax.org/books/anatomy-and-physiology-2e/pages/5-2-accessory-structures-of-the-skin",
      "https://openstax.org/books/anatomy-and-physiology-2e/pages/10-9-development-and-regeneration-of-muscle-tissue",
      "https://pubmed.ncbi.nlm.nih.gov/24571576/",
      "https://doi.org/10.1002/ar.22660",
      "https://pubmed.ncbi.nlm.nih.gov/38542083/"
    ].compactMap { URL(string: $0) })
    static func read(bundle: Bundle) throws -> Self? {
      guard let data = NSDataAsset(name: "HealthAtlasFunctionStructures", bundle: bundle)?.data else { return nil }
      guard data.count <= 384_000 else { throw Invalid.catalogue }
      return try JSONDecoder().decode(Self.self, from: data)
    }
    static func plate(for id: String?) -> Plate? {
      guard let id, let pack = try? bundled.get() else { return nil }
      return pack.plates.first { $0.owner == id }
    }
    func validating(in atlas: GalaxySSIHealthAtlas, bundle: Bundle) throws {
      guard schema == 1, source.androidPR == 4384,
        source.mergeCommit == "ab78711d467c013444883dbaeca23c39a601c875",
        plates.count == 54, plates.compactMap(\.owner) == Self.owners, Set(plates.map(\.id)).count == 54,
        plates.flatMap(\.annotations).count == 177, plates.flatMap(\.markers).count == 27,
        plates.allSatisfy({ plate in
          guard let owner = plate.owner, atlas.entry(owner) != nil, plate.id == owner,
            plate.entryIDs == [owner] + plate.markers.map(\.id), plate.aspectRatio == 360.0 / 280,
            let source = plate.source, Self.sources.contains(source),
            plate.asset.hasPrefix("HealthAtlasStructure") ||
              ["HealthAtlasFunctionErector", "HealthAtlasFunctionLigaments", "HealthAtlasFunctionPlacenta", "HealthAtlasFunctionPineal"].contains(plate.asset),
            UIImage(named: plate.asset, in: bundle, compatibleWith: nil) != nil,
            Set(plate.markers.map(\.id) + plate.annotations.map(\.id)).count == plate.markers.count + plate.annotations.count
          else { return false }
          let points = plate.markers + plate.annotations.map(\.marker)
          let keys = [plate.viewLabel] + (plate.selectorLabel.map { [$0] } ?? []) +
            plate.annotations.flatMap { [$0.title, $0.explanation] }
          return plate.markers.allSatisfy { atlas.entry($0.id) != nil } &&
            plate.annotations.allSatisfy { atlas.entry($0.id) == nil } &&
            points.allSatisfy { $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) } &&
            keys.allSatisfy { key in
              key.hasPrefix("health_atlas_") && ["en", "zh-Hans"].allSatisfy {
                GalaxySSIHealthAtlasText.get(key, $0) != key
              }
            }
        }) else { throw Invalid.catalogue }
    }
  }
}
