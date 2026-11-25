import SwiftUI
import UIKit

struct GalaxySSIHealthAtlasHearingView: View {
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let phase: Double
  let language: String
  private typealias Motion = GalaxySSIHealthAtlasHearingMotion
  private static let air = color(0x246681), movement = color(0x23736E), nerveInk = color(0x976021), lettering = color(0x203F4A)
  var body: some View {
    let motion = Motion(chapter: story.chapter(phase), fraction: story.fraction(phase))
    GeometryReader { geometry in
      let edge = min(geometry.size.width, geometry.size.height), scale = edge / 344
      ZStack(alignment: .topLeading) {
        RoundedRectangle(cornerRadius: 8).fill(LinearGradient(colors: [Self.color(0xE9F3F7), Self.color(0xF9F1E6)], startPoint: .top, endPoint: .bottom))
        if let asset = motion.meshAsset {
          GalaxySSIHealthAtlasMeshImage(asset: asset, logicalSize: CGSize(width: 344, height: 344),
            vertices: motion.mesh, columns: 28, rows: 28).id(asset)
        }
        Canvas { context, _ in
          var drawing = context; drawing.scaleBy(x: scale, y: scale)
          switch motion.stage {
          case .sound: sound(in: drawing, motion: motion)
          case .middleEar: middle(in: drawing, motion: motion)
          case .cochlea: cochlearWave(in: drawing, motion: motion)
          case .hairCell: hair(in: drawing, motion: motion)
          case .nerve: nerve(in: drawing, motion: motion)
          }
        }
      }.frame(width: edge, height: edge).position(x: geometry.size.width / 2, y: geometry.size.height / 2)
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-hearing-art")
  }
  private func ear(in context: GraphicsContext) {
    bitmap(in: context, asset: "HealthAtlasEarSection", rect: CGRect(x: 16, y: 58, width: 312, height: 208))
  }
  private func sound(in context: GraphicsContext, motion: Motion) {
    ear(in: context)
    for distance in motion.soundDistances {
      let x = 25 + distance * 121, half = 12 + 6 * (1 - distance)
      var wave = Path(); wave.move(to: CGPoint(x: x, y: 165 - half))
      wave.addQuadCurve(to: CGPoint(x: x, y: 165 + half), control: CGPoint(x: x + 12, y: 165))
      outlined(in: context, path: wave, color: Self.air, outer: 4, inner: 2)
    }
    annotation(in: context, x: 88, y: 165, center: 72, baseline: 287, key: "canal", color: Self.air)
    annotation(in: context, x: 154, y: 168, center: 207, baseline: 304, key: "drum", color: Self.air)
  }
  private func middle(in context: GraphicsContext, motion: Motion) {
    let shift = motion.motion * 3
    focus(in: context, x: 155 + shift, y: 170, radius: 17, color: Self.movement)
    focus(in: context, x: 192 + shift, y: 148, radius: 20, color: Self.movement)
    focus(in: context, x: 213 + shift, y: 163, radius: 9, color: Self.movement)
    annotation(in: context, x: 155 + shift, y: 170, center: 73, baseline: 287, key: "drum", color: Self.movement)
    annotation(in: context, x: 192 + shift, y: 147, center: 189, baseline: 30, key: "ossicles", color: Self.movement)
    annotation(in: context, x: 213 + shift, y: 163, center: 255, baseline: 286, key: "window", color: Self.movement)
  }
  private func cochlearWave(in context: GraphicsContext, motion: Motion) {
    ear(in: context)
    let path = GalaxySSIHealthAtlasSectionLessonView.path(Self.cochlea, width: 344, height: 344)
    outlined(in: context, path: path, color: Self.movement, outer: 3, inner: 1.9)
    bead(in: context, route: Self.cochlea, position: motion.cochleaPosition, color: Self.movement)
    annotation(in: context, x: 246, y: 158, center: 266, baseline: 47, key: "cochlea_label", color: Self.movement)
    label(in: context, key: "basilar", center: 172, baseline: 275, size: 12)
    var wave = Path()
    for step in 0...100 {
      let position = Double(step) / 100
      let point = CGPoint(x: 31 + position * 282, y: 300 + 12 * Motion.packet(position, progress: motion.fraction))
      if step == 0 { wave.move(to: point) } else { wave.addLine(to: point) }
    }
    context.stroke(wave, with: .color(Self.movement), style: StrokeStyle(lineWidth: 2.7, lineCap: .round, lineJoin: .round))
    label(in: context, key: "base", center: 56, baseline: 330, size: 11)
    label(in: context, key: "apex", center: 288, baseline: 330, size: 11)
  }
  private func hair(in context: GraphicsContext, motion: Motion) {
    annotation(in: context, x: 79 + 5 * motion.motion, y: 83, center: 77, baseline: 23, key: "bundle", color: Self.movement)
    annotation(in: context, x: 86, y: 225, center: 82, baseline: 290, key: "synapse", color: Self.nerveInk)
    let opening = Motion.relativeChannelOpening(motion.motion)
    if opening > 0.32 {
      let departure = 15 * opening
      context.fill(circle(x: 90, y: 222 + departure, radius: 3.5), with: .color(Self.color(0xF1A337)))
      context.fill(circle(x: 100, y: 225 + departure, radius: 2.5), with: .color(Self.color(0xF1A337)))
    }
    tipLink(in: context, time: motion.fraction, motion: motion.motion, opening: opening)
  }
  private func nerve(in context: GraphicsContext, motion: Motion) {
    bitmap(in: context, asset: "HealthAtlasBrain", rect: CGRect(x: 70, y: 11, width: 204, height: 204))
    context.stroke(GalaxySSIHealthAtlasSectionLessonView.path(Self.nerveRoute, width: 344, height: 344),
      with: .color(Self.nerveInk), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
    for position in motion.nervePositions { bead(in: context, route: Self.nerveRoute, position: position, color: Self.nerveInk) }
    for point in [CGPoint(x: 45, y: 246), CGPoint(x: 172, y: 245), CGPoint(x: 300, y: 245)] {
      focus(in: context, x: point.x, y: point.y, radius: 7, color: Self.nerveInk)
    }
    label(in: context, key: "cochlea_label", center: 45, baseline: 281, size: 11.5)
    label(in: context, key: "relays", center: 172, baseline: 281, size: 11.5)
    label(in: context, key: "cortex", center: 289, baseline: 281, size: 11.5)
    label(in: context, key: "signal", center: 172, baseline: 315, size: 12.5)
  }
  private func bitmap(in context: GraphicsContext, asset: String, rect: CGRect) {
    context.draw(context.resolve(Image(asset)), in: rect)
  }
  private func bead(in context: GraphicsContext, route: GalaxySSIHealthAtlasSectionLesson.Route, position: Double, color: Color) {
    guard let sample = GalaxySSIHealthAtlasFunctionPath.sample(route, position: position, width: 344, height: 344) else { return }
    context.fill(circle(x: sample.point.x, y: sample.point.y, radius: 6), with: .color(.white))
    context.fill(circle(x: sample.point.x, y: sample.point.y, radius: 3.4), with: .color(color))
  }
  private func focus(in context: GraphicsContext, x: Double, y: Double, radius: Double, color: Color) {
    outlined(in: context, path: circle(x: x, y: y, radius: radius), color: color, outer: 3, inner: 1.4)
  }
  private func annotation(in context: GraphicsContext, x: Double, y: Double, center: Double, baseline: Double, key: String, color: Color) {
    let endpoint = baseline > y ? baseline - 15 : baseline + 6
    var line = Path(); line.move(to: CGPoint(x: x, y: y)); line.addLine(to: CGPoint(x: center, y: endpoint))
    outlined(in: context, path: line, color: color, outer: 2.8, inner: 1.3)
    context.fill(circle(x: x, y: y, radius: 2.7), with: .color(color))
    label(in: context, key: key, center: center, baseline: baseline, size: 11.5)
  }
  private func outlined(in context: GraphicsContext, path: Path, color: Color, outer: Double, inner: Double) {
    context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: outer, lineCap: .round, lineJoin: .round))
    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: inner, lineCap: .round, lineJoin: .round))
  }
  private func circle(x: Double, y: Double, radius: Double) -> Path {
    Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
  }
  func label(in context: GraphicsContext, key: String, center: Double, baseline: Double, size: Double) {
    let text = GalaxySSIHealthAtlasFunctionText.get("health_atlas_hear_" + key, language)
    let font = UIFont.systemFont(ofSize: size), width = (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: size)]).width
    context.draw(Text(verbatim: text).font(.system(size: size)).foregroundColor(Self.lettering),
      at: CGPoint(x: center - width / 2, y: baseline - font.ascender), anchor: .topLeading)
  }
  private static func route(_ x: Double, _ y: Double, _ controls: [Double]...) -> GalaxySSIHealthAtlasSectionLesson.Route {
    .init(start: .init(x: x, y: y), commands: controls.map { c in
      .init(kind: .cubic, points: [.init(x: c[0], y: c[1]), .init(x: c[2], y: c[3]), .init(x: c[4], y: c[5])])
    })
  }
  static let cochlea = route(218, 171, [225,138,278,139,281,171], [284,200,239,207,232,181], [226,157,270,155,266,177], [263,189,244,184,245,173], [246,165,255,165,255,173])
  static let nerveRoute = route(45, 246, [77,246,82,216,113,216], [148,216,144,245,172,245], [199,245,206,216,232,216], [262,216,271,245,300,245])
  static func color(_ value: UInt32) -> Color {
    Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
  }
}
