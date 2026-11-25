import SwiftUI

extension GalaxySSIHealthAtlasVisionView {
  func rodCapture(in context: GraphicsContext, time: Double, count: Int) {
    picture(in: context, asset: "HealthAtlasSensoryRod", l: 4, t: 43, r: 142, b: 290)
    let light = GalaxySSIHealthAtlasRodResponse.light(time), target = 73.0
    if (0.10...0.24).contains(time) {
      let incident = (time - 0.10) / 0.14
      dot(in: context, x: target, y: 26 + 66 * incident, radius: 4, color: Self.gold)
    }
    for index in 0..<count {
      let move = GalaxySSIHealthAtlasVisionMotion.loop(time * 2.4 + Double(index) / Double(count))
      dot(in: context, x: target + Double(index % 3 - 1) * 9, y: 284 + move * 17, radius: 2.6, color: Self.neural)
    }
    let focus = light > 0.5 ? Self.gold : Self.rod
    context.stroke(circle(x: target, y: 92, radius: 19), with: .color(focus), lineWidth: 1.6)
    var leader = Path(); leader.move(to: CGPoint(x: target + 19, y: 92)); leader.addLine(to: CGPoint(x: 147, y: 108))
    context.stroke(leader, with: .color(focus), lineWidth: 1.6)
    label(in: context, x: target, y: 326, key: count > 3 ? "dark_release" : "light_release", size: 11.5)
    rodMembrane(in: context, time: time, light: light)
  }
  private func rodMembrane(in context: GraphicsContext, time: Double, light: Double) {
    func rounded(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ radius: Double, _ color: Color) {
      context.fill(Path(roundedRect: CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1), cornerRadius: radius), with: .color(color))
    }
    rounded(142, 38, 333, 306, 8, Self.color(0xEEF7F5)); rounded(142, 150, 333, 306, 8, Self.color(0xF6ECDF))
    label(in: context, x: 237, y: 59, key: light > 0.5 ? "lit" : "unlit", size: 12.5)
    label(in: context, x: 237, y: 91, key: "dark_current", size: 11)
    let gate = GalaxySSIHealthAtlasRodResponse.opening(time), gap = 9 * gate
    for row in 0...1 {
      let y = 136 + 15 * Double(row)
      var membrane = Path(); membrane.move(to: CGPoint(x: 151, y: y)); membrane.addLine(to: CGPoint(x: 214, y: y))
      membrane.move(to: CGPoint(x: 260, y: y)); membrane.addLine(to: CGPoint(x: 324, y: y))
      context.stroke(membrane, with: .color(Self.color(0xAD7A70)), lineWidth: 3)
    }
    rounded(211, 125, 237 - gap, 162, 7, Self.rod); rounded(237 + gap, 125, 263, 162, 7, Self.rod)
    for index in 0..<Int(gate * 4 + 0.5) {
      let f = GalaxySSIHealthAtlasVisionMotion.loop(time * 2.2 + Double(index) * 0.25)
      dot(in: context, x: 237, y: 104 + 74 * f, radius: 3.1, color: Self.neural)
    }
    label(in: context, x: 238, y: 190, key: gate > 0.22 ? "cng_open" : "cng_closed", size: 11.5)
    let messenger = GalaxySSIHealthAtlasRodResponse.messenger(time)
    for index in 0...6 {
      dot(in: context, x: 169 + Double(index) * 22, y: 216 + sin(time * 6 + Double(index)) * 3, radius: 4.3,
        color: Double(index) < messenger * 7 ? Self.gold : Self.color(0xC9BCAE))
    }
    label(in: context, x: 237, y: 241, key: "cgmp", size: 11.5)
    label(in: context, x: 237, y: 274, key: gate <= 0.22 ? "hyperpolarized" : "resting", size: 11.5)
  }
}
