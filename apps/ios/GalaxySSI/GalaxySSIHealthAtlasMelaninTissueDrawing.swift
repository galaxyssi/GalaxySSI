import SwiftUI

private typealias MelaninTissueMotion = GalaxySSIHealthAtlasMelaninMotion
private typealias MelaninTissueShapes = GalaxySSIHealthAtlasMelaninShapes

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func melaninTissue(focus: Double?) {
    rounded(24, 272, 336, 302, 10, 0xDDD9E6)
    gradient(Path(roundedRect: CGRect(x: 24, y: 105, width: 312, height: 179), cornerRadius: 9), 104, 284, 0xFFEEDC, 0xEECAC1)
    for row in 0...1 {
      for col in 0...6 {
        let x = Double(27 + col * 46 + row * 10), y = Double(105 + row * 9), right = min(x + 42, 333)
        rounded(x, y, right, y + 7, 3.5, (row + col) % 2 == 0 ? Self.sand : 0xF6DBB1)
        line(x + 3, y + 2, right - 3, y + 2, Self.cream, 1)
      }
    }
    for (index, cell) in MelaninTissueMotion.cells.enumerated() {
      let path = MelaninTissueShapes.wafer(cell)
      gradient(path, 122, 282, 0xFFE9D8, 0xF0BFB8); stroke(path, 0xC78E90, 1.1)
      let nx = cell.x + (index % 2 == 0 ? -3 : 3)
      oval(nx - cell.rx * 0.28, cell.y - cell.ry * 0.30, nx + cell.rx * 0.28, cell.y + cell.ry * 0.40, fill: 0xD1ABD0, border: 0xAD85B1)
    }
    gradient(MelaninTissueShapes.recipient, 142, 220, 0xFFEDDE, 0xF2C3A8); stroke(MelaninTissueShapes.recipient, 0xBB7D82, 1.7)
    melaninNucleus(242, 186, rx: 14, ry: 12)
    if let focus {
      let art = melaninAlpha(Int(31 + 22 * wave(focus - 0.25)))
      art.stroke(MelaninTissueShapes.donor, Self.teal, 21)
      for branch in MelaninTissueShapes.branchPaths { art.stroke(branch, Self.teal, 21) }
    }
    for (index, branch) in MelaninTissueShapes.branchPaths.enumerated() {
      let width = index == 0 ? 11.0 : 8
      stroke(branch, MelaninTissueShapes.membrane, width); stroke(branch, MelaninTissueShapes.branchFill, width - 2.5)
    }
    gradient(MelaninTissueShapes.donor, 227, 282, 0xCEF0DD, 0xA5D3C6); stroke(MelaninTissueShapes.donor, MelaninTissueShapes.membrane, 1.5)
    melaninNucleus(128, 258, rx: 12, ry: 10)
    line(30, 285, 330, 285, 0x9C8099, 2); line(32, 289, 328, 289, 0xF5EDF1, 1.2)
  }
  private func melaninNucleus(_ x: Double, _ y: Double, rx: Double, ry: Double) {
    oval(x - rx, y - ry, x + rx, y + ry, fill: 0xB49AC4, border: 0x876899)
    disc(x - 3, y - 2, 3.1, 0x9070A2); disc(x + 4, y + 3, 2, 0xE6CDE0)
  }
}
