import SwiftUI

struct GalaxySSIHealthAtlasMammaryView: View {
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let phase: Double
  let language: String
  var body: some View {
    Canvas { context, size in
      let scale = min(size.width, size.height) / 360
      guard scale > 0 else { return }
      var local = context
      local.translateBy(x: (size.width - 360 * scale) / 2, y: (size.height - 360 * scale) / 2); local.scaleBy(x: scale, y: scale)
      let art = GalaxySSIHealthAtlasIllustratedDrawing(context: local, language: language)
      art.gradient(Path(roundedRect: CGRect(x: 0, y: 0, width: 360, height: 360), cornerRadius: 8), 0, 360, 0xE8F4F3, 0xFBF0DF)
      let step = story.chapter(phase), t = story.fraction(phase)
      art.mammaryScene(GalaxySSIHealthAtlasMammaryMotion(step: step, fraction: t), step: step, t: t)
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-mammary-milk-flow-art")
  }
}

enum GalaxySSIHealthAtlasMammaryInk {
  static let rim: UInt32 = 0x9D626D, seam: UInt32 = 0xB67581, nucleus: UInt32 = 0xBA8DA7, basal: UInt32 = 0x609C90
  static let guide: UInt32 = 0x546F73, milk: UInt32 = 0xFFF5D6, milkEdge: UInt32 = 0xA67847
  static func outline(_ radius: Double) -> Path {
    let lower = GalaxySSIHealthAtlasMammaryMotion.point(radius, 40), upper = GalaxySSIHealthAtlasMammaryMotion.point(radius, 320)
    var path = Path(); path.move(to: CGPoint(x: 333, y: 201)); path.addLine(to: CGPoint(x: 275, y: 201))
    path.addCurve(to: CGPoint(x: lower.x, y: lower.y), control1: CGPoint(x: 246, y: 201), control2: CGPoint(x: lower.x + 14, y: lower.y - 17))
    path.addArc(center: CGPoint(x: 138, y: 177), radius: radius, startAngle: .degrees(40), endAngle: .degrees(320), clockwise: false)
    path.addCurve(to: CGPoint(x: 275, y: 153), control1: CGPoint(x: upper.x + 14, y: upper.y + 17), control2: CGPoint(x: 246, y: 153))
    path.addLine(to: CGPoint(x: 333, y: 153)); return path
  }
}
