import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func gastricChiefDigest(_ t: Double) {
    typealias Geometry = GalaxySSIHealthAtlasGastricChiefGeometry
    typealias Motion = GalaxySSIHealthAtlasGastricChiefMotion
    gastricChiefTint(Geometry.stomachCavity, 67, 289, 0xE5F2EC, 0xC2E0DD)
    stroke(Geometry.stomachCavity, 0xE5AA9E, 13); stroke(Geometry.stomachCavity, 0x9A6470, 1.65)
    stroke(Geometry.cavityFolds, 0xEFD9CA, 7); stroke(Geometry.cavityFolds, Self.coral, 1.1)
    let left = Motion.split(t, 0), right = Motion.split(t, 1)
    let middleX = 5 * left - 4 * right, middleY = 20 * left
    if left == 0 { gastricChiefBond(3, 0, 0) }
    if right == 0 { gastricChiefBond(7, middleX, middleY) }
    gastricChiefChain(0, 3, -11 * left, -8 * left)
    gastricChiefChain(4, 7, middleX, middleY)
    gastricChiefChain(8, 11, middleX + 17 * right, middleY - 29 * right)
    for i in 0...1 {
      let p = Motion.approach(t, i), split = i == 0 ? left : right
      let target = i == 0 ? 136.0 : 216.0, side = i == 0 ? -1.0 : 1.0
      let x = target + side * (46 * (1 - p) + 26 * split) + Double(i) * middleX * p
      let y = 157 - 35 * (1 - p) + (15 + Double(i) * middleY) * wave(p * 0.25) - 39 * split
      gastricChiefMolecule(x, y, 9)
    }
    gastricChiefMolecule(288, 145, 7.4)
    line(180, 309, 180, 254, 0x56696E, 1.1)
    line(180, 254, 137, 202, 0x56696E, 1.1)
    line(180, 254, 221, 197, 0x56696E, 1.1)
    disc(137, 202, 1.7, 0x56696E); disc(221, 197, 1.7, 0x56696E)
    label("gastric_chief_story_cut_sites", 180, 328, 144)
  }
  private func gastricChiefChain(_ first: Int, _ last: Int, _ dx: Double, _ dy: Double) {
    for i in first..<last { gastricChiefBond(i, dx, dy) }
    for i in first...last {
      let color: UInt32 = i % 2 == 0 ? 0xA8C7A8 : 0xC6D49C
      disc(66 + 20 * Double(i) + dx, GalaxySSIHealthAtlasGastricChiefGeometry.proteinY[i] + dy, 5.4, color, border: 0x397164)
    }
  }
  private func gastricChiefBond(_ i: Int, _ dx: Double, _ dy: Double) {
    let x = 66 + 20 * Double(i) + dx, ys = GalaxySSIHealthAtlasGastricChiefGeometry.proteinY
    line(x, ys[i] + dy, x + 20, ys[i + 1] + dy, 0x397164, 2.7)
  }
}
