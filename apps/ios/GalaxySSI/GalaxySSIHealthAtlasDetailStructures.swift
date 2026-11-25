import Foundation
import UIKit

extension GalaxySSIHealthAtlas {
  struct DetailStructurePack: Decodable {
    let schema: Int
    let source: GalaxySSIHealthAtlasFunctionCatalogue.Source
    let plates: [Plate]
    static let bundled: Result<Self?, Error> = Result { try read(bundle: .main) }
    static let owners = ["cornea","lens","renal-cortex","renal-medulla","renal-pelvis","gallbladder","parotid-glands","submandibular-glands","ureters","bladder","urethra","aorta","pulmonary-trunk","coronary-vessels","larynx","trachea","bronchi","middle-ear","cochlea","vestibular-apparatus","brainstem","cerebellum","spinal-cord","scapula","humerus","tibia"]
    static let sources = Set([
      "https://pmc.ncbi.nlm.nih.gov/articles/PMC9317547/",
      "https://pubmed.ncbi.nlm.nih.gov/8641842/",
      "https://histologylab.ctl.columbia.edu/lab12/kidney/",
      "https://openstax.org/books/anatomy-and-physiology-2e/pages/25-3-gross-anatomy-of-the-kidney",
      "https://anatomy.ttuhscep.edu/gastrointestinal_system/duodenum_tables.html",
      "https://pmc.ncbi.nlm.nih.gov/articles/PMC4048853/",
      "https://www.ncbi.nlm.nih.gov/sites/books/NBK538325/",
      "https://histology.leeds.ac.uk/home/urinary/ureter/",
      "https://openstax.org/books/anatomy-and-physiology-2e/pages/25-2-gross-anatomy-of-urine-transport",
      "https://pubmed.ncbi.nlm.nih.gov/14672484/",
      "https://www.ncbi.nlm.nih.gov/books/NBK538140/",
      "https://www.ncbi.nlm.nih.gov/books/NBK534812/",
      "https://pmc.ncbi.nlm.nih.gov/articles/PMC287879/",
      "https://openstax.org/books/anatomy-and-physiology-2e/pages/22-1-organs-and-structures-of-the-respiratory-system",
      "https://pmc.ncbi.nlm.nih.gov/articles/PMC4404098/",
      "https://pmc.ncbi.nlm.nih.gov/articles/PMC4718166/",
      "https://pmc.ncbi.nlm.nih.gov/articles/PMC6753699/",
      "https://pmc.ncbi.nlm.nih.gov/articles/PMC10039035/",
      "https://brain.oit.duke.edu/lab03/lab03.html",
      "https://nba.uth.tmc.edu/neuroscience/s3/chapter05.html",
      "https://cumming.ucalgary.ca/sites/default/files/teams/122/education/neurosurgery/spine3-sl-anatomy-of-the-spinal-cord.pdf",
      "https://openstax.org/books/anatomy-and-physiology-2e/pages/8-1-the-pectoral-girdle",
      "https://openstax.org/books/anatomy-and-physiology-2e/pages/8-2-bones-of-the-upper-limb",
      "https://openstax.org/books/anatomy-and-physiology-2e/pages/8-4-bones-of-the-lower-limb"
    ].compactMap { URL(string: $0) })
    static func read(bundle: Bundle) throws -> Self? {
      guard let data = NSDataAsset(name: "HealthAtlasDetailStructures", bundle: bundle)?.data else { return nil }
      guard data.count <= 256_000 else { throw Invalid.catalogue }
      return try JSONDecoder().decode(Self.self, from: data)
    }
    static func plate(for id: String?) -> Plate? {
      guard let id, let pack = try? bundled.get() else { return nil }
      return pack.plates.first { $0.owner == id }
    }
    func validating(in atlas: GalaxySSIHealthAtlas, bundle: Bundle) throws {
      guard schema == 1, source.androidPR == 4389,
        source.mergeCommit == "9508d49277cf33ab7f85e65722e7c470930fff7e",
        plates.count == 26, plates.compactMap(\.owner) == Self.owners,
        Set(plates.map(\.id)).count == 26,
        plates.flatMap(\.annotations).count == 139, plates.flatMap(\.markers).count == 3,
        plates.allSatisfy({ plate in
          guard let owner = plate.owner, atlas.entry(owner) != nil, plate.id == plate.viewKey,
            plate.entryIDs == [owner] + plate.markers.map(\.id), plate.aspectRatio == 360.0 / 280,
            let source = plate.source, Self.sources.contains(source), plate.asset.hasPrefix("HealthAtlasDetail"),
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
