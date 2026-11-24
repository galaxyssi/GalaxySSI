import SwiftUI

extension GalaxySSIHealthAtlasHearingView {
  func tipLink(in context: GraphicsContext, time: Double, motion: Double, opening: Double) {
    let right = 253 + 16 * motion, tall = 293 + 24 * motion
    func rounded(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ radius: Double, _ color: UInt32) {
      context.fill(Path(roundedRect: CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1), cornerRadius: radius), with: .color(Self.color(color)))
    }
    func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ color: UInt32, _ width: Double) {
      var path = Path(); path.move(to: CGPoint(x: x1, y: y1)); path.addLine(to: CGPoint(x: x2, y: y2))
      context.stroke(path, with: .color(Self.color(color)), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
    rounded(157, 27, 333, 304, 9, 0xF8FBF8)
    label(in: context, key: "tip_link", center: 245, baseline: 55, size: 13)
    label(in: context, key: "endolymph", center: 245, baseline: 80, size: 11)
    rounded(168, 218, 322, 260, 10, 0xD8E9DF)
    line(205, 228, right - 45, 180, 0x4D8F86, 12)
    line(245, 228, right, 150, 0x4D8F86, 12)
    line(285, 228, tall, 114, 0x4D8F86, 12)
    line(right - 43, 177, right - 1, 169, 0x976021, 1.7 + opening)
    line(right + 2, 150, tall - 5, 138, 0x976021, 1.7 + opening)
    let gap = 1 + opening * 5
    rounded(right - 10, 144, right - gap, 149, 2, 0x23736E)
    rounded(right + gap, 144, right + 10, 149, 2, 0x23736E)
    if opening > 0.32 {
      for index in 0...2 {
        let progress = GalaxySSIHealthAtlasSignalMotion.loop(time * 5 + Double(index) / 3)
        context.fill(Path(ellipseIn: CGRect(x: right - 3, y: 118 + progress * 56 - 3, width: 6, height: 6)), with: .color(Self.color(0xA76623)))
      }
    }
    label(in: context, key: "potassium", center: 245, baseline: 285, size: 12)
  }
}
