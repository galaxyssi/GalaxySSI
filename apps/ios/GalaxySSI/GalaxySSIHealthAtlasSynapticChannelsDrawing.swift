import SwiftUI

extension GalaxySSIHealthAtlasSignalDrawing {
  func gradedPotential(_ t: Double) {
    rounded(19, 262, 341, 343, 8, Self.cream)
    label(114, 282, "neuro_voltage"); label(275, 283, "neuro_threshold")
    let left = 32.0, bottom = 332.0, length = 292.0, height = 63.0
    let thresholdY = bottom - 0.58 * height
    for i in 0...19 {
      let x = left + Double(i) * 15
      line(x, thresholdY, x + 7, thresholdY, Self.gold, 1)
    }
    let samples = max(1, Int(t * Double(Motion.potential.count - 1)))
    var curve = Path(); curve.move(to: CGPoint(x: left, y: bottom - height * Motion.potential[0]))
    for i in 1...samples {
      curve.addLine(to: CGPoint(x: left + length * Double(i) / Double(Motion.potential.count - 1), y: bottom - height * Motion.potential[i]))
    }
    stroke(curve, Self.blue, 2.5)
    let reading = Motion.gradedInput(t)
    dot(left + length * t, bottom - height * reading, 4, reading >= 0.58 ? Self.gold : Self.blue)
  }
  func membraneRelay(_ t: Double) {
    rounded(19, 274, 341, 343, 8, Self.cream)
    line(34, 303, 326, 303, Self.coral, 3); line(34, 314, 326, 314, Self.coral, 3)
    for segment in 0...2 {
      let x = 77.0 + Double(segment) * 103, local = t * 1.55 - Double(segment) * 0.29
      let activation = (0.04...0.69).contains(local), sodium = local < 0.32
      let color: UInt32 = !activation ? 0x8FA4A6 : sodium ? Self.blue : Self.violet
      gate(x, 309, color, open: activation)
      if activation {
        if sodium { arrow(x, 289, x, 327, Self.blue) } else { arrow(x, 327, x, 289, Self.violet) }
        let fraction = sodium ? (local - 0.04) / 0.28 : (local - 0.32) / 0.37
        dot(x, sodium ? 289 + 38 * fraction : 327 - 38 * fraction, 3.1, color)
      }
    }
    dot(40, 333, 2.9, Self.blue); label(98, 337, "neuro_sodium_in")
    dot(216, 333, 2.9, Self.violet); label(274, 337, "neuro_potassium_out")
  }
  func gate(_ x: Double, _ y: Double, _ color: UInt32, open: Bool) {
    rounded(x - 14, y - 11, x + 14, y + 11, 4, Self.cream)
    rounded(x - 13, y - 9, x - 4, y + 9, 4, color)
    rounded(x + 4, y - 9, x + 13, y + 9, 4, color)
    if !open { line(x - 5, y, x + 5, y, color, 3) }
  }
}
