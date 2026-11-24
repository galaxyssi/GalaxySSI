import Foundation

enum GalaxySSIHealthAtlasPodocyteMotion {
  typealias Point = GalaxySSIHealthAtlasSectionLesson.Point
  static let left = 24.0, right = 244.0, matrixDepth = 13.0
  static let fenestrae = (0..<8).map { 43 + 25.5 * Double($0) }
  static let feet = (0..<8).map { 39.5 + 27 * Double($0) }
  static let slits = (0..<7).map { feet[$0] + 13.5 }
  static func safe(_ t: Double) -> Double { t.isFinite ? min(1,max(0,t)) : 0 }
  private static func ease(_ f: Double) -> Double { f * f * (3 - 2 * f) }
  static func progress(step: Int, t: Double) -> Double {
    let f = safe(t)
    switch step {
    case 0: return ease(f)
    case 1: return f * f
    case 2: return 1 - (1 - f) * (1 - f)
    case 3: return ease(safe((f - 0.08) / 0.84))
    default: return f
    }
  }
  static func wallY(_ x: Double) -> Double { let dx = x - 134; return 173 - 0.0008 * dx * dx }
  static func endoY(_ x: Double) -> Double {
    let bulge = max(0,1 - abs(x - 81) / 15)
    return wallY(x) - 12 - 12 * bulge * bulge
  }
  static func footY(_ x: Double) -> Double { wallY(x) + matrixDepth }
  struct Segment { let left: Double; let right: Double }
  static let endothelialSegments: [Segment] = (0...8).map { i in
    .init(left: i == 0 ? left : fenestrae[i - 1] + 3.5,right: i == 8 ? right : fenestrae[i] - 3.5)
  }
  static func strip(top: (Double) -> Double, bottom: (Double) -> Double, left: Double = 24, right: Double = 244) -> [Point] {
    let samples = max(1,Int((right - left) / 2))
    func x(_ i: Int) -> Double { left + (right - left) * Double(i) / Double(samples) }
    var points = [Point(x: left,y: top(left))]
    for i in 1...samples { points.append(.init(x: x(i),y: top(x(i)))) }
    for i in stride(from: samples, through: 0, by: -1) { points.append(.init(x: x(i),y: bottom(x(i)))) }
    return points
  }
  static func focusAlpha(_ x: Double, center: Double, width: Double) -> Double { max(0,1 - abs(x - center) / width) }
  static func bloodX(_ f: Double, index: Int) -> Double { left - 13 + (45 + Double(index) * 76 + f * 190).truncatingRemainder(dividingBy: right - left + 26) }
  static func proteinX(_ f: Double, index: Int) -> Double { left - 7 + (23 + Double(index) * 57 + f * 157).truncatingRemainder(dividingBy: right - left + 14) }
  static func filtrate(_ f: Double, index: Int) -> (p: Double, q: Double) {
    let p = (f * 1.27 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
    return (p,(p + 0.16).truncatingRemainder(dividingBy: 1))
  }
}
