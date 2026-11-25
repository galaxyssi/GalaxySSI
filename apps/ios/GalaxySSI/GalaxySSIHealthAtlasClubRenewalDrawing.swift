import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func clubRenew(_ t: Double) {
    typealias Motion = GalaxySSIHealthAtlasClubMotion
    let expansion = Motion.expand(t), division = Motion.divide(t), mature = Motion.differentiate(t)
    clubWallBed()
    clubCiliatedCell(57, width: 0.70, phase: 0.3)
    clubCiliatedCell(287, width: 1.02, phase: 0.3)
    let right = 187 + 52 * expansion, joinY = 171 + 20 * mature, shoulderY = 159 + 32 * mature
    let renewal = GalaxySSIHealthAtlasClubGeometry.renewal(right, joinY, shoulderY)
    gradient(renewal, 150, 255, 0xF7DFA1, 0xDFAA6A)
    if division > 0 {
      let boundary = joinY + (253 - joinY) * division
      line(163, 253, 163, boundary, 0x815B35, 1.3)
    }
    if mature > 0 {
      var local = context; local.clip(to: renewal); local.opacity *= Double(Int(255 * mature)) / 255
      let top = min(joinY, shoulderY)
      copy(local).gradient(Path(CGRect(x: 163, y: top, width: right - 161, height: 254 - top)), 186, 256, 0xD6E9E1, 0xA7C9C3)
      line(163, 253, 163, joinY, 0x727477, 1.15)
      for i in 0...9 {
        let x = 171 + Double(i) * 6.4, y = 191 - (191 - shoulderY) * 0.64
        clubCilium(x, y, length: 16 * mature, bend: 3 + 3 * mature)
      }
    }
    stroke(renewal, 0x815B35, 1.4)
    let nucleusX = 142 - 17 * division
    oval(nucleusX - 12, 213, nucleusX + 12, 239, fill: 0xA480AA, border: Self.violet)
    if division > 0 {
      let childX = 143 + (right - 162) * 0.75 * division, r = 12 * division
      oval(childX - r, 226 - r, childX + r, 226 + r, fill: 0xA480AA, border: Self.violet)
    }
    clubGranule(125, 178, 4); clubGranule(133, 191, 3.5)
  }
}
