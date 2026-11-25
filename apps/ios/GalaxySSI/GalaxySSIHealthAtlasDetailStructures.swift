import Foundation
import UIKit

extension GalaxySSIHealthAtlas {
  struct DetailStructurePack: Decodable {
    let schema: Int
    let source: GalaxySSIHealthAtlasFunctionCatalogue.Source
    let plates: [Plate]
    static let bundled: Result<Self?, Error> = Result { try read(bundle: .main) }
    static let owners = ["cornea","lens","renal-cortex","renal-medulla","renal-pelvis","gallbladder","parotid-glands","submandibular-glands","ureters","bladder","urethra","aorta","pulmonary-trunk","coronary-vessels","larynx","trachea","bronchi","middle-ear","cochlea","vestibular-apparatus","brainstem","cerebellum","spinal-cord","scapula","humerus","tibia"]
    static let expandedOwners = owners + ["skin-organ","epidermis","dermis","right-atrium","left-atrium","right-ventricle","left-ventricle","tricuspid-valve","mitral-valve","pulmonary-valve","aortic-valve","external-ear","inner-ear","nose","tongue","glomerulus","bowmans-capsule","proximal-tubule","nephron-loop","cerebrum","peripheral-nerves","spinal-nerves","ganglia","ovaries","testes","uterine-tubes","endometrium","biceps-brachii","triceps-brachii","quadriceps-femoris","hamstrings","femur","patella","foot-bones","ulna"]
    static let sources = Set([
      "https://openstax.org/books/anatomy-and-physiology-2e/pages/5-1-layers-of-the-skin",
      "https://histology.leeds.ac.uk/home/skin/epidermis_layers/",
      "https://openstax.org/books/anatomy-and-physiology-2e/pages/19-1-heart-anatomy",
      "https://onlinelibrary.wiley.com/doi/10.1111/j.0021-8782.2004.00330.x",
      "https://doi.org/10.1002/ca.22591",
      "https://doi.org/10.1530/ERP-20-0034",
      "https://www.asecho.org/wp-content/uploads/2022/01/PIIS0894731721005940.pdf",
      "https://www.vhlab.umn.edu/atlas/anatomy-tutorial/cardiac-valve-nomenclature.shtml",
      "https://pmc.ncbi.nlm.nih.gov/articles/PMC11630884/",
      "https://www.nature.com/articles/s41598-021-82716-0",
      "https://peir.path.uab.edu/wiki/Histologic:Chapter_11#Tongue",
      "https://openstax.org/books/anatomy-and-physiology-2e/pages/25-4-microscopic-anatomy-of-the-kidney",
      "https://histology.oit.duke.edu/NormalBody/Urinary/Urinary.html",
      "https://histopathology.pennstatehealth.net/slideview/MH-141b-kidney/16-slide-1.html?page=1",
      "https://brain.oit.duke.edu/lab01/lab01.html",
      "https://openstax.org/books/anatomy-and-physiology-2e/pages/13-4-the-peripheral-nervous-system",
      "https://nba.uth.tmc.edu/neuroscience/m/s2/chapter03.html",
      "https://pmc.ncbi.nlm.nih.gov/articles/PMC6598622/",
      "https://histology.oit.duke.edu/NormalBody/FemaleRepro/FemaleRepro.html",
      "https://openstax.org/books/anatomy-and-physiology-2e/pages/27-1-anatomy-and-physiology-of-the-testicular-reproductive-system",
      "https://histopathology.pennstatehealth.net/slideview/MH-171-oviduct/18-slide-1.html",
      "https://histology.leeds.ac.uk/home/female/uterus/",
      "https://anatomy.ttuhscep.edu/musculoskeletal_system/axilla_tables.html",
      "https://anatomy.ttuhscep.edu/musculoskeletal_system/thigh_tables.html",
      "https://anatomy.ttuhscep.edu/musculoskeletal_system/gluteal_tables.html",
      "https://faculty.ksu.edu.sa/sites/default/files/2_humanskeletalanatomy.pdf#page=19",
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
    static func read(bundle: Bundle, revision: Int = 4391) throws -> Self? {
      guard [4389, 4391].contains(revision) else { throw Invalid.catalogue }
      let asset = revision == 4389 ? "HealthAtlasDetailStructures" : "HealthAtlasExpandedDetailStructures"
      guard let data = NSDataAsset(name: asset, bundle: bundle)?.data else { return nil }
      guard data.count <= 256_000 else { throw Invalid.catalogue }
      let value = try JSONDecoder().decode(Self.self, from: data)
      guard value.source.androidPR == revision else { throw Invalid.catalogue }
      return value
    }
    static func plate(for id: String?) -> Plate? {
      guard let id, let pack = try? bundled.get() else { return nil }
      return pack.plates.first { $0.owner == id }
    }
    func validating(in atlas: GalaxySSIHealthAtlas, bundle: Bundle) throws {
      let detail = source.androidPR == 4389 && source.mergeCommit == "9508d49277cf33ab7f85e65722e7c470930fff7e"
      let expanded = source.androidPR == 4391 && source.mergeCommit == "165809fc9606ac1ff6b0df6eb9bee73286b415ea"
      let owners = expanded ? Self.expandedOwners : Self.owners
      guard schema == 1, detail || expanded,
        plates.count == owners.count, plates.compactMap(\.owner) == owners,
        Set(plates.map(\.id)).count == owners.count,
        plates.flatMap(\.annotations).count == (expanded ? 279 : 139),
        plates.flatMap(\.markers).count == (expanded ? 52 : 3),
        plates.allSatisfy({ plate in
          guard let owner = plate.owner, atlas.entry(owner) != nil, plate.id == plate.viewKey,
            plate.entryIDs == [owner] + plate.markers.map(\.id), plate.aspectRatio == 360.0 / 280,
            let source = plate.source, Self.sources.contains(source),
            (Self.owners.contains(owner) ? plate.asset.hasPrefix("HealthAtlasDetail") :
              expanded && plate.asset.hasPrefix("HealthAtlasExpanded")),
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
