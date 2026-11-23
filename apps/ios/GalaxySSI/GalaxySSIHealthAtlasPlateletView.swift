import SwiftUI

struct GalaxySSIHealthAtlasPlateletView: View {
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
      art.plateletScene(step: story.chapter(phase), t: story.fraction(phase))
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-platelet-hemostasis-art")
  }
}

enum GalaxySSIHealthAtlasPlateletShapes {
  static let lining: UInt32 = 0xA7697B, wall: UInt32 = 0xBE8B93, platelet: UInt32 = 0x946024
  static let plateletFill: UInt32 = 0xFFD694, fiber: UInt32 = 0x307E79, signal: UInt32 = 0x87649D
  static let topWall = Path(roundedRect: CGRect(x: 24, y: 80, width: 312, height: 33), cornerRadius: 14)
  static let lowerWall = Path { p in
    p.move(to: CGPoint(x: 24, y: 234))
    p.addQuadCurve(to: CGPoint(x: 40, y: 221), control: CGPoint(x: 24, y: 221))
    p.addLine(to: CGPoint(x: 148, y: 221))
    p.addQuadCurve(to: CGPoint(x: 162, y: 230), control: CGPoint(x: 157, y: 221))
    p.addLine(to: CGPoint(x: 170, y: 243))
    p.addQuadCurve(to: CGPoint(x: 167, y: 256), control: CGPoint(x: 172, y: 248))
    p.addQuadCurve(to: CGPoint(x: 150, y: 270), control: CGPoint(x: 160, y: 270))
    p.addLine(to: CGPoint(x: 40, y: 270))
    p.addQuadCurve(to: CGPoint(x: 24, y: 255), control: CGPoint(x: 24, y: 270)); p.closeSubpath()
  }
  static let exposedEdge = Path { p in
    p.move(to: CGPoint(x: 151, y: 224))
    p.addQuadCurve(to: CGPoint(x: 161, y: 234), control: CGPoint(x: 157, y: 226))
    p.addLine(to: CGPoint(x: 167, y: 244))
    p.addQuadCurve(to: CGPoint(x: 163, y: 258), control: CGPoint(x: 170, y: 249))
  }
}
