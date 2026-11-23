import SwiftUI
import UIKit

enum GalaxySSIHealthAtlasOcularInk {
  static let transmit: UInt32 = 0x598F86, suppress: UInt32 = 0x86598E, retinol: UInt32 = 0xAA6B31, cisRetinal: UInt32 = 0x307C6E
  static let rays: [UInt32] = [0x659F9B, 0xCA8D78, 0x8D8EB3, 0x6F9FB8]
}

struct GalaxySSIHealthAtlasOcularView: View {
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let phase: Double
  let language: String
  var body: some View {
    let motion = GalaxySSIHealthAtlasOcularMotion(courseID: story.id, chapter: story.chapter(phase), fraction: story.fraction(phase))
    Canvas { context, size in
      let scale = min(size.width, size.height) / 360
      guard scale > 0 else { return }
      var local = context
      local.translateBy(x: (size.width - 360 * scale) / 2, y: (size.height - 360 * scale) / 2); local.scaleBy(x: scale, y: scale)
      let art = GalaxySSIHealthAtlasIllustratedDrawing(context: local, language: language)
      art.gradient(Path(roundedRect: CGRect(x: 0, y: 0, width: 360, height: 360), cornerRadius: 8), 0, 360, 0xE8F4F3, 0xFBF0DF)
      switch motion.course {
      case .visualCycle: art.pigmentScene(step: motion.chapter, t: motion.fraction)
      case .dimRelay: art.rodRelayScene(step: motion.chapter, t: motion.fraction)
      case .cornea: art.corneaScene(step: motion.chapter, t: motion.fraction)
      }
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier(story.id == "RPE_VISUAL_CYCLE" ? "atlas-function-rpe-visual-cycle-art" :
        story.id == "DIM_LIGHT_RELAY" ? "atlas-function-dim-light-relay-art" : "atlas-function-corneal-surface-renewal-art")
  }
}

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func ocularRod(_ x: Double, _ top: Double, _ bottom: Double, _ halfWidth: Double) {
    oval(x - halfWidth, top, x + halfWidth, bottom, top: 70, bottom: 192, from: 0xD6E8EB, to: 0x7296B1, border: Self.blue)
    for i in 1...6 {
      let y = top + (bottom - top) * Double(i) / 7, width = i == 1 || i == 6 ? 0.64 : 0.84
      line(x - halfWidth * width, y, x + halfWidth * width, y, 0x577C98, 1.3)
    }
  }
  func ocularMolecule(_ x: Double, _ y: Double, _ size: Double, _ bend: Double, _ color: UInt32) {
    let a = x - 12 * size, b = x + 12 * size, dy = bend * 10 * size
    line(a, y + dy, x, y, color, 3 * size); line(x, y, b, y + dy, color, 3 * size)
    disc(a, y + dy, 3.4 * size, color, border: Self.cream); disc(b, y + dy, 3.4 * size, color, border: Self.cream)
  }
  func ocularPulse(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ t: Double, _ index: Int, _ color: UInt32) {
    let f = GalaxySSIHealthAtlasOcularMotion.relayFraction(t, index: index)
    disc(x1 + (x2 - x1) * f, y1 + (y2 - y1) * f, 4.5, color, border: Self.cream)
  }
  func ocularScientificText(_ text: String, _ x: Double, _ baseline: Double) {
    let font = UIFont.systemFont(ofSize: 14, weight: .medium), width = (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 14, weight: .medium)]).width
    context.draw(Text(verbatim: text).font(.system(size: 14, weight: .medium)).foregroundColor(Self.color(Self.violet)),
      at: CGPoint(x: x - width / 2, y: baseline - font.ascender), anchor: .topLeading)
  }
}
