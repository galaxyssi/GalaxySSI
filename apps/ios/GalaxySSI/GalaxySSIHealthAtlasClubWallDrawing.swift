import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func clubHumanWall(_ cilia: Double) {
    typealias Geometry = GalaxySSIHealthAtlasClubGeometry
    clubWallBed()
    fill(Geometry.film, 0xC4E4E5); stroke(Geometry.filmSurface, 0x649493, 1.4)
    clubCiliatedCell(71, width: 1, phase: cilia)
    clubCiliatedCell(284, width: 1.08, phase: cilia)
    gradient(Geometry.clubCell, 150, 255, 0xF7DFA1, 0xDFAA6A)
    stroke(Geometry.clubCell, 0x815B35, 1.6); stroke(Geometry.apicalLight, 0xFCEAC1, 1.7)
    oval(159, 209, 193, 242, fill: 0xA480AA, border: Self.violet)
    disc(175, 225, 4.3, Self.violet)
    clubGranule(156, 183, 4.3); clubGranule(199, 184, 4.8)
    clubGranule(165, 199, 3.3); clubGranule(209, 199, 3.9)
  }
  func clubWallBed() {
    fill(GalaxySSIHealthAtlasClubGeometry.bed, 0xF2D5BD)
    stroke(GalaxySSIHealthAtlasClubGeometry.bed, 0x945E63, 1.05)
    stroke(GalaxySSIHealthAtlasClubGeometry.bedFibers, 0xC38D7B, 1.1)
  }
  func clubCiliatedCell(_ x: Double, width: Double, phase: Double) {
    var local = context; local.translateBy(x: x, y: 0); local.scaleBy(x: width, y: 1)
    let art = copy(local), cell = GalaxySSIHealthAtlasClubGeometry.ciliatedCell
    art.gradient(cell, 186, 256, 0xD6E9E1, 0xA7C9C3); art.stroke(cell, 0x727477, 1.3)
    art.oval(-13, 208, 12, 238, fill: 0xA480AA, border: Self.violet)
    art.disc(-2, 222, 3.3, Self.violet)
    for i in 0...12 {
      let offset = Double(i - 6), bend = 10 * wave(phase + offset * 0.025) + 2
      art.clubCilium(offset * 6.3, 189 + offset * offset * 0.045, length: 16 - Double(i % 3), bend: bend)
    }
  }
  func clubCilium(_ x: Double, _ y: Double, length: Double, bend: Double) {
    var p = Path()
    p.move(to: CGPoint(x: x, y: y))
    p.addQuadCurve(to: CGPoint(x: x + bend, y: y - length), control: CGPoint(x: x + bend * 0.14, y: y - length * 0.68))
    stroke(p, 0x4D7D76, 1.35)
  }
  func clubGranule(_ x: Double, _ y: Double, _ r: Double) {
    disc(x, y, r, 0xE3AD62, border: 0x996030)
    disc(x - r * 0.15, y - r * 0.12, r * 0.38, 0x996030)
  }
  func clubProtein(_ x: Double, _ y: Double) {
    oval(x - 3.2, y - 2.2, x + 3.2, y + 2.2, fill: 0xE9BF72, border: 0x726047)
  }
}
