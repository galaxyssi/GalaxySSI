import SwiftUI

struct GalaxySSIHealthAtlasPanethBarrierView: View {
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let phase: Double
  let language: String
  private static let cargo: UInt32 = 0x9C4938
  private static let xs = [-3.5, 0.2, 3.9, -0.7], ys = [5.5, 4.1, 6.2, 9.0]
  var body: some View {
    Canvas { context, size in
      let scale = min(size.width, size.height) / 360
      guard scale > 0 else { return }
      var local = context
      local.translateBy(x: (size.width - 360 * scale) / 2, y: (size.height - 360 * scale) / 2); local.scaleBy(x: scale, y: scale)
      let wall = GalaxySSIHealthAtlasCryptWallDrawing(context: local, language: language)
      wall.art.gradient(Path(roundedRect: CGRect(x: 0, y: 0, width: 360, height: 360), cornerRadius: 8), 0, 360, 0xE8F4F3, 0xFBF0DF)
      let step = story.chapter(phase), t = story.fraction(phase)
      guard GalaxySSIHealthAtlasCryptWallDrawing.centers.count == 29 else { return }
      wall.wall(feature: 13); wall.art.label("crypt_lumen", 166, 97, 122)
      let base = GalaxySSIHealthAtlasCryptWallDrawing.centers[13], cell = wall.atPose(base)
      cell.panethBody(active: true)
      switch step {
      case 0:
        stored(cell, towardApex: 0)
        cell.ring(0, 9, 14 + 5 * t, opacity: 0.72 * (1 - t), width: 1.7, tint: Self.cargo)
      case 1: stored(cell, towardApex: GalaxySSIHealthAtlasCryptWallDrawing.ease(t, 0.06, 0.96))
      case 2: release(cell, t)
      default: spread(cell, t)
      }
      wall.leader("paneth_barrier_cell", base.at(-5, 14), 111, 319, 66, 89, Self.cargo)
      if step == 1 { wall.leader("paneth_barrier_apical", base.at(5, 2), 124, 251, 166, 98, Self.cargo) }
      else if step >= 2 { wall.art.label("paneth_barrier_peptides", 167, 154, 119) }
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-paneth-crypt-barrier-art")
  }
  private func stored(_ cell: GalaxySSIHealthAtlasCryptWallDrawing, towardApex: Double) {
    for i in 0..<4 {
      let x = Self.xs[i], y = Self.ys[i] + (2.2 + Double(i % 2) * 2.4 - Self.ys[i]) * towardApex
      cell.art.disc(x, y, 2.25, Self.cargo); cell.art.disc(x - 0.35, y - 0.45, 0.9, 0xFBC978)
    }
  }
  private func release(_ cell: GalaxySSIHealthAtlasCryptWallDrawing, _ t: Double) {
    cell.art.disc(-0.9, 8.8, 1.7, Self.cargo)
    for i in 0...2 {
      let p = GalaxySSIHealthAtlasCryptWallDrawing.ease(t, Double(i) * 0.14, 0.76 + Double(i) * 0.095), mouth = Self.xs[i]
      if p < 0.28 {
        let start = 2.2 + Double(i % 2) * 2.4
        cell.art.disc(mouth, start + (0.5 - start) * p / 0.28, 2.2, Self.cargo)
      } else {
        let released = (p - 0.28) / 0.72
        cell.ring(mouth, 0.5, 2.5 + released, opacity: 1 - released, width: 1.25, tint: Self.cargo)
        peptide(cell, mouth + (Double(i) - 1) * 9 * released, -2 - (20 + Double(i) * 8) * released, 1)
        peptide(cell, mouth + (Double(i) - 0.8) * 12 * released, -2 - (13 + Double(i) * 7) * released, 0.83)
      }
    }
  }
  private func spread(_ cell: GalaxySSIHealthAtlasCryptWallDrawing, _ t: Double) {
    cell.art.disc(-0.9, 8.8, 1.7, Self.cargo)
    let p = GalaxySSIHealthAtlasCryptWallDrawing.ease(t)
    for i in 0...10 {
      let offset = Double(i % 5 - 2), x = offset * (4 + 12 * p) + Double(i % 2) * 7
      let y = -19 - Double(i) * 3.1 - (18 + Double(i % 3) * 8) * p
      peptide(cell, x, y, (0.95 - 0.3 * p) * (i < 6 ? 1 : GalaxySSIHealthAtlasCryptWallDrawing.ease(t, 0.03, 0.4)))
    }
  }
  private func peptide(_ cell: GalaxySSIHealthAtlasCryptWallDrawing, _ x: Double, _ y: Double, _ opacity: Double) {
    var local = cell.context; local.opacity = Double(Int(255 * min(1, max(0, opacity)))) / 255
    GalaxySSIHealthAtlasIllustratedDrawing(context: local, language: language).line(x - 1.5, y + 0.8, x + 1.5, y - 0.8, Self.cargo, 2.65)
  }
}
