import SwiftUI

private typealias PodocyteWall = GalaxySSIHealthAtlasPodocyteGeometry
private typealias PodocyteContour = GalaxySSIHealthAtlasPodocyteMotion

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func podocyteGlomerulus(_ f: Double?) {
    line(94,75,PodocyteContour.left,111,0xA2ABA1,1); line(107,72,PodocyteContour.right,111,0xA2ABA1,1)
    fill(PodocyteWall.capsule,0xF5F5E9); stroke(PodocyteWall.capsule,0x93A49B,1.5)
    stroke(PodocyteWall.tuftBranch,PodocyteWall.vessel,7); stroke(PodocyteWall.tuftBranch,0xE6ACAC,4.4)
    stroke(PodocyteWall.tuft,PodocyteWall.vessel,8.5); stroke(PodocyteWall.tuft,0xEAB5B4,5.7)
    let radius = f.map { 11 + 2 * wave($0 - 0.25) } ?? 11
    stroke(Path(ellipseIn: CGRect(x: 102 - radius, y: 67 - radius, width: 2 * radius, height: 2 * radius)),0x875267,f == nil ? 1.2 : 1.7)
    if let f {
      for i in 0...2 { at(PodocyteWall.tuftFlow,(f * 0.72 + Double(i) * 0.33).truncatingRemainder(dividingBy: 1)) { disc($0,$1,2.4,0x9C3F51) } }
    }
    line(135,49,110,61,PodocyteWall.leader,1); label("podocyte_story_label_glomerulus",177,45,99)
  }
  func podocyteSpaces() {
    context.fill(PodocyteWall.blood,with: .linearGradient(Gradient(colors: [Self.color(0xF0BBB5).opacity(0),Self.color(0xF4CBC2)]),
      startPoint: CGPoint(x: 0, y: 111),endPoint: CGPoint(x: 0, y: 176)))
    context.fill(PodocyteWall.filtrateSpace,with: .linearGradient(Gradient(colors: [Self.color(0xCCDFE2),Self.color(0xDDEBED).opacity(0)]),
      startPoint: CGPoint(x: 0, y: 176),endPoint: CGPoint(x: 0, y: 302)))
  }
  func podocyteWall() {
    gradient(PodocyteWall.basement,157,188,0xF6E7C3,0xDBC096)
    for i in 0...25 {
      let x = PodocyteContour.left + 4 + Double(i) * 8, y = PodocyteContour.wallY(x), offset = i % 2 == 0 ? 0.0 : 2.0
      line(x,y + 4 + offset,x + 4,y + 7 + offset,0xBFA681,1); line(x + 3,y + 10,x + 7,y + 8,0xBFA681,0.9)
    }
    stroke(PodocyteWall.basement,PodocyteWall.matrix,1.25)
    for segment in PodocyteWall.endothelium {
      gradient(segment,136,173,0xFBDDD1,0xD38F94); stroke(segment,PodocyteWall.endo,1)
    }
    let y = PodocyteContour.endoY(81)
    oval(73,y + 3,89,y + 10,fill: 0xB16D80,border: 0x874E62)
    gradient(PodocyteWall.podocyte,185,257,0xC6B2D6,0xE5D7ED); stroke(PodocyteWall.podocyte,PodocyteWall.footInk,1.45)
    oval(110,235,140,251,fill: 0xAC8ABD,border: PodocyteWall.footInk); oval(119,240,126,245,fill: 0x856397,border: PodocyteWall.footInk)
    for (i, x) in PodocyteContour.feet.enumerated() {
      var local = context; local.translateBy(x: x, y: PodocyteContour.footY(x))
      let art = copy(local), attached = i % 2 == 1
      art.fill(PodocyteWall.foot,attached ? 0xCDB8DC : 0xADC9BF); art.stroke(PodocyteWall.foot,attached ? PodocyteWall.footInk : PodocyteWall.neighbor,1.15)
    }
    for x in PodocyteContour.slits { podocyteDiaphragm(x,color: PodocyteWall.slit,weight: 1.35) }
  }
  func podocyteDiaphragm(_ x: Double, color: UInt32, weight: Double) {
    line(x - 4.6,PodocyteContour.footY(x - 4.6) + 3.5,x + 4.6,PodocyteContour.footY(x + 4.6) + 3.5,color,weight)
  }
}
