import SwiftUI

struct GalaxySSIHealthAtlasLoadTransferStoryView: View {
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let phase: Double
  let language: String
  let pelvic: Bool
  var body: some View {
    let step = story.chapter(phase), t = story.fraction(phase)
    GeometryReader { geometry in
      let edge = min(geometry.size.width, geometry.size.height), scale = edge / 360
      ZStack(alignment: .topLeading) {
        Canvas { context, _ in
          var local = context; local.scaleBy(x: scale, y: scale)
          GalaxySSIHealthAtlasIllustratedDrawing(context: local, language: language)
            .gradient(Path(roundedRect: CGRect(x: 0, y: 0, width: 360, height: 360), cornerRadius: 8), 0, 360, 0xE8F4F3, 0xFBF0DF)
        }
        if !pelvic {
          GalaxySSIHealthAtlasMeshImage(asset: "HealthAtlasCompleteSubcutaneousSection",
            logicalSize: CGSize(width: 360, height: 360),
            vertices: Self.mesh(compression: Self.compression(step: step, fraction: t)), columns: 24, rows: 20)
        }
        Canvas { context, _ in
          var local = context; local.scaleBy(x: scale, y: scale)
          let art = GalaxySSIHealthAtlasIllustratedDrawing(context: local, language: language)
          if pelvic { art.pelvicLoadScene(step, t) }
          else { art.subcutaneousScene(step, t, Self.compression(step: step, fraction: t)) }
        }
      }.frame(width: edge, height: edge).position(x: geometry.size.width / 2, y: geometry.size.height / 2)
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[step].caption, language))
      .accessibilityIdentifier(pelvic ? "atlas-function-pelvic-ring-art" : "atlas-function-subcutaneous-cushion-art")
  }
  static func compression(step: Int, fraction: Double) -> Double {
    let smooth = fraction * fraction * (3 - 2 * fraction)
    return step == 0 ? 0 : step == 1 ? smooth : step == 2 ? 1 : 1 - smooth
  }
  static func mesh(compression: Double) -> [CGPoint] {
    guard compression.isFinite, (0...1).contains(compression) else { return [] }
    return (0...20).flatMap { row in
      (0...24).map { column in
        let x = Double(column) * 360 / 24, y = Double(row) * 280 / 20
        let relative = (x - 180) / 100, across = max(0, 1 - relative * relative)
        let depth = min(1, max(0, (223 - y) / 172)), bulge = max(0, 1 - abs(y - 153) / 75)
        return CGPoint(x: x + 15 * compression * relative * across * bulge,
          y: 42 + y + 28 * compression * across * depth)
      }
    }
  }
}
