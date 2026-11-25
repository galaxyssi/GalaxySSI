import SwiftUI

extension GalaxySSIHealthAtlasInsulinDrawing {
  func potassiumTrace(_ t: Double) {
    let panel = Path(roundedRect: CGRect(x: 20, y: 277, width: 320, height: 73), cornerRadius: 8)
    fill(panel, 0xFAF5ED); stroke(panel, 0xD9C6B7, 1)
    label(80, 296, "k_opening"); label(275, 296, "voltage")
    let traces: [(UInt32, (Double) -> Double)] = [
      (Self.potassium, Motion.potassiumOpen), (Self.calcium, Motion.relativeDepolarization)
    ]
    for (color, trace) in traces {
      let x = color == Self.potassium ? 80.0 : 275
      line(x - 12, 302, x + 12, 302, color, 2)
      func y(_ time: Double) -> Double { 338 - 26 * trace(time) }
      var curve = Path(); curve.move(to: CGPoint(x: 39, y: y(0)))
      for index in 1...24 {
        let fraction = t * Double(index) / 24
        curve.addLine(to: CGPoint(x: 39 + 282 * fraction, y: y(fraction)))
      }
      stroke(curve, color, 2); particle(39 + 282 * t, y(t), color, 3.2)
    }
  }
}
