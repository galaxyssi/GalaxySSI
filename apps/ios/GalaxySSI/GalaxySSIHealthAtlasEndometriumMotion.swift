import Foundation

enum GalaxySSIHealthAtlasEndometriumMotion {
  static let left = 106.0, right = 254.0, basal = 244.0, muscle = 281.0
  static let glandSites = [129.0,177,228]
  static func ramp(_ t: Double, from: Double, to: Double) -> Double {
    let p = t.isFinite ? min(1,max(0,(t - from) / (to - from))) : 0
    return p * p * (3 - 2 * p)
  }
  private static func wave(_ t: Double) -> Double { sin(t * 2 * .pi) }
  struct Frame {
    let step: Int; let t: Double; let top: Double; let secretory: Double; let erosion: Double?
    init(step: Int, fraction: Double) {
      self.step = step; t = fraction.isFinite ? min(1,max(0,fraction)) : 0
      switch step {
      case 1: top = 244 - (244 - 161) * GalaxySSIHealthAtlasEndometriumMotion.ramp(t,from: 0.05,to: 0.91)
      case 2: top = 161 - 12 * GalaxySSIHealthAtlasEndometriumMotion.ramp(t,from: 0.02,to: 0.75)
      case 3: top = 149
      case 4: top = 244
      default: top = 161
      }
      secretory = step == 2 ? GalaxySSIHealthAtlasEndometriumMotion.ramp(t,from: 0.08,to: 0.78) : step == 3 ? 1 : 0
      erosion = step == 3 ? t : nil
    }
  }
  static func surface(_ x: Double, top: Double, erosion: Double?) -> Double {
    let depth = basal - top, ripple = 1.6 * wave((x - left) / 52) * (depth / 95)
    guard let erosion else { return top + ripple }
    let lag = 0.11 + 0.24 * abs(wave((x - 182) / 145)) + 0.08 * wave((x - left) / 45)
    return basal - (depth - ripple) * (1 - ramp(erosion,from: lag,to: lag + 0.47))
  }
  struct Stroma { let x: Double; let y: Double; let rx: Double; let ry: Double; let angle: Double; let inBase: Bool }
  static func stroma(_ frame: Frame, index: Int) -> Stroma? {
    let x = 113 + Double(index * 31 % 133), inBase = index % 3 == 0
    let upper = surface(x,top: frame.top,erosion: nil)
    let y = inBase ? 248 + Double(index * 13 % 29) : upper + (basal - upper) * (0.13 + Double(index * 19 % 73) / 100)
    if !inBase && (y < surface(x,top: frame.top,erosion: frame.erosion) + 3 || frame.top == basal) { return nil }
    let rounding = inBase || index % 4 == 0 ? 0 : frame.secretory
    return .init(x: x,y: y,rx: 3.2 - 0.5 * rounding,ry: 1.1 + 1.1 * rounding,angle: index % 2 == 0 ? 27 : -21,inBase: inBase)
  }
  static func secretion(_ t: Double, gland: Int, particle: Int) -> (fraction: Double, radius: Double)? {
    let travel = ramp(t,from: 0.14 + 0.12 * Double(particle) + 0.05 * Double(gland),to: 0.84 + 0.06 * Double(particle))
    guard travel > 0 else { return nil }
    return ((1 - travel) * (0.62 - 0.17 * Double(particle)),1.2 + 1.2 * ramp(t,from: 0.18,to: 0.58))
  }
  struct Fragment { let x: Double; let y: Double; let alpha: Int }
  static func fragment(_ t: Double, index: Int) -> Fragment? {
    let move = ramp(t,from: 0.06 + Double(index) * 0.14,to: 0.6 + Double(index) * 0.12)
    let opacity = ramp(move,from: 0,to: 0.18) * (1 - ramp(move,from: 0.64,to: 1))
    guard opacity > 0 else { return nil }
    return .init(x: 190 - 21 * Double(index) + move * (10 - 5 * Double(index)),y: 162 + Double(index) * 4 - 31 * move,alpha: Int(215 * opacity))
  }
  static func repairRadius(_ t: Double, index: Int) -> Double { 3 + 24 * ramp(t,from: 0.04 + Double(index) * 0.07,to: 0.85 + Double(index) * 0.06) }
}
