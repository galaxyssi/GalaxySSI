import SwiftUI

struct GalaxySSIHealthAtlasSebaceousView: View {
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let phase: Double
  let language: String
  var body: some View {
    Canvas { context, size in
      let scale = min(size.width, size.height) / 360
      guard scale > 0 else { return }
      var local = context
      local.translateBy(x: (size.width - 360 * scale) / 2, y: (size.height - 360 * scale) / 2)
      local.scaleBy(x: scale, y: scale)
      let art = GalaxySSIHealthAtlasIllustratedDrawing(context: local, language: language)
      art.gradient(Path(roundedRect: CGRect(x: 0, y: 0, width: 360, height: 360), cornerRadius: 8), 0, 360, 0xE8F4F3, 0xFBF0DF)
      let step = story.chapter(phase), fraction = story.fraction(phase)
      let t = fraction.isFinite ? min(1, max(0, fraction)) : 0
      art.label("sebaceous_skin_view", 83, 26, 145)
      art.label("sebaceous_acinar_view", 259, 26, 168)
      art.sebaceousSkin(step, t)
      art.sebaceousLobule(step, t)
      art.sebaceousLeader("sebaceous_young", 267, 57, 150, 290, 96)
      art.sebaceousLeader("sebaceous_mature", 282, 277, 140, 292, 202)
      art.sebaceousLeader("sebaceous_duct", 191, 313, 103, 193, 185)
      art.disc(213, 337, 3.3, 0xD69742, border: 0x9B651E)
      art.label("sebaceous_lipids", 266, 341, 92)
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-sebaceous-art")
  }
}
extension GalaxySSIHealthAtlasIllustratedDrawing {
  func sebaceousLeader(_ key: String, _ x: Double, _ baseline: Double, _ width: Double, _ targetX: Double, _ targetY: Double) {
    let anchorY = baseline + (targetY > baseline ? 6 : -16)
    line(x, anchorY, targetX, targetY, 0x668181, 1)
    disc(targetX, targetY, 1.7, 0x668181, border: Self.cream)
    label(key, x, baseline, width)
  }
  func sebaceousFill(_ shape: Path, _ top: Double, _ bottom: Double, _ from: UInt32, _ to: UInt32, _ border: UInt32) {
    gradient(shape, top, bottom, from, to); stroke(shape, border, 1.4)
  }
}
