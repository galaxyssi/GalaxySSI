import Foundation

enum GalaxySSIHealthAtlasAccessoryGlandLabels {
  struct Callout {
    let key: String
    let x: Double
    let y: Double
    let row: Double
    let left: Bool
    init(_ key: String, _ x: Double, _ y: Double, _ row: Double, _ left: Bool) {
      self.key = key; self.x = x; self.y = y; self.row = row; self.left = left
    }
  }
  static let vesicle = Callout("vesicles", 119, 67, 58, true)
  static let ejaculatory = Callout("ejaculatory", 199, 113, 102, false)
  static let prostate = Callout("prostate", 138, 136, 134, true)
  static let bulb = Callout("bulbourethral", 207, 183, 180, false)
  static let bulbar = Callout("label_bulbar", 187, 229, 240, false)
  static let prostaticUrethra = Callout("label_prostatic", 181, 163, 163, false)
  static func forStep(_ step: Int) -> [Callout] {
    switch step {
    case 1: return [vesicle, Callout("label_vas", 217, 35, 28, false), Callout("label_junction", 205, 97, 87, false)]
    case 2: return [Callout("ejaculatory", 161, 115, 102, true), Callout("prostate", 220, 119, 110, false), prostaticUrethra]
    case 3: return [Callout("prostate", 138, 121, 113, true), Callout("label_prostate_ducts", 160, 156, 157, true), prostaticUrethra]
    case 4: return [Callout("bulbourethral", 149, 183, 166, true), Callout("label_membranous", 184, 172, 166, false), Callout("label_long_duct", 165, 210, 213, true), bulbar]
    default: return [vesicle, ejaculatory, prostate, bulb, bulbar]
    }
  }
}
