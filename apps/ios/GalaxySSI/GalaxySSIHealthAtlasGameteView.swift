import SwiftUI

struct GalaxySSIHealthAtlasGameteView: View {
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let phase: Double
  let language: String
  var body: some View {
    let motion = GalaxySSIHealthAtlasGameteMotion(courseID: story.id, chapter: story.chapter(phase), fraction: story.fraction(phase))
    Canvas { context, size in
      let scale = min(size.width, size.height) / 360
      guard scale > 0 else { return }
      var local = context
      local.translateBy(x: (size.width - 360 * scale) / 2, y: (size.height - 360 * scale) / 2); local.scaleBy(x: scale, y: scale)
      let art = GalaxySSIHealthAtlasIllustratedDrawing(context: local, language: language)
      art.gradient(Path(roundedRect: CGRect(x: 0, y: 0, width: 360, height: 360), cornerRadius: 8), 0, 360, 0xE8F4F3, 0xFBF0DF)
      if motion.sperm { art.spermScene(step: motion.chapter, t: motion.fraction) }
      else { art.ovumScene(step: motion.chapter, t: motion.fraction) }
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier(story.id == "SPERM_TRANSPORT" ? "atlas-function-sperm-transport-art" : "atlas-function-ovum-transport-art")
  }
}

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func gameteFlow(_ route: GalaxySSIHealthAtlasGameteMotion.Route, _ t: Double, _ color: UInt32, _ count: Int) {
    for i in 0..<count { at(route, t * 1.19 - Double(i) * 0.062) { disc($0, $1, i == 0 ? 4.2 : 3.2, color, border: Self.cream) } }
  }
  func gameteSperm(_ x: Double, _ y: Double, rotation: Double, size: Double, t: Double) {
    var local = context; local.translateBy(x: x, y: y); local.rotate(by: .degrees(rotation)); local.scaleBy(x: size, y: size)
    let drawing = copy(local), curl = 7 * wave(t)
    var tail = Path(); tail.move(to: CGPoint(x: -4, y: 0))
    tail.addCurve(to: CGPoint(x: -33, y: curl * 0.66), control1: CGPoint(x: -14, y: curl), control2: CGPoint(x: -20, y: -curl))
    drawing.stroke(tail, Self.teal, 1.55)
    drawing.oval(-6, -4, 7, 4, fill: 0x74AE9D, border: Self.teal); drawing.disc(2, -1, 1.1, Self.cream)
  }
  func gameteOocyte(_ x: Double, _ y: Double, _ r: Double) {
    let halo = r * 1.43
    for i in 0...11 {
      let a = Double(i) * .pi / 6
      disc(x + halo * cos(a), y + halo * sin(a), r * 0.22, Self.sand, border: Self.sienna)
    }
    oval(x - r, y - r, x + r, y + r, top: 130, bottom: 200, from: 0xFFF4D1, to: 0xECC08D, border: Self.violet)
    disc(x + r * 0.60, y - r * 0.54, r * 0.12, Self.violet); disc(x - r * 0.27, y - r * 0.34, r * 0.13, Self.cream)
  }
}
