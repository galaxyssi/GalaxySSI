import Foundation

struct GalaxySSIHealthAtlasPleuraMotion {
  let breath: Double
  var widen: Double { 1 + 0.11 * breath }
  init(step: Int, fraction: Double) {
    let t = fraction.isFinite ? min(1, max(0, fraction)) : 0, pulse = (1 - cos(2 * .pi * t)) / 2
    switch step {
    case 0: breath = 0.28 * pulse
    case 1: breath = 0.55 * t
    case 2: breath = 0.55 + 0.45 * t
    case 3: breath = 1 - 0.72 * pulse
    default: breath = 1 - t
    }
  }
  func wallTick(_ i: Int) -> Double { 55 + Double(i) * 54 + 9 * breath }
  func lungTick(_ i: Int) -> Double { 55 + Double(i) * 54 + 35 * breath }
}
