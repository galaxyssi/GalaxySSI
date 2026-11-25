import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func clubLocate(_ t: Double) {
    typealias Geometry = GalaxySSIHealthAtlasClubGeometry
    gradient(Geometry.branch, 55, 217, 0xF1C9B0, 0xBA787E)
    stroke(Geometry.branch, 0x945E63, 1.7); stroke(Geometry.branchFibers, 0xAB7572, 1.5)
    var local = context; local.translateBy(x: 150, y: 184); local.scaleBy(x: 1, y: 0.92)
    let art = copy(local)
    art.disc(0, 0, 101, 0xF2D5BD, border: 0x945E63)
    art.disc(0, 0, 93, 0xC68585, border: 0x945E63)
    art.stroke(Path(ellipseIn: CGRect(x: -87, y: -87, width: 174, height: 174)), 0xE2A399, 1.4)
    art.disc(0, 0, 80, 0xF2D5BD, border: 0x945E63)
    art.disc(0, 0, 74, 0xD1E4DB, border: 0x649493)
    art.disc(0, 0, 54, 0xE9F4F1)
    for i in 0...15 {
      var rotated = local; rotated.rotate(by: .degrees(Double(i) * 22.5))
      copy(rotated).clubRimCell(Geometry.clubPositions.contains(i))
    }
    let scan = GalaxySSIHealthAtlasClubMotion.locate(t)
    let start = 166 - 91 * scan
    var arc = Path()
    arc.addArc(center: .zero, radius: 41, startAngle: .degrees(start), endAngle: .degrees(166 - 91 * scan + 30), clockwise: false)
    art.stroke(arc, 0x815B35, 2.2)
  }
  private func clubRimCell(_ club: Bool) {
    typealias Geometry = GalaxySSIHealthAtlasClubGeometry
    let edge: UInt32 = club ? 0x815B35 : 0x4D7D76, cell = club ? Geometry.rimClub : Geometry.rimCiliated
    fill(cell, club ? 0xECC47C : 0xB3D1C8); stroke(cell, edge, 0.85)
    oval(-4, 63, 4, 70, fill: 0xA480AA, border: edge)
    if club {
      disc(-3, 54, 1.5, 0x996030); disc(4, 56, 1.5, 0x996030)
    } else {
      for i in -2...2 { line(Double(i) * 3.5, 55, Double(i) * 3 + 1.5, 50, edge, 0.9) }
    }
  }
}
