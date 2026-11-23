import Foundation
import UIKit

extension GalaxySSIHealthAtlas {
  struct ExtendedCellPack: Decodable {
    let schema: Int
    let entries: [Entry]
    let mechanisms: [Mechanism]
    static func read(bundle: Bundle) throws -> Self? {
      guard let data = NSDataAsset(name: "HealthAtlasExtendedCells", bundle: bundle)?.data else { return nil }
      guard data.count <= 512_000 else { throw Invalid.catalogue }
      return try JSONDecoder().decode(Self.self, from: data)
    }
    func applying(to base: GalaxySSIHealthAtlas) throws -> GalaxySSIHealthAtlas {
      let revised = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
      let models = Dictionary(mechanisms.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
      guard schema == 1, entries.count == 52, revised.count == entries.count,
        models.count == mechanisms.count, Set(models.keys) == Set(revised.keys),
        entries.allSatisfy({ entry in
          guard let original = base.entry(entry.id), [.cell, .fragment].contains(entry.kind),
            entry.kind == original.kind, entry.systems == original.systems,
            entry.mechanism == entry.id, let model = models[entry.id] else { return false }
          return model.kind == entry.kind.rawValue
        }) else { throw Invalid.catalogue }
      let existing = Set(base.mechanisms.map(\.id))
      return try GalaxySSIHealthAtlas.validated(.init(schema: base.schema,
        entries: base.entries.map { revised[$0.id] ?? $0 },
        mechanisms: base.mechanisms.map { models[$0.id] ?? $0 } + mechanisms.filter { !existing.contains($0.id) }),
        requireCompleteMicroscopic: true)
    }
  }
}
