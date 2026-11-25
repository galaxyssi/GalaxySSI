import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func ductBufferSecrete(_ t: Double) {
    rounded(45, 146, 315, 213, 7, 0xD8EEE8)
    for i in 0...5 {
      let x = 45 + Double(i) * 45
      ductBufferCell(x, 115, 45, 36, active: i == 1 || i == 3)
      ductBufferCell(x, 207, 45, 36, active: i == 2)
    }
    line(45, 151, 315, 151, 0x547C7B, 1.6); line(45, 207, 315, 207, 0x547C7B, 1.6)
    for i in 0...2 {
      let base = 112 + 45 * Double(i), top = i != 1
      for j in 0...2 {
        let p = GalaxySSIHealthAtlasDuctBufferMotion.secretion(t - Double(j) * 0.09, i)
        if p > 0 {
          let across = min(1, p * 2), downstream = max(0, p * 2 - 1)
          let y = top ? 142 + across * (26 + Double(j) * 4) : 217 - across * (27 + Double(j) * 4)
          ductBufferFluidMark(base + Double(j) * 7 + downstream * 38, y)
        }
      }
    }
    arrow(272, 181, 300, 181, 0x236E71)
  }
}
