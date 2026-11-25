import SwiftUI
import UIKit

struct GalaxySSIHealthAtlasMotionSenseView: View {
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let phase: Double
  let language: String
  var body: some View {
    let motion = GalaxySSIHealthAtlasMotionSenseMotion(courseID: story.id, chapter: story.chapter(phase), fraction: story.fraction(phase))
    Canvas { context, size in
      let scale = min(size.width, size.height) / 360
      guard scale > 0 else { return }
      var local = context
      local.translateBy(x: (size.width - 360 * scale) / 2, y: (size.height - 360 * scale) / 2); local.scaleBy(x: scale, y: scale)
      let art = GalaxySSIHealthAtlasIllustratedDrawing(context: local, language: language)
      art.gradient(Path(roundedRect: CGRect(x: 0, y: 0, width: 360, height: 360), cornerRadius: 8), 0, 360, 0xE8F4F3, 0xFBF0DF)
      if motion.balance { art.balanceScene(step: motion.chapter, t: motion.fraction) }
      else { art.touchScene(step: motion.chapter, t: motion.fraction) }
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier(story.id == "VESTIBULAR_BALANCE" ? "atlas-function-vestibular-balance-art" : "atlas-function-touch-signal-art")
  }
}

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func motionArea(_ path: Path, _ top: Double, _ bottom: Double, _ from: UInt32, _ to: UInt32, _ edge: UInt32) {
    gradient(path, top, bottom, from, to); stroke(path, edge, 1.35)
  }
  func motionScientificText(_ text: String, _ x: Double, _ baseline: Double) {
    let font = UIFont.systemFont(ofSize: 14, weight: .medium), width = (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 14, weight: .medium)]).width
    context.draw(Text(verbatim: text).font(.system(size: 14, weight: .medium)).foregroundColor(Self.color(Self.teal)),
      at: CGPoint(x: x - width / 2, y: baseline - font.ascender), anchor: .topLeading)
  }
}
