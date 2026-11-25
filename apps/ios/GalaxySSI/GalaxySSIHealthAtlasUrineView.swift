import SwiftUI

struct GalaxySSIHealthAtlasUrineView: View {
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
      switch step {
      case 0: art.urineOverview(t)
      case 1: art.urinePeristalsis(t)
      case 2: art.urineJunction(t)
      default: art.urineReservoir(t, emptying: step == 4)
      }
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-urine-route-art")
  }
}

enum GalaxySSIHealthAtlasUrineShapes {
  static let kidney = Path { p in
    p.move(to: CGPoint(x: 139, y: 81))
    p.addCurve(to: CGPoint(x: 77, y: 73), control1: CGPoint(x: 130, y: 46), control2: CGPoint(x: 91, y: 44))
    p.addCurve(to: CGPoint(x: 84, y: 160), control1: CGPoint(x: 61, y: 102), control2: CGPoint(x: 61, y: 144))
    p.addCurve(to: CGPoint(x: 139, y: 129), control1: CGPoint(x: 106, y: 176), control2: CGPoint(x: 141, y: 151))
    p.addCurve(to: CGPoint(x: 126, y: 108), control1: CGPoint(x: 138, y: 118), control2: CGPoint(x: 121, y: 122))
    p.addCurve(to: CGPoint(x: 139, y: 81), control1: CGPoint(x: 129, y: 99), control2: CGPoint(x: 144, y: 101)); p.closeSubpath()
  }
  static let medulla = Path { p in
    p.move(to: CGPoint(x: 121, y: 80))
    p.addCurve(to: CGPoint(x: 78, y: 113), control1: CGPoint(x: 103, y: 56), control2: CGPoint(x: 78, y: 80))
    p.addCurve(to: CGPoint(x: 119, y: 138), control1: CGPoint(x: 71, y: 152), control2: CGPoint(x: 99, y: 160))
    p.addCurve(to: CGPoint(x: 115, y: 108), control1: CGPoint(x: 130, y: 128), control2: CGPoint(x: 109, y: 125))
    p.addCurve(to: CGPoint(x: 121, y: 80), control1: CGPoint(x: 119, y: 98), control2: CGPoint(x: 132, y: 93)); p.closeSubpath()
  }
  static let calyces = Path { p in
    p.move(to: CGPoint(x: 101, y: 90)); p.addQuadCurve(to: CGPoint(x: 128, y: 110), control: CGPoint(x: 111, y: 103))
    p.move(to: CGPoint(x: 95, y: 113)); p.addQuadCurve(to: CGPoint(x: 128, y: 110), control: CGPoint(x: 110, y: 109))
    p.move(to: CGPoint(x: 101, y: 137)); p.addQuadCurve(to: CGPoint(x: 128, y: 110), control: CGPoint(x: 114, y: 132))
  }
  static let junctionWall = Path { p in
    p.move(to: CGPoint(x: 20, y: 104))
    p.addCurve(to: CGPoint(x: 340, y: 145), control1: CGPoint(x: 126, y: 110), control2: CGPoint(x: 211, y: 126))
    p.addLine(to: CGPoint(x: 340, y: 245))
    p.addCurve(to: CGPoint(x: 20, y: 196), control1: CGPoint(x: 211, y: 225), control2: CGPoint(x: 121, y: 197)); p.closeSubpath()
  }
  static func bladder(half: Double, top: Double, base: Double, neck: Double) -> Path {
    Path { p in
      p.move(to: CGPoint(x: 180 - neck, y: base))
      p.addCurve(to: CGPoint(x: 180 - half, y: (top + base) / 2), control1: CGPoint(x: 164, y: base - 21), control2: CGPoint(x: 180 - half, y: base - 16))
      p.addCurve(to: CGPoint(x: 180, y: top), control1: CGPoint(x: 180 - half, y: top + 12), control2: CGPoint(x: 144, y: top))
      p.addCurve(to: CGPoint(x: 180 + half, y: (top + base) / 2), control1: CGPoint(x: 216, y: top), control2: CGPoint(x: 180 + half, y: top + 12))
      p.addCurve(to: CGPoint(x: 180 + neck, y: base), control1: CGPoint(x: 180 + half, y: base - 16), control2: CGPoint(x: 196, y: base - 21))
    }
  }
  struct Channel {
    let route: GalaxySSIHealthAtlasSectionLesson.Route
    let samples: [GalaxySSIHealthAtlasFunctionPath.Sample]
    init?(_ route: GalaxySSIHealthAtlasSectionLesson.Route) {
      var points: [GalaxySSIHealthAtlasFunctionPath.Sample] = []
      for i in 0...64 {
        guard let sample = GalaxySSIHealthAtlasFunctionPath.sample(route, position: Double(i) / 64, width: 360, height: 360) else { return nil }
        points.append(sample)
      }
      self.route = route; samples = points
    }
  }
  static let ureterChannel = Channel(GalaxySSIHealthAtlasUrineMotion.ureter)
  static let tunnelChannel = Channel(GalaxySSIHealthAtlasUrineMotion.tunnel)
  static let outletChannel = Channel(GalaxySSIHealthAtlasUrineMotion.outlet)
}
