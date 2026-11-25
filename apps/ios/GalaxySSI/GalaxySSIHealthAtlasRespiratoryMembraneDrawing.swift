import SwiftUI

extension GalaxySSIHealthAtlasBreathingView {
  func membrane(in context: GraphicsContext, time: Double) {
    func band(_ top: Double, _ bottom: Double, _ color: UInt32) {
      context.fill(Path(roundedRect: CGRect(x: 19, y: top, width: 306, height: bottom - top), cornerRadius: 9), with: .color(Self.color(color)))
    }
    band(42, 140, 0xDEEDF2); band(144, 159, 0xDFA98F); band(160, 165, 0xECD8BA)
    band(166, 180, 0xA9C5C0); band(184, 282, 0xF2DBD7)
    label(in: context, text: t("alveolar_air"), center: 172, baseline: 32, size: 14)
    label(in: context, text: t("cross_section"), center: 172, baseline: 302, size: 13)
    let cell = 34 + 275 * time
    context.fill(Path(ellipseIn: CGRect(x: cell - 15, y: 234, width: 30, height: 21)), with: .color(Self.color(0xBA5763)))
    context.stroke(Path(ellipseIn: CGRect(x: cell - 8, y: 241, width: 16, height: 7)), with: .color(Self.color(0xED9196)), lineWidth: 2)
    for gas in 0...1 {
      let color = Self.color(gas == 0 ? 0x087A78 : 0x92531D)
      let x = gas == 0 ? 98.0 : 246, start = gas == 0 ? 87.0 : 222, end = gas == 0 ? 222.0 : 87
      let head = gas == 0 ? -7.0 : 7
      var arrow = Path(); arrow.move(to: CGPoint(x: x, y: start)); arrow.addLine(to: CGPoint(x: x, y: end))
      arrow.move(to: CGPoint(x: x, y: end)); arrow.addLine(to: CGPoint(x: x - 5, y: end + head))
      arrow.move(to: CGPoint(x: x, y: end)); arrow.addLine(to: CGPoint(x: x + 5, y: end + head))
      context.stroke(arrow, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round))
      for particle in 0...2 {
        let fraction = GalaxySSIHealthAtlasSignalMotion.loop(time * 1.6 + Double(particle) / 3)
        let y = start + (end - start) * fraction
        context.fill(Path(ellipseIn: CGRect(x: x - 5.4, y: y - 5.4, width: 10.8, height: 10.8)), with: .color(.white))
        context.fill(Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)), with: .color(color))
      }
    }
    label(in: context, text: t("barrier"), center: 172, baseline: 130, size: 13)
    label(in: context, text: t("blood"), center: 172, baseline: 274, size: 13)
    legend(in: context, center: 91, text: t("oxygen"), color: Self.color(0x087A78))
    legend(in: context, center: 253, text: t("carbon"), color: Self.color(0x92531D))
  }
}
