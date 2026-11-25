import SwiftUI

struct GalaxySSIHealthAtlasIsletLessonView: View {
  enum Kind { case delta, pp }
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let phase: Double
  let language: String
  let kind: Kind
  var body: some View {
    Canvas { context, size in
      let scale = min(size.width, size.height) / 360
      guard scale > 0 else { return }
      var local = context
      local.translateBy(x: (size.width - 360 * scale) / 2, y: (size.height - 360 * scale) / 2); local.scaleBy(x: scale, y: scale)
      let art = GalaxySSIHealthAtlasIllustratedDrawing(context: local, language: language)
      art.gradient(Path(roundedRect: CGRect(x: 0, y: 0, width: 360, height: 360), cornerRadius: 8), 0, 360, 0xE8F4F3, 0xFBF0DF)
      let step = story.chapter(phase), t = story.fraction(phase)
      if kind == .delta { art.deltaLocalSignal(step, t) } else { art.pancreaticPPSignal(step, t) }
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier(kind == .delta ? "atlas-function-pancreatic-delta-art" : "atlas-function-pancreatic-pp-art")
  }
}

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func endocrineDiamond(_ x: Double, _ y: Double, _ r: Double, _ tint: UInt32) {
    var p = Path(); p.move(to: CGPoint(x: x, y: y - r)); p.addLine(to: CGPoint(x: x + r, y: y))
    p.addLine(to: CGPoint(x: x, y: y + r)); p.addLine(to: CGPoint(x: x - r, y: y)); p.closeSubpath(); fill(p, tint)
  }
  func endocrineVessel(_ path: Path, _ width: Double) { stroke(path, 0xA26070, width + 3); stroke(path, 0xEAB4B6, width) }
  func endocrineArc(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double, _ start: Double, _ sweep: Double, _ tint: UInt32, _ width: Double) {
    guard sweep.isFinite, sweep != 0, rx > 0, ry > 0 else { return }
    var path = Path(); path.addArc(center: .zero, radius: 1, startAngle: .degrees(start), endAngle: .degrees(start + sweep), clockwise: false)
    stroke(path.applying(CGAffineTransform(a: rx, b: 0, c: 0, d: ry, tx: x, ty: y)), tint, width)
  }
}
