import SwiftUI

private typealias PodocyteParticles = GalaxySSIHealthAtlasPodocyteGeometry
private typealias PodocyteFlow = GalaxySSIHealthAtlasPodocyteMotion

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func podocyteBlood(_ f: Double) {
    var local = context; local.clip(to: Path(CGRect(x: PodocyteFlow.left, y: 109, width: PodocyteFlow.right - PodocyteFlow.left, height: 46)))
    let art = copy(local)
    for i in 0...2 { art.podocyteRedCell(PodocyteFlow.bloodX(f,index: i),126 + Double(i % 2) * 4,tilt: i % 2 == 0 ? -13 : 19) }
    for i in 0...3 { art.podocyteProtein(PodocyteFlow.proteinX(f,index: i),140 + Double(i % 2) * 3) }
  }
  func podocyteFiltrate(_ f: Double) {
    arrow(112,111,169,111,PodocyteParticles.vessel); arrow(136,268,136,289,PodocyteParticles.water)
    for i in 0...2 {
      let phases = PodocyteFlow.filtrate(f,index: i)
      at(PodocyteParticles.leftFlow,phases.p) { podocyteWater($0,$1) }
      at(PodocyteParticles.rightFlow,phases.p) { podocyteSolute($0,$1) }
      at(PodocyteParticles.leftFlow,phases.q) { podocyteSolute($0,$1) }
      at(PodocyteParticles.rightFlow,phases.q) { podocyteWater($0,$1) }
    }
  }
  func podocyteRedCell(_ x: Double, _ y: Double, tilt: Double) {
    var local = context; local.translateBy(x: x, y: y); local.rotate(by: .degrees(tilt))
    let art = copy(local)
    art.oval(-11,-5.7,11,5.7,fill: 0xD1838B,border: PodocyteParticles.vessel)
    art.oval(-5.8,-2.2,5.8,2.2,fill: 0xE9AAA6,border: 0xBA707D)
  }
  func podocyteProtein(_ x: Double, _ y: Double) {
    disc(x - 2.2,y + 0.8,2.9,0xC7A05D,border: PodocyteParticles.protein)
    disc(x + 2.3,y + 1.4,2.6,0xD4B071,border: PodocyteParticles.protein)
    disc(x + 0.4,y - 2,2.7,0xE4C487,border: PodocyteParticles.protein)
  }
  func podocyteWater(_ x: Double, _ y: Double) {
    var p = Path(); p.move(to: CGPoint(x: x, y: y - 4.3))
    p.addCurve(to: CGPoint(x: x + 3.4, y: y + 1.3), control1: CGPoint(x: x + 1, y: y - 2), control2: CGPoint(x: x + 3.4, y: y))
    p.addCurve(to: CGPoint(x: x - 3.4, y: y + 1.3), control1: CGPoint(x: x + 3.4, y: y + 5), control2: CGPoint(x: x - 3.4, y: y + 5))
    p.addCurve(to: CGPoint(x: x, y: y - 4.3), control1: CGPoint(x: x - 3.4, y: y), control2: CGPoint(x: x - 1, y: y - 2)); p.closeSubpath()
    fill(p,0x88BED5); stroke(p,PodocyteParticles.water,1.1)
  }
  func podocyteSolute(_ x: Double, _ y: Double) {
    var p = Path(); p.move(to: CGPoint(x: x, y: y - 2.7))
    p.addLine(to: CGPoint(x: x + 2.7, y: y)); p.addLine(to: CGPoint(x: x, y: y + 2.7)); p.addLine(to: CGPoint(x: x - 2.7, y: y)); p.closeSubpath()
    fill(p,PodocyteParticles.solute)
  }
}
