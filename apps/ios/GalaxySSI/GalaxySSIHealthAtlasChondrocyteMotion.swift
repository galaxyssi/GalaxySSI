import Foundation

struct GalaxySSIHealthAtlasChondrocyteMotion {
  let step: Int
  let t: Double
  let hydration: Double
  let squeeze: Double
  let scaleY: Double
  init(step: Int, fraction: Double) {
    self.step = step; t = fraction.isFinite ? min(1,max(0,fraction)) : 0
    hydration = step < 3 ? 0.18 : step == 3 ? 0.18 + 0.82 * Self.ease(t,from: 0.03,to: 0.95) : 1
    squeeze = step == 4 ? Self.ease(t,from: 0,to: 0.36) * (1 - Self.ease(t,from: 0.38,to: 0.96)) : 0
    scaleY = 1 - 0.19 * squeeze
  }
  static func ease(_ t: Double, from: Double, to: Double) -> Double {
    let f = t.isFinite ? min(1,max(0,(t - from) / (to - from))) : 0
    return f * f * (3 - 2 * f)
  }
  static func mappedY(_ y: Double, scale: Double) -> Double { 177 + (y - 177) * scale }
  static func collagenRide(_ t: Double, index: Int) -> Double { ease(t,from: 0.04 + Double(index) * 0.21,to: 0.57 + Double(index) * 0.19) }
  static func collagenGrowth(_ t: Double, index: Int) -> Double { ease(t,from: 0.53 + Double(index) * 0.19,to: 0.83 + Double(index) * 0.17) }
  static func deposit(_ t: Double, index: Int) -> Double { ease(t,from: Double(index) * 0.16,to: 0.56 + Double(index) * 0.20) }
  static func zoneHead(_ t: Double, index: Int) -> Double { min(1,max(0,(t - 0.13 * Double(index)) / 0.56)) * 1.34 }
  var washAlpha: Int { Int(111 * hydration * (1 - 0.56 * squeeze)) }
  var compressionAlpha: Int { Int(215 * Self.ease(t,from: 0,to: 0.15) * (1 - Self.ease(t,from: 0.35,to: 0.65))) }
  struct Water { let x: Double; let y: Double; let length: Double; let alpha: Int }
  func water(index: Int, side: Double) -> Water {
    let advance = step == 3 ? Self.ease(t,from: 0.04 + 0.063 * Double(index),to: 0.72 + 0.066 * Double(index)) : 0
    let x = 180 + side * (step < 4 ? 139 - 40 * advance : 99 + 40 * squeeze) + Double(index % 3 - 1) * 12
    return .init(x: x,y: 155 + 15 * Double(index) + side * 4,length: 7 + 5 * hydration,
      alpha: Int(step < 4 ? 60 + 132 * advance : 192 - 75 * squeeze))
  }
}
