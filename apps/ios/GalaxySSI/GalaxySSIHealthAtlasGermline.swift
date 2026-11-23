import Foundation
import UIKit

/// Stage-end teaching counts, not division intermediates, genetic testing or patient inference.
enum GalaxySSIHealthAtlasGermline {
  enum Target: String { case cell, paternal, maternal, combined }
  struct Counts: Equatable {
    let sets: Int
    let dnaContent: Int
    let target: Target
    var chromosomes: Int { 23 * sets }
    var dnaMolecules: Int { 23 * dnaContent }
    var duplicated: Bool { dnaContent == 2 * sets }
  }
  static let source = URL(string: "https://openstax.org/books/biology-2e/pages/11-1-the-process-of-meiosis")!
  static let supported = ["cell-spermatogonium", "cell-spermatocyte", "cell-spermatozoon", "cell-oocyte-or-ovum"]
  static func counts(_ id: String, stage: Int) -> Counts? {
    guard (0...3).contains(stage) else { return nil }
    switch id {
    case "cell-spermatogonium": return Counts(sets: 2, dnaContent: stage < 2 ? 2 : 4, target: .cell)
    case "cell-spermatocyte":
      if stage == 0 { return Counts(sets: 2, dnaContent: 4, target: .cell) }
      return Counts(sets: 1, dnaContent: stage == 1 ? 2 : 1, target: .cell)
    case "cell-spermatozoon": return Counts(sets: 1, dnaContent: 1, target: .paternal)
    case "cell-oocyte-or-ovum":
      if stage < 2 { return Counts(sets: 1, dnaContent: 2, target: .maternal) }
      if stage == 2 { return Counts(sets: 1, dnaContent: 1, target: .maternal) }
      return Counts(sets: 2, dnaContent: 2, target: .combined)
    default: return nil
    }
  }
  static func numbers(_ counts: Counts, language: String) -> String {
    String(format: GalaxySSIHealthAtlasText.get("health_atlas_germline_counts", language),
      Int64(counts.chromosomes), Int64(counts.dnaMolecules), counts.sets == 1 ? "n" : "2n", String(counts.dnaContent) + "C")
  }
  static func context(_ counts: Counts, language: String) -> String {
    ["health_atlas_germline_title", "health_atlas_germline_" + counts.target.rawValue]
      .map { GalaxySSIHealthAtlasText.get($0, language) }.joined(separator: "\n") + "\n" +
      numbers(counts, language: language) + "\n" +
      GalaxySSIHealthAtlasText.get("health_atlas_germline_scope", language) + "\n" + source.absoluteString
  }
}

extension GalaxySSIHealthAtlas {
  struct ReproductivePack: Decodable {
    let schema: Int
    let entries: [Entry]
    let mechanisms: [Mechanism]
    static func read(bundle: Bundle) throws -> Self? {
      guard let data = NSDataAsset(name: "HealthAtlasReproductiveCells", bundle: bundle)?.data else { return nil }
      guard data.count <= 256_000 else { throw Invalid.catalogue }
      return try JSONDecoder().decode(Self.self, from: data)
    }
    func applying(to base: GalaxySSIHealthAtlas) throws -> GalaxySSIHealthAtlas {
      let revised = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
      let models = Dictionary(mechanisms.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
      guard schema == 1, entries.count == 12, revised.count == entries.count,
        mechanisms.count == 15, models.count == mechanisms.count,
        entries.allSatisfy({ entry in
          base.entry(entry.id).map { $0.kind == .cell && entry.kind == .cell && $0.systems == entry.systems } == true
        }), mechanisms.allSatisfy({ $0.kind == "cell" || ["male", "female", "sperm"].contains($0.id) }) else { throw Invalid.catalogue }
      let existing = Set(base.mechanisms.map(\.id))
      return try GalaxySSIHealthAtlas.validated(.init(schema: base.schema,
        entries: base.entries.map { revised[$0.id] ?? $0 },
        mechanisms: base.mechanisms.map { models[$0.id] ?? $0 } + mechanisms.filter { !existing.contains($0.id) }))
    }
  }
}
