import Foundation
import UIKit
import SwiftUI

/// Stage-end teaching counts, not division intermediates, genetic testing or patient inference.
enum GalaxySSIHealthAtlasGermline {
  enum Target: String { case cell, paternal, maternal, combined }
  struct Counts: Equatable {
    let sets: Int
    let dnaContent: Int
    let target: Target
    init?(sets: Int, dnaContent: Int, target: Target) {
      guard (1...2).contains(sets), dnaContent == sets || dnaContent == 2 * sets else { return nil }
      self.sets = sets; self.dnaContent = dnaContent; self.target = target
    }
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
    numbers(counts, text: { GalaxySSIHealthAtlasText.get("health_atlas_" + $0, language) })
  }
  static func numbers(_ counts: Counts, text t: (String) -> String) -> String {
    String(format: t("germline_counts"),
      Int64(counts.chromosomes), Int64(counts.dnaMolecules), counts.sets == 1 ? "n" : "2n", String(counts.dnaContent) + "C")
  }
  static func context(_ counts: Counts, language: String) -> String {
    context(counts, text: { GalaxySSIHealthAtlasText.get("health_atlas_" + $0, language) })
  }
  static func context(_ counts: Counts, text t: (String) -> String) -> String {
    [t("germline_title"), t("germline_" + counts.target.rawValue), numbers(counts, text: t),
      t("germline_scope"), source.absoluteString].joined(separator: "\n")
  }
}

struct GalaxySSIHealthAtlasGermlineView: View {
  let counts: GalaxySSIHealthAtlasGermline.Counts
  let language: String
  var showsDetails = true
  private func t(_ key: String) -> String { GalaxySSIHealthAtlasText.get("health_atlas_germline_" + key, language) }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(t("title")).font(.headline)
      Text(t(counts.target.rawValue)).font(.subheadline).bold().fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("atlas-germline-target")
      Text(GalaxySSIHealthAtlasGermline.numbers(counts, language: language)).font(.headline)
        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("atlas-germline-numbers")
      GeometryReader { geometry in
        let radius = min(geometry.size.width * 0.44, geometry.size.height * 0.43)
        let cx = geometry.size.width / 2, cy = geometry.size.height / 2
        ZStack {
          Circle().stroke(Color.secondary, lineWidth: 2).frame(width: radius * 2, height: radius * 2).position(x: cx, y: cy)
          ForEach(0..<(counts.sets * 2), id: \.self) { index in
            let x = cx + (CGFloat(index) - CGFloat(counts.sets * 2 - 1) / 2) * radius * 0.42
            let half = radius * 0.28
            Path { path in
              if counts.duplicated {
                path.move(to: CGPoint(x: x - half * 0.35, y: cy - half))
                path.addLine(to: CGPoint(x: x + half * 0.35, y: cy + half))
                path.move(to: CGPoint(x: x + half * 0.35, y: cy - half))
                path.addLine(to: CGPoint(x: x - half * 0.35, y: cy + half))
              } else {
                path.move(to: CGPoint(x: x, y: cy - half)); path.addLine(to: CGPoint(x: x, y: cy + half))
              }
            }.stroke(GalaxySSIHealthTheme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
          }
        }
      }.frame(height: 150).accessibilityHidden(true)
      Text(t("symbols")).font(.footnote).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
      if showsDetails {
        Text(t("timing")).font(.footnote).fixedSize(horizontal: false, vertical: true)
        Text(t("scope")).font(.footnote).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        Link(t("source"), destination: GalaxySSIHealthAtlasGermline.source).frame(minHeight: 44)
      }
    }.accessibilityIdentifier("atlas-germline")
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
