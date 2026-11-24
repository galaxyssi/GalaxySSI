import Foundation

enum GalaxySSIHealthAtlasSebaceousMotion {
  static func eased(_ t: Double) -> Double { t * t * (3 - 2 * t) }
  static func canal(_ t: Double, _ index: Int) -> Double {
    (t + Double(index) * 0.24).truncatingRemainder(dividingBy: 1) * 0.93 + 0.02
  }
  static func release(_ t: Double, _ index: Int) -> Double {
    min(0.95, eased(t) * 0.74 + Double(index) * 0.072)
  }
  static func duct(_ t: Double, _ index: Int) -> Double {
    (t * 0.78 + Double(index) / 4).truncatingRemainder(dividingBy: 1) * 0.93 + 0.03
  }
  static func volume(_ stored: Double, _ index: Int) -> Double {
    min(1, max(0, stored * 1.32 - Double(index) * 0.12))
  }
}
