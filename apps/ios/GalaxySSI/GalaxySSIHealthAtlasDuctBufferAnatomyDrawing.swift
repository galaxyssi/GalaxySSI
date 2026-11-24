import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func ductBufferOrient(_ t: Double) {
    typealias Geometry = GalaxySSIHealthAtlasDuctBufferGeometry
    ductBufferFilled(Geometry.lobule, 0xF7E4D4, 0xCFA797)
    for branch in Geometry.lobuleBranches { ductBufferTube(branch, 15, 9) }
    ductBufferTube(Geometry.collecting, 22, 14)
    ductBufferAcinus(85, 107, 0.86); ductBufferAcinus(86, 180, 1); ductBufferAcinus(93, 254, 0.87)
    let p = GalaxySSIHealthAtlasDuctBufferMotion.orient(t)
    for i in 0...3 {
      let f = p - Double(i) * 0.045
      if f >= 0 { at(GalaxySSIHealthAtlasDuctBufferRoutes.orientationTrack.route, f) { x, y in disc(x, y, 2.6, 0xA66539, border: Self.cream) } }
    }
  }
  private func ductBufferAcinus(_ x: Double, _ y: Double, _ scale: Double) {
    var local = context; local.translateBy(x: x, y: y); local.scaleBy(x: scale, y: scale)
    for i in 1...5 {
      var rotated = local; rotated.rotate(by: .degrees(Double(i) * 60))
      let art = copy(rotated), wedge = GalaxySSIHealthAtlasDuctBufferGeometry.acinarWedge
      art.gradient(wedge, -17, 17, 0xF6C9B4, 0xD99AA1); art.stroke(wedge, 0x975E64, 1.2)
      art.oval(25, -5, 34, 5, fill: 0xA67F9C, border: 0x855871)
      art.disc(13, -1, 1.5, 0xA66539); art.disc(17, 2, 1.4, 0xA66539)
    }
    copy(local).disc(0, 0, 6, 0xD8EEE8, border: 0x547C7B)
  }
  func ductBufferDeliver(_ t: Double) {
    typealias Geometry = GalaxySSIHealthAtlasDuctBufferGeometry
    ductBufferBowel(Geometry.duodenum, 48)
    for i in 0...3 {
      let y = 129 + 23 * Double(i)
      line(316, y - 3, 309 - Double(i), y + 2, 0x975E64, 1.1)
    }
    gradient(Geometry.pancreas, 109, 235, 0xF6D4AA, 0xD79A84); stroke(Geometry.pancreas, 0x975E64, 1.2)
    stroke(Geometry.organDetails, 0xBF877B, 1.25)
    ductBufferTube(Geometry.organBranches, 5, 2.5); ductBufferTube(Geometry.mainDuct, 11, 7)
    disc(298, 185, 3.4, 0xD8EEE8, border: 0x547C7B)
    let p = GalaxySSIHealthAtlasDuctBufferMotion.delivery(t)
    for i in 0...4 {
      let f = 0.12 + 0.87 * p - Double(i) * 0.043
      if f >= 0 {
        at(GalaxySSIHealthAtlasDuctBufferRoutes.deliveryTrack.route, f) { x, y in
          if i == 2 { disc(x, y, 2.1, 0xA66539, border: Self.cream) }
          else { ductBufferFluidMark(x, y, scale: 0.74) }
        }
      }
    }
  }
}
