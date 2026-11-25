import SwiftUI
import UIKit

struct GalaxySSIHealthAtlasNephronView: View {
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let phase: Double
  let language: String
  private typealias Motion = GalaxySSIHealthAtlasNephronMotion
  private static let labelInk = color(0x27424C)
  var body: some View {
    let motion = Motion(chapter: story.chapter(phase), fraction: story.fraction(phase))
    Canvas { context, size in
      let scale = min(size.width, size.height) / 344
      guard scale > 0 else { return }
      var drawing = context
      drawing.translateBy(x: (size.width - 344 * scale) / 2, y: (size.height - 344 * scale) / 2)
      drawing.scaleBy(x: scale, y: scale)
      drawing.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: 344, height: 344), cornerRadius: 8),
        with: .linearGradient(Gradient(colors: [Self.color(0xECF5F6), Self.color(0xFAF1E4)]),
          startPoint: .zero, endPoint: CGPoint(x: 0, y: 344)))
      var art = drawing; art.translateBy(x: 55, y: 17); art.scaleBy(x: 0.20, y: 0.20)
      art.draw(art.resolve(Image("HealthAtlasNephron")), in: CGRect(x: 0, y: 0, width: 1173, height: 1341))
      if let route = motion.vessel {
        art.stroke(GalaxySSIHealthAtlasSectionLessonView.path(route, width: 1173, height: 1341),
          with: .color(Self.color(0xDF9F9C)), style: StrokeStyle(lineWidth: 37, lineCap: .round, lineJoin: .round))
        stream(in: art, route: route, color: Self.color(Motion.Ink.blood.rawValue), positions: motion.positions(count: 2))
      }
      for flow in motion.streams {
        stream(in: art, route: flow.route, color: Self.color(flow.ink.rawValue), positions: motion.positions(count: flow.count))
      }
      switch motion.stage {
      case .filter:
        label(in: drawing, key: "glomerulus", center: 84, baseline: 122)
        legend(in: drawing, key: "blood", center: 78, ink: .blood)
        legend(in: drawing, key: "filtrate", center: 231, ink: .crosses)
      case .proximal:
        label(in: drawing, key: "capillary", center: 95, baseline: 150)
        legend(in: drawing, key: "filtrate", center: 84, ink: .fluid)
        legend(in: drawing, key: "reabsorb", center: 249, ink: .crosses)
      case .loop:
        label(in: drawing, key: "water", center: 113, baseline: 168, color: Self.color(Motion.Ink.crosses.rawValue))
        label(in: drawing, key: "salt", center: 217, baseline: 194, color: Self.color(Motion.Ink.salt.rawValue))
        legend(in: drawing, key: "filtrate", center: 172, ink: .fluid)
      case .distal:
        label(in: drawing, key: "capillary", center: 246, baseline: 29)
        legend(in: drawing, key: "filtrate", center: 84, ink: .fluid)
        legend(in: drawing, key: "secretion", center: 243, ink: .secreted)
      case .collect:
        label(in: drawing, key: "water", center: 215, baseline: 173, color: Self.color(Motion.Ink.crosses.rawValue))
        legend(in: drawing, key: "urine", center: 220, ink: .salt)
      }
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-nephron-art")
  }
  private func stream(in context: GraphicsContext, route: Motion.Route, color: Color, positions: [Double]) {
    for position in positions {
      guard let sample = GalaxySSIHealthAtlasFunctionPath.sample(route, position: position, width: 1173, height: 1341) else { continue }
      let x = sample.point.x, y = sample.point.y, dx = sample.direction.dx, dy = sample.direction.dy
      var glyph = Path()
      glyph.move(to: CGPoint(x: x - 14 * dx + 10 * dy, y: y - 14 * dy - 10 * dx))
      glyph.addLine(to: CGPoint(x: x + 7 * dx, y: y + 7 * dy))
      glyph.addLine(to: CGPoint(x: x - 14 * dx - 10 * dy, y: y - 14 * dy + 10 * dx))
      context.stroke(glyph, with: .color(.white), style: StrokeStyle(lineWidth: 13, lineCap: .round, lineJoin: .round))
      context.stroke(glyph, with: .color(color), style: StrokeStyle(lineWidth: 7.5, lineCap: .round, lineJoin: .round))
    }
  }
  private func label(in context: GraphicsContext, key: String, center: Double, baseline: Double, color: Color? = nil) {
    let text = t(key), font = UIFont.systemFont(ofSize: 11.5)
    let width = (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 11.5)]).width
    context.draw(Text(verbatim: text).font(.system(size: 11.5)).foregroundColor(color ?? Self.labelInk),
      at: CGPoint(x: center - width / 2, y: baseline - font.ascender), anchor: .topLeading)
  }
  private func legend(in context: GraphicsContext, key: String, center: Double, ink: Motion.Ink) {
    let width = (t(key) as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 11.5)]).width
    let x = center - (width + 13) / 2 + 3.5
    context.fill(Path(ellipseIn: CGRect(x: x - 3.5, y: 318.5, width: 7, height: 7)), with: .color(Self.color(ink.rawValue)))
    label(in: context, key: key, center: center + 6, baseline: 326)
  }
  private static func color(_ value: UInt32) -> Color {
    Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
  }
  private func t(_ key: String) -> String { GalaxySSIHealthAtlasFunctionText.get("health_atlas_nephron_story_" + key, language) }
}
