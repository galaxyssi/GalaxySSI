import Foundation
import UIKit

extension GalaxySSIHealthAtlas {
  struct RegionalStructurePack: Decodable {
    let schema: Int
    let source: GalaxySSIHealthAtlasFunctionCatalogue.Source
    let plates: [Plate]
    static let bundled: Result<Self?, Error> = Result { try read(bundle: .main) }
    static let owners = ["fibula","clavicle","mammary-glands","soleus","rectus-abdominis","oblique-abdominal-muscles","erector-spinae","appendix","autonomic-nerves","ligaments","placenta","hair","limb-bones","cranial-nerves","radius","olfactory-mucosa","deltoid","trapezius","cell-microglia","cell-ependymal-cell","ribs","cartilage","joints","pineal-gland","biliary-tract","blood-vessels","arteries","blood","hypothalamus","bronchioles","taste-buds","paranasal-sinuses","pleura","cell-mast-cell","cell-hematopoietic-stem-cell","cell-helper-t-cell","cell-cytotoxic-t-cell","cell-regulatory-t-cell","cell-pericyte","cell-lymphatic-endothelial-cell","cell-sertoli-cell","cell-spermatogonium","cell-spermatocyte","cell-ciliated-oviduct-cell","cell-endometrial-epithelial-cell","cell-endometrial-stromal-cell","cell-mammary-luminal-cell","cell-trophoblast","cell-langerhans-cell","cell-sebocyte","cell-sweat-gland-secretory-cell","cell-hair-matrix-cell","cell-muscle-satellite-cell","cell-tenocyte","sweat-glands","hair-follicles","nails","sebaceous-glands","vulva","labia-majora","labia-minora","uterus","cervix","bulbourethral-glands","penis","scrotum","skull","vertebrae","clitoris","greater-vestibular-glands","pectoralis-major","latissimus-dorsi","cell-tenocyte"]
    static let sources = FunctionStructurePack.sources.union(Set([
      "https://openstax.org/books/anatomy-and-physiology-2e/pages/8-4-bones-of-the-lower-limb",
      "https://openstax.org/books/anatomy-and-physiology-2e/pages/8-1-the-pectoral-girdle",
      "https://pmc.ncbi.nlm.nih.gov/articles/PMC1571528/",
      "https://pubmed.ncbi.nlm.nih.gov/32783229/",
      "https://openstax.org/books/biology/pages/43-3-human-reproductive-anatomy-and-gametogenesis",
      "https://training.seer.cancer.gov/cervical-uterine/anatomy/",
      "https://pmc.ncbi.nlm.nih.gov/articles/PMC8373982/",
      "https://openstax.org/books/anatomy-and-physiology-2e/pages/13-3-circulation-and-the-central-nervous-system",
      "https://openstax.org/books/anatomy-and-physiology-2e/pages/7-3-the-vertebral-column",
      "https://pubmed.ncbi.nlm.nih.gov/15879834/",
      "https://pmc.ncbi.nlm.nih.gov/articles/PMC9544139/",
      "https://rad.washington.edu/muscle-atlas/pectoralis-major/",
      "https://rad.washington.edu/muscle-atlas/latissimus-dorsi/",
      "https://doi.org/10.1111/joa.12164",
      "https://openstax.org/books/anatomy-and-physiology-2e/pages/8-3-the-pelvic-girdle-and-pelvis",
      "https://openstax.org/books/anatomy-and-physiology-2e/pages/5-1-layers-of-the-skin"
    ].compactMap { URL(string: $0) }))
    static let completeOwners = Array(owners.dropLast()) + ["pelvis", "subcutaneous-tissue", "cell-tenocyte"]
    static let loadTransferAssets = ["pelvis": "HealthAtlasCompletePelvicRing",
      "subcutaneous-tissue": "HealthAtlasCompleteSubcutaneousSection"]
    static func read(bundle: Bundle, revision: Int = 4388) throws -> Self? {
      guard [4385, 4388].contains(revision) else { throw Invalid.catalogue }
      let asset = revision == 4385 ? "HealthAtlasRegionalStructures" : "HealthAtlasCompleteStructures"
      guard let data = NSDataAsset(name: asset, bundle: bundle)?.data else { return nil }
      guard data.count <= 512_000 else { throw Invalid.catalogue }
      return try JSONDecoder().decode(Self.self, from: data)
    }
    static func views(for id: String?) -> [Plate] {
      guard let id, let pack = try? bundled.get() else { return [] }
      return pack.plates.filter { $0.owner == id }
    }
    static func plate(for id: String?) -> Plate? { views(for: id).first }
    func validating(in atlas: GalaxySSIHealthAtlas, bundle: Bundle) throws {
      let regional = source.androidPR == 4385 && source.mergeCommit == "a81aa85a1c81e41ff19a032eabea1eddcd2371dc"
      let complete = source.androidPR == 4388 && source.mergeCommit == "6581110ec5c048edebf63821dee839b4818fe663"
      let expectedOwners = complete ? Self.completeOwners : Self.owners
      guard schema == 1, regional || complete,
        plates.count == expectedOwners.count, plates.compactMap(\.owner) == expectedOwners,
        Set(plates.map(\.id)).count == expectedOwners.count,
        plates.flatMap(\.annotations).count == (complete ? 259 : 252),
        plates.flatMap(\.markers).count == (complete ? 41 : 36),
        plates.allSatisfy({ plate in
          guard let owner = plate.owner, atlas.entry(owner) != nil, plate.id == plate.viewKey,
            plate.entryIDs == [owner] + plate.markers.map(\.id), plate.aspectRatio == 360.0 / 280,
            let source = plate.source, Self.sources.contains(source),
            (Self.loadTransferAssets[owner].map { complete && plate.asset == $0 } ?? plate.asset.hasPrefix("HealthAtlasRegional")),
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
