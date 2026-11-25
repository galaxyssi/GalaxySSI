import SwiftUI

struct GalaxySSIHealthAtlasAbsorptionView: View {
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
      art.absorptionScene(step: story.chapter(phase), t: story.fraction(phase))
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-intestinal-absorption-art")
  }
}

enum GalaxySSIHealthAtlasAbsorptionShapes {
  static let leader: UInt32 = 0x637E81, brush: UInt32 = 0x8A6052, lipid: UInt32 = 0xA16125
  static let surface = GalaxySSIHealthAtlasSectionLessonView.path(GalaxySSIHealthAtlasAbsorptionMotion.outline, width: 360, height: 360)
  static let villus: Path = { var path = surface; path.closeSubpath(); return path }()
  struct Features { var microvilli = Path(); var cellBoundaries = Path(); var nuclei = Path() }
  static let features: Features = {
    var paths = Features()
    // Cache source normal-based microgeometry once, not once per animation frame.
    for index in 8...128 {
      guard let sample = GalaxySSIHealthAtlasFunctionPath.sample(GalaxySSIHealthAtlasAbsorptionMotion.outline,
        position: Double(index) / 136, width: 360, height: 360) else { continue }
      let x = sample.point.x, y = sample.point.y, nx = -sample.direction.dy, ny = sample.direction.dx
      paths.microvilli.move(to: CGPoint(x: x, y: y)); paths.microvilli.addLine(to: CGPoint(x: x - 3.8 * nx, y: y - 3.8 * ny))
      if index % 4 == 0 {
        paths.cellBoundaries.move(to: CGPoint(x: x, y: y)); paths.cellBoundaries.addLine(to: CGPoint(x: x + 14 * nx, y: y + 14 * ny))
      } else if index % 4 == 2 {
        let cx = x + 9 * nx, cy = y + 9 * ny
        paths.nuclei.addEllipse(in: CGRect(x: cx - 2.2, y: cy - 3, width: 4.4, height: 6))
      }
    }
    return paths
  }()
  static let insetBrush = Path { p in
    for x in stride(from: 222, through: 342, by: 4) { p.move(to: CGPoint(x: Double(x), y: 107)); p.addLine(to: CGPoint(x: Double(x), y: x % 8 == 2 ? 97 : 99)) }
  }
  static let enterocyte = Path { p in
    p.move(to: CGPoint(x: 239, y: 108)); p.addLine(to: CGPoint(x: 323, y: 108))
    p.addCurve(to: CGPoint(x: 315, y: 218), control1: CGPoint(x: 320, y: 150), control2: CGPoint(x: 323, y: 198))
    p.addQuadCurve(to: CGPoint(x: 247, y: 218), control: CGPoint(x: 282, y: 232))
    p.addCurve(to: CGPoint(x: 239, y: 108), control1: CGPoint(x: 239, y: 198), control2: CGPoint(x: 242, y: 150)); p.closeSubpath()
  }
  static let capillaries = Path { p in
    p.move(to: CGPoint(x: 69, y: 297))
    p.addCurve(to: CGPoint(x: 73, y: 165), control1: CGPoint(x: 73, y: 241), control2: CGPoint(x: 75, y: 197))
    p.addCurve(to: CGPoint(x: 95, y: 104), control1: CGPoint(x: 71, y: 128), control2: CGPoint(x: 78, y: 106))
    p.addCurve(to: CGPoint(x: 111, y: 154), control1: CGPoint(x: 112, y: 102), control2: CGPoint(x: 115, y: 123))
    p.addCurve(to: CGPoint(x: 100, y: 297), control1: CGPoint(x: 105, y: 202), control2: CGPoint(x: 105, y: 249))
    p.move(to: CGPoint(x: 74, y: 203))
    p.addCurve(to: CGPoint(x: 107, y: 186), control1: CGPoint(x: 85, y: 204), control2: CGPoint(x: 91, y: 186))
    p.move(to: CGPoint(x: 74, y: 245))
    p.addCurve(to: CGPoint(x: 104, y: 231), control1: CGPoint(x: 87, y: 247), control2: CGPoint(x: 91, y: 229))
  }
  static let lacteal = Path { p in
    p.move(to: CGPoint(x: 133, y: 130))
    p.addCurve(to: CGPoint(x: 126, y: 218), control1: CGPoint(x: 131, y: 173), control2: CGPoint(x: 126, y: 194))
    p.addCurve(to: CGPoint(x: 136, y: 297), control1: CGPoint(x: 126, y: 249), control2: CGPoint(x: 135, y: 270))
  }
}
