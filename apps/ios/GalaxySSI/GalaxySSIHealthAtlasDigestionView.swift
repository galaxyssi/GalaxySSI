import SwiftUI
import UIKit

struct GalaxySSIHealthAtlasDigestionView: View {
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let phase: Double
  let language: String
  private typealias Motion = GalaxySSIHealthAtlasDigestionMotion
  private static let contents = color(0x9B5828), muscle = color(0xA54F67), blood = color(0xA73552)
  private static let lymph = color(0x087966), water = color(0x27669D), lettering = color(0x253F48)
  var body: some View {
    let motion = Motion(courseID: story.id, chapter: story.chapter(phase), fraction: story.fraction(phase))
    Canvas { context, size in
      let scale = min(size.width, size.height) / 344
      guard scale > 0 else { return }
      var drawing = context
      drawing.translateBy(x: (size.width - 344 * scale) / 2, y: (size.height - 344 * scale) / 2)
      drawing.scaleBy(x: scale, y: scale)
      drawing.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: 344, height: 344), cornerRadius: 8),
        with: .linearGradient(Gradient(colors: [Self.color(0xEAF5F5), Self.color(0xFFF4E7)]),
          startPoint: .zero, endPoint: CGPoint(x: 0, y: 344)))
      var art = drawing
      if motion.stage == .villus {
        art.translateBy(x: 4, y: -16); art.scaleBy(x: 0.93, y: 0.93)
        picture(in: art, slug: "Jejunum", square: true)
        flow(in: art, route: Motion.waterSoluble, color: Self.blood, positions: motion.flowPositions(count: 5), size: 4.3)
        flow(in: art, route: Motion.dietaryFat, color: Self.lymph, positions: motion.flowPositions(count: 4), size: 4.3)
      } else {
        art.translateBy(x: 12, y: 41); art.scaleBy(x: 0.89, y: 0.89)
        scene(in: art, motion: motion)
      }
      labels(in: drawing, stage: motion.stage)
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier(story.id == "DIGESTION" ? "atlas-function-meal-art" : "atlas-function-colon-art")
  }
  private func scene(in context: GraphicsContext, motion: Motion) {
    let t = motion.fraction
    switch motion.stage {
    case .swallow:
      picture(in: context, slug: "Mouth")
      bolus(in: context, route: Motion.swallow, position: 0.03 + 0.93 * t, radius: 9)
    case .peristalsis:
      picture(in: context, slug: "Esophagus")
      squeeze(in: context, route: Motion.downEsophagus, position: max(0, 0.91 * t - 0.13), inside: 14, outer: 27, breadth: 5)
      bolus(in: context, route: Motion.downEsophagus, position: 0.04 + 0.92 * t, radius: 7.5)
    case .stomach:
      picture(in: context, slug: "Stomach")
      for particle in motion.stomachParticles { dot(in: context, x: particle.point.x, y: particle.point.y, radius: particle.radius, color: Self.contents) }
      if t > 0.53 { flow(in: context, route: Motion.stomachExit, color: Self.contents, positions: motion.flowPositions(count: 4, time: (t - 0.53) / 0.47), size: 3.4) }
      squeeze(in: context, route: Motion.stomachExit, position: t * 0.69, inside: 15, outer: 24, breadth: 7)
    case .duodenum:
      picture(in: context, slug: "Duodenum")
      flow(in: context, route: Motion.bile, color: Self.lymph, positions: motion.flowPositions(count: 3), size: 3.4)
      flow(in: context, route: Motion.enzymes, color: Self.water, positions: motion.flowPositions(count: 4), size: 3.4)
      for position in motion.duodenalPositions {
        guard let sample = sample(Motion.smallBowel, position) else { continue }
        let x = sample.point.x, y = sample.point.y
        if position < 0.47 { dot(in: context, x: x, y: y, radius: 6, color: Self.contents) }
        else {
          dot(in: context, x: x - 4, y: y, radius: 3.3, color: Self.contents)
          dot(in: context, x: x + 3, y: y + 3, radius: 2.5, color: Self.contents)
        }
      }
    case .cecum:
      picture(in: context, slug: "Large")
      flow(in: context, route: Motion.colonEntry, color: Self.contents, positions: motion.flowPositions(count: 3), size: 4)
    case .mix:
      picture(in: context, slug: "Large")
      let phase = t * .pi * 4
      squeeze(in: context, route: Motion.ascending, position: 0.53, inside: 9 + 8 * (sin(phase) + 1), outer: 29, breadth: 6)
      squeeze(in: context, route: Motion.transverse, position: 0.38, inside: 9 + 8 * (sin(phase - 1.6) + 1), outer: 29, breadth: 6)
      squeeze(in: context, route: Motion.descending, position: 0.57, inside: 9 + 8 * (sin(phase - 2.9) + 1), outer: 29, breadth: 6)
      bolus(in: context, route: Motion.ascending, position: 0.55 + sin(phase) * 0.21, radius: 6)
      bolus(in: context, route: Motion.transverse, position: 0.41 + sin(phase - 1.6) * 0.19, radius: 6)
      bolus(in: context, route: Motion.descending, position: 0.51 + sin(phase - 2.9) * 0.21, radius: 6)
    case .water:
      picture(in: context, slug: "Large")
      for route in Motion.waterTracks { flow(in: context, route: route, color: Self.water, positions: motion.flowPositions(count: 3), size: 3.4) }
      bolus(in: context, route: Motion.colonFlow, position: 0.20 + 0.19 * t, radius: 9 - t * 3)
      bolus(in: context, route: Motion.colonFlow, position: 0.53 + 0.15 * t, radius: 8 - t * 3)
    case .propulsion:
      picture(in: context, slug: "Large")
      squeeze(in: context, route: Motion.colonFlow, position: max(0, 0.96 * t - 0.085), inside: 14, outer: 26, breadth: 9)
      bolus(in: context, route: Motion.colonFlow, position: 0.06 + 0.9 * t, radius: 10)
    case .rectum:
      picture(in: context, slug: "Rectum")
      bolus(in: context, route: Motion.rectal, position: motion.rectalAdvance, radius: 12)
      squeeze(in: context, route: Motion.rectal, position: 0.98, inside: 14 + 7 * t, outer: 29, breadth: 4.5)
    case .villus: break
    }
  }
  private func picture(in context: GraphicsContext, slug: String, square: Bool = false) {
    context.draw(context.resolve(Image("HealthAtlasFunctionGut" + slug)), in: CGRect(x: 0, y: 0, width: 360, height: square ? 360 : 280))
  }
  private func sample(_ route: Motion.Route, _ position: Double) -> GalaxySSIHealthAtlasFunctionPath.Sample? {
    GalaxySSIHealthAtlasFunctionPath.sample(route, position: position, width: 360, height: 360)
  }
  private func squeeze(in context: GraphicsContext, route: Motion.Route, position: Double, inside: Double, outer: Double, breadth: Double) {
    guard let sample = sample(route, position) else { return }
    let x = sample.point.x, y = sample.point.y, dx = sample.direction.dx, dy = sample.direction.dy
    let nx = -dy, ny = dx
    var path = Path()
    for side in [-1.0, 1.0] {
      path.move(to: CGPoint(x: x + nx * side * outer - dx * breadth, y: y + ny * side * outer - dy * breadth))
      path.addQuadCurve(to: CGPoint(x: x + nx * side * outer + dx * breadth, y: y + ny * side * outer + dy * breadth),
        control: CGPoint(x: x + nx * side * inside, y: y + ny * side * inside))
    }
    context.stroke(path, with: .color(Self.color(0xFAE6DC)), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
    context.stroke(path, with: .color(Self.muscle), style: StrokeStyle(lineWidth: 4.4, lineCap: .round, lineJoin: .round))
  }
  private func bolus(in context: GraphicsContext, route: Motion.Route, position: Double, radius: Double) {
    guard let sample = sample(route, position) else { return }
    let x = sample.point.x, y = sample.point.y
    dot(in: context, x: x, y: y, radius: radius, color: Self.contents)
    dot(in: context, x: x - radius * 0.23, y: y - radius * 0.22, radius: radius * 0.42, color: Self.color(0xEDAF6F))
  }
  private func flow(in context: GraphicsContext, route: Motion.Route, color: Color, positions: [Double], size: Double) {
    for position in positions {
      guard let sample = sample(route, position) else { continue }
      let x = sample.point.x, y = sample.point.y, dx = sample.direction.dx, dy = sample.direction.dy
      var path = Path()
      path.move(to: CGPoint(x: x - (dx - dy) * size, y: y - (dy + dx) * size))
      path.addLine(to: CGPoint(x: x + dx * size, y: y + dy * size))
      path.addLine(to: CGPoint(x: x - (dx + dy) * size, y: y - (dy - dx) * size))
      context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: size * 1.22, lineCap: .round, lineJoin: .round))
      context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: size * 0.64, lineCap: .round, lineJoin: .round))
    }
  }
  private func labels(in context: GraphicsContext, stage: Motion.Stage) {
    switch stage {
    case .swallow: key(in: context, center: 172, id: "health_atlas_meal_bolus", color: Self.contents)
    case .peristalsis:
      key(in: context, center: 88, id: "health_atlas_meal_bolus", color: Self.contents)
      key(in: context, center: 250, id: "health_atlas_meal_contraction", color: Self.muscle)
    case .stomach: key(in: context, center: 172, id: "health_atlas_meal_chyme", color: Self.contents)
    case .duodenum:
      key(in: context, center: 80, id: "health_atlas_meal_enzymes", color: Self.water)
      key(in: context, center: 253, id: "health_atlas_meal_bile", color: Self.lymph)
    case .villus:
      key(in: context, center: 92, id: "health_atlas_meal_blood", color: Self.blood)
      key(in: context, center: 254, id: "health_atlas_meal_lymph", color: Self.lymph)
    case .water: key(in: context, center: 172, id: "health_atlas_colon_story_water_key", color: Self.water)
    default: key(in: context, center: 172, id: "health_atlas_colon_story_contents", color: Self.contents)
    }
  }
  private func key(in context: GraphicsContext, center: Double, id: String, color: Color) {
    let text = GalaxySSIHealthAtlasFunctionText.get(id, language), font = UIFont.systemFont(ofSize: 11.5)
    let width = (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 11.5)]).width
    let x = center - (width + 14) / 2
    dot(in: context, x: x + 4, y: 321, radius: 3.6, color: color)
    context.draw(Text(verbatim: text).font(.system(size: 11.5)).foregroundColor(Self.lettering),
      at: CGPoint(x: x + 14, y: 325 - font.ascender), anchor: .topLeading)
  }
  private func dot(in context: GraphicsContext, x: Double, y: Double, radius: Double, color: Color) {
    context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)), with: .color(color))
  }
  private static func color(_ value: UInt32) -> Color {
    Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
  }
}
