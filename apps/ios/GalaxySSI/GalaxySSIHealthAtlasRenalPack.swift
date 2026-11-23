import Foundation
import UIKit

extension GalaxySSIHealthAtlas {
  struct RenalPack: Decodable {
    let schema: Int
    let entries: [Entry]
    let mechanisms: [Mechanism]
    let insertAfter: [String: String]
    let plate: Plate
    static let bundled: Result<Self?, Error> = Result { try read(bundle: .main) }
    static func read(bundle: Bundle) throws -> Self? {
      guard let data = NSDataAsset(name: "HealthAtlasRenal", bundle: bundle)?.data else { return nil }
      guard data.count <= 256_000 else { throw Invalid.catalogue }
      return try JSONDecoder().decode(Self.self, from: data)
    }
    func applying(to base: GalaxySSIHealthAtlas, bundle: Bundle) throws -> GalaxySSIHealthAtlas {
      let replacements = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
      let additions = Set(entries.filter { base.entry($0.id) == nil }.map(\.id))
      let models = Set(mechanisms.map(\.id))
      guard schema == 1, !entries.isEmpty, entries.count <= 64, replacements.count == entries.count,
        models.count == mechanisms.count, mechanisms.count <= 32,
        models.isDisjoint(with: Set(base.mechanisms.map(\.id))),
        mechanisms.allSatisfy({ $0.kind == "cell" }),
        Set(insertAfter.keys) == additions, insertAfter.values.allSatisfy({ base.entry($0) != nil }),
        entries.allSatisfy({ entry in
          if let original = base.entry(entry.id) { return original.kind == entry.kind && original.systems == entry.systems }
          return entry.kind == .organ && entry.systems == ["urinary"]
        }) else { throw Invalid.catalogue }
      let revised = base.entries.flatMap { entry in
        [replacements[entry.id] ?? entry] + entries.filter { insertAfter[$0.id] == entry.id }
      }
      let result = try GalaxySSIHealthAtlas.validated(.init(schema: base.schema, entries: revised, mechanisms: base.mechanisms + mechanisms))
      guard plate.id == "nephron", plate.owner == "nephron", plate.source?.scheme == "https",
        plate.source?.host == "openstax.org", plate.source?.user == nil, plate.source?.password == nil,
        plate.asset == "HealthAtlasNephron", UIImage(named: plate.asset, in: bundle, compatibleWith: nil) != nil,
        plate.aspectRatio.isFinite, (0.1...3).contains(plate.aspectRatio),
        Set(plate.entryIDs).count == plate.entryIDs.count, !plate.entryIDs.isEmpty,
        plate.entryIDs.allSatisfy({ result.entry($0)?.kind == .organ }),
        Set(plate.markers.map(\.id)).count == plate.markers.count,
        plate.markers.allSatisfy({ result.entry($0.id) != nil && $0.x.isFinite && $0.y.isFinite &&
          (0...1).contains($0.x) && (0...1).contains($0.y) }) else { throw Invalid.catalogue }
      return result
    }
  }
}
