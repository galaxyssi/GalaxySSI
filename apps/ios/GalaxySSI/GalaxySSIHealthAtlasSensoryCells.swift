import Foundation
import UIKit

extension GalaxySSIHealthAtlas {
  struct SensoryPack: Decodable {
    let schema: Int
    let entries: [Entry]
    let mechanisms: [Mechanism]
    let plates: [Plate]
    static let bundled: Result<Self?, Error> = Result { try read(bundle: .main) }
    static let relayIDs = ["cell-retinal-bipolar-cell", "cell-retinal-aii-amacrine-cell"]
    static let portraitOwners: Set<String> = ["cell-rod-photoreceptor", "cell-cone-photoreceptor", "cell-inner-ear-hair-cell"]
    static let owners = ["cell-oligodendrocyte", "cell-microglia", "cell-ependymal-cell", "cell-satellite-glial-cell", "cell-rod-photoreceptor", "cell-cone-photoreceptor", "cell-retinal-pigment-epithelial-cell", "cell-retinal-ganglion-cell", "cell-inner-ear-hair-cell", "cell-olfactory-receptor-neuron", "cell-taste-receptor-cell", "cell-corneal-epithelial-cell", "cell-merkel-cell", "cell-retinal-bipolar-cell", "cell-retinal-aii-amacrine-cell", "retina"]
    static let sources = [
      "cell-oligodendrocyte": "https://openstax.org/books/anatomy-and-physiology-2e/pages/12-2-nervous-tissue",
      "cell-microglia": "https://openstax.org/books/anatomy-and-physiology-2e/pages/12-2-nervous-tissue",
      "cell-ependymal-cell": "https://openstax.org/books/anatomy-and-physiology-2e/pages/12-2-nervous-tissue",
      "cell-satellite-glial-cell": "https://openstax.org/books/anatomy-and-physiology-2e/pages/12-2-nervous-tissue",
      "cell-rod-photoreceptor": "https://www.ncbi.nlm.nih.gov/books/NBK10885/",
      "cell-cone-photoreceptor": "https://www.ncbi.nlm.nih.gov/books/NBK10885/",
      "cell-retinal-pigment-epithelial-cell": "https://pubmed.ncbi.nlm.nih.gov/15987797/",
      "cell-retinal-ganglion-cell": "https://www.ncbi.nlm.nih.gov/books/NBK10885/",
      "cell-inner-ear-hair-cell": "https://openstax.org/books/anatomy-and-physiology-2e/pages/14-1-sensory-perception",
      "cell-olfactory-receptor-neuron": "https://openstax.org/books/anatomy-and-physiology-2e/pages/14-1-sensory-perception",
      "cell-taste-receptor-cell": "https://openstax.org/books/anatomy-and-physiology-2e/pages/14-1-sensory-perception",
      "cell-corneal-epithelial-cell": "https://pubmed.ncbi.nlm.nih.gov/26310149/",
      "cell-merkel-cell": "https://openstax.org/books/anatomy-and-physiology-2e/pages/14-1-sensory-perception",
      "cell-retinal-bipolar-cell": "https://pubmed.ncbi.nlm.nih.gov/28856684/",
      "cell-retinal-aii-amacrine-cell": "https://pubmed.ncbi.nlm.nih.gov/28856684/",
      "retina": "https://www.ncbi.nlm.nih.gov/books/NBK10885/"
    ]
    static let externalSources: Set<URL> = Set([
      "https://www.ncbi.nlm.nih.gov/books/NBK10885/", "https://pubmed.ncbi.nlm.nih.gov/15987797/",
      "https://pubmed.ncbi.nlm.nih.gov/26310149/", "https://pubmed.ncbi.nlm.nih.gov/28856684/"
    ].map { URL(string: $0)! })
    static func read(bundle: Bundle) throws -> Self? {
      guard let data = NSDataAsset(name: "HealthAtlasSensoryCells", bundle: bundle)?.data else { return nil }
      guard data.count <= 128_000 else { throw Invalid.catalogue }
      return try JSONDecoder().decode(Self.self, from: data)
    }
    func applying(to base: GalaxySSIHealthAtlas, bundle: Bundle) throws -> GalaxySSIHealthAtlas {
      let ids = Set(Self.relayIDs + ["retina"])
      guard schema == 1, entries.map(\.id) == Self.relayIDs, entries.allSatisfy({ entry in
          entry.kind == .cell && base.entry(entry.id) == nil && entry.mechanism == entry.id &&
            entry.systems == ["sensory", "nervous"] && entry.related == ["retina"] &&
            entry.name.hasPrefix("health_atlas_sensory_") && entry.description.hasPrefix("health_atlas_sensory_")
        }), base.entry("retina")?.kind == .organ, base.entry("cell-retinal-ganglion-cell")?.kind == .cell,
        mechanisms.count == 3, Set(mechanisms.map(\.id)) == ids, ids.isDisjoint(with: Set(base.mechanisms.map(\.id))),
        mechanisms.allSatisfy({ model in
          let stem = model.id == "retina" ? "retinal_path" : model.id == Self.relayIDs[0] ? "bipolar" : "aii"
          let prefix = "health_atlas_sensory_" + stem
          return model.kind == (model.id == "retina" ? "vision" : "cell") &&
            model.title == prefix + "_title" &&
            model.stages == (0..<4).map { prefix + (model.id == "retina" ? "_" : "_stage_") + String($0) } &&
            model.chapter == "14-1-sensory-perception" && model.reference == GalaxySSIHealthAtlasRetinaPath.source
        }) else { throw Invalid.catalogue }
      let revised = base.entries.flatMap { entry -> [Entry] in
        let item = entry.id == "retina" ? entry.replacing(mechanism: "retina") : entry
        return [item] + (entry.id == "cell-retinal-ganglion-cell" ? entries : [])
      }
      let atlas = try GalaxySSIHealthAtlas.validated(.init(schema: base.schema, entries: revised,
        mechanisms: mechanisms + base.mechanisms), requireCompleteMicroscopic: true)
      guard plates.count == 16, plates.compactMap(\.owner) == Self.owners, Set(plates.map(\.id)).count == 16,
        plates.flatMap(\.annotations).count == 34, plates.flatMap(\.markers).count == 3,
        plates.allSatisfy({ plate in
          guard let owner = plate.owner, atlas.entry(owner)?.kind == (owner == "retina" ? .organ : .cell),
            plate.id == owner, plate.entryIDs == [owner] + plate.markers.map(\.id), plate.source?.absoluteString == Self.sources[owner],
            plate.asset.hasPrefix("HealthAtlasSensory"), UIImage(named: plate.asset, in: bundle, compatibleWith: nil) != nil,
            plate.aspectRatio == (Self.portraitOwners.contains(owner) ? 2.0 / 3 : 360.0 / 280), (2...4).contains(plate.annotations.count),
            Set(plate.markers.map(\.id) + plate.annotations.map(\.id)).count == plate.markers.count + plate.annotations.count
          else { return false }
          if owner == "retina" {
            guard plate.viewKey == "retina-layers", plate.selectorLabel == "health_atlas_sensory_retinal_layers",
              plate.markers.map(\.id) == ["cell-retinal-ganglion-cell", "cell-rod-photoreceptor", "cell-cone-photoreceptor"] else { return false }
          } else if !plate.markers.isEmpty || plate.viewKey != nil || plate.selectorLabel != nil { return false }
          return plate.markers.allSatisfy { atlas.entry($0.id)?.kind == .cell } && plate.annotations.allSatisfy { feature in
            atlas.entry(feature.id) == nil && feature.title.hasPrefix("health_atlas_sensory_") &&
              feature.explanation == feature.title + "_detail" && ["en", "zh-Hans"].allSatisfy { language in
                GalaxySSIHealthAtlasText.get(feature.title, language) != feature.title &&
                  GalaxySSIHealthAtlasText.get(feature.explanation, language) != feature.explanation
              }
          }
        }) else { throw Invalid.catalogue }
      return atlas
    }
  }
}
