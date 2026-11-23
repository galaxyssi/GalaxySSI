import Foundation
import UIKit

extension GalaxySSIHealthAtlas {
  struct Feature: Decodable, Identifiable {
    let marker: Marker
    let title: String
    let explanation: String
    var id: String { marker.id }
  }
  enum LabelTarget {
    case anatomy(String)
    case feature(Feature)
  }
  struct ImmunePack: Decodable {
    let schema: Int
    let plates: [Plate]
    static let bundled: Result<Self?, Error> = Result { try read(bundle: .main) }
    static let phagocytosisOwner = "cell-macrophage"
    static let owners = ["cell-neutrophil", "cell-eosinophil", "cell-basophil", "cell-monocyte", "cell-macrophage",
      "cell-t-cell", "cell-b-cell", "cell-natural-killer-cell", "cell-plasma-cell", "cell-megakaryocyte",
      "fragment-platelet", "cell-dendritic-cell"]
    static func read(bundle: Bundle) throws -> Self? {
      guard let data = NSDataAsset(name: "HealthAtlasImmuneCells", bundle: bundle)?.data else { return nil }
      guard data.count <= 128_000 else { throw Invalid.catalogue }
      return try JSONDecoder().decode(Self.self, from: data)
    }
    func validating(in atlas: GalaxySSIHealthAtlas, bundle: Bundle) throws {
      let blood = "18-4-leukocytes-and-platelets", innate = "21-2-barrier-defenses-and-the-innate-immune-response"
      let tCells = "21-3-the-adaptive-immune-response-t-lymphocytes-and-their-functional-types"
      let bCells = "21-4-the-adaptive-immune-response-b-lymphocytes-and-antibodies"
      let chapters = [blood, blood, blood, blood, innate, tCells, bCells, innate, bCells, blood, blood, innate]
      guard schema == 1, plates.count == 12, plates.compactMap(\.owner) == Self.owners,
        Set(plates.map(\.id)).count == 12, plates.flatMap(\.annotations).count == 25,
        zip(plates, chapters).allSatisfy({ plate, chapter in
          guard let owner = plate.owner, let entry = atlas.entry(owner), [.cell, .fragment].contains(entry.kind),
            plate.id == owner, plate.entryIDs == [owner], plate.markers.isEmpty,
            plate.asset.hasPrefix("HealthAtlasImmune"),
            plate.aspectRatio == (["cell-neutrophil", Self.phagocytosisOwner].contains(owner) ? 1 : 360.0 / 280),
            UIImage(named: plate.asset, in: bundle, compatibleWith: nil) != nil,
            plate.source?.absoluteString == "https://openstax.org/books/anatomy-and-physiology-2e/pages/" + chapter,
            (2...3).contains(plate.annotations.count),
            Set(plate.annotations.map(\.id)).count == plate.annotations.count else { return false }
          let expectedLabel = ["cell-t-cell", "cell-b-cell"].contains(owner) ? "cell_receptor_scheme" :
            owner == "fragment-platelet" ? "platelet_disc" : "cell_morphology"
          return plate.viewLabel == "health_atlas_" + expectedLabel && plate.annotations.allSatisfy { feature in
            atlas.entry(feature.id) == nil && !feature.id.isEmpty && feature.title.hasPrefix("health_atlas_feature_") &&
              feature.explanation == feature.title + "_detail" &&
              GalaxySSIHealthAtlasText.get(feature.title, "en") != feature.title &&
              GalaxySSIHealthAtlasText.get(feature.explanation, "en") != feature.explanation &&
              feature.marker.x.isFinite && feature.marker.y.isFinite &&
              (0...1).contains(feature.marker.x) && (0...1).contains(feature.marker.y)
          }
        }) else { throw Invalid.catalogue }
    }
  }
}

extension GalaxySSIHealthAtlas.Plate {
  func labelTarget(_ id: String, in atlas: GalaxySSIHealthAtlas) -> GalaxySSIHealthAtlas.LabelTarget? {
    if let feature = annotations.first(where: { $0.id == id }) { return .feature(feature) }
    guard markers.contains(where: { $0.id == id }), atlas.entry(id) != nil else { return nil }
    return .anatomy(id)
  }
  private enum CodingKeys: String, CodingKey {
    case id, asset, owner, viewLabel, entryIDs, aspectRatio, markers, source, viewKey, selectorLabel, features, splitCallouts
  }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(id: try values.decode(String.self, forKey: .id), asset: try values.decode(String.self, forKey: .asset),
      owner: try values.decodeIfPresent(String.self, forKey: .owner), viewLabel: try values.decode(String.self, forKey: .viewLabel),
      entryIDs: try values.decode([String].self, forKey: .entryIDs), aspectRatio: try values.decode(Double.self, forKey: .aspectRatio),
      markers: try values.decode([GalaxySSIHealthAtlas.Marker].self, forKey: .markers), source: try values.decodeIfPresent(URL.self, forKey: .source),
      viewKey: try values.decodeIfPresent(String.self, forKey: .viewKey), selectorLabel: try values.decodeIfPresent(String.self, forKey: .selectorLabel),
      features: try values.decodeIfPresent([GalaxySSIHealthAtlas.Feature].self, forKey: .features),
      splitCallouts: try values.decodeIfPresent(Bool.self, forKey: .splitCallouts) ?? false)
    let points = markers + annotations.map(\.marker), ids = points.map(\.id)
    guard Set(ids).count == ids.count, points.count <= 64, points.allSatisfy({
      !$0.id.isEmpty && $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y)
    }) else { throw DecodingError.dataCorruptedError(forKey: .markers, in: values, debugDescription: "Invalid or duplicate atlas label anchors") }
  }
  func featureContext(language: String) -> String? {
    guard !annotations.isEmpty else { return nil }
    return String(format: GalaxySSIHealthAtlasText.get("health_atlas_feature_context", language),
      annotations.map { GalaxySSIHealthAtlasText.get($0.title, language) }.joined(separator: ", "))
  }
}
