import SwiftUI

struct GalaxySSIHealthAtlasMelaninView: View {
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
      art.melaninScene(step: story.chapter(phase), t: story.fraction(phase))
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-melanin-transfer-art")
  }
}

enum GalaxySSIHealthAtlasMelaninShapes {
  static let membrane: UInt32 = 0x548E83, branchFill: UInt32 = 0xBDE4D2, pigment: UInt32 = 0x774723, leader: UInt32 = 0x635C69
  static let branchPaths = GalaxySSIHealthAtlasMelaninMotion.branches.map { GalaxySSIHealthAtlasSectionLessonView.path($0, width: 360, height: 360) }
  static let recipient = Path { p in
    p.move(to: CGPoint(x: 240, y: 142))
    p.addCurve(to: CGPoint(x: 280, y: 172), control1: CGPoint(x: 263, y: 141), control2: CGPoint(x: 279, y: 153))
    p.addCurve(to: CGPoint(x: 263, y: 215), control1: CGPoint(x: 282, y: 188), control2: CGPoint(x: 276, y: 207))
    p.addCurve(to: CGPoint(x: 211, y: 209), control1: CGPoint(x: 247, y: 224), control2: CGPoint(x: 225, y: 219))
    p.addCurve(to: CGPoint(x: 204, y: 176), control1: CGPoint(x: 202, y: 202), control2: CGPoint(x: 202, y: 189))
    p.addCurve(to: CGPoint(x: 240, y: 142), control1: CGPoint(x: 203, y: 157), control2: CGPoint(x: 219, y: 143)); p.closeSubpath()
  }
  static let donor = Path { p in
    p.move(to: CGPoint(x: 94, y: 265))
    p.addCurve(to: CGPoint(x: 132, y: 228), control1: CGPoint(x: 92, y: 248), control2: CGPoint(x: 113, y: 228))
    p.addCurve(to: CGPoint(x: 169, y: 253), control1: CGPoint(x: 151, y: 224), control2: CGPoint(x: 166, y: 238))
    p.addCurve(to: CGPoint(x: 134, y: 281), control1: CGPoint(x: 176, y: 272), control2: CGPoint(x: 154, y: 281))
    p.addCurve(to: CGPoint(x: 94, y: 265), control1: CGPoint(x: 115, y: 282), control2: CGPoint(x: 97, y: 279)); p.closeSubpath()
  }
  static func wafer(_ cell: GalaxySSIHealthAtlasMelaninMotion.Cell) -> Path {
    let x = cell.x, y = cell.y, rx = cell.rx, ry = cell.ry
    return Path { p in
      p.move(to: CGPoint(x: x - rx, y: y))
      p.addCurve(to: CGPoint(x: x + rx * 0.15, y: y - ry), control1: CGPoint(x: x - rx, y: y - ry * 0.7), control2: CGPoint(x: x - rx * 0.6, y: y - ry))
      p.addCurve(to: CGPoint(x: x + rx, y: y + ry * 0.12), control1: CGPoint(x: x + rx * 0.7, y: y - ry), control2: CGPoint(x: x + rx, y: y - ry * 0.5))
      p.addCurve(to: CGPoint(x: x - rx * 0.20, y: y + ry), control1: CGPoint(x: x + rx, y: y + ry * 0.85), control2: CGPoint(x: x + rx * 0.52, y: y + ry))
      p.addCurve(to: CGPoint(x: x - rx, y: y), control1: CGPoint(x: x - rx * 0.84, y: y + ry), control2: CGPoint(x: x - rx, y: y + ry * 0.5)); p.closeSubpath()
    }
  }
}
