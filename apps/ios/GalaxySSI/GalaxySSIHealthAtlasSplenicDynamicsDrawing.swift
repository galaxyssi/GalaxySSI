import SwiftUI

private typealias SplenicFlow = GalaxySSIHealthAtlasSplenicMotion
private typealias SplenicCapture = GalaxySSIHealthAtlasSplenicShapes

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func splenicDynamics(step: Int, t: Double) {
    if step != 1 { at(SplenicFlow.sinusRun,0.32 + 0.51 * t) { splenicRedCell($0,$1 - 5,scale: 0.60,angle: -10) } }
    switch step {
    case 0:
      splenicMacrophage(0)
      at(SplenicFlow.approach,SplenicFlow.ease(t)) { splenicRedCell($0,$1,scale: 1,angle: 12 * (1 - t)) }
    case 1:
      splenicMacrophage(0); splenicPassingCell(SplenicFlow.mix(128,307,SplenicFlow.ease(t)))
    case 2:
      splenicMacrophage(0)
      let f = SplenicFlow.ease(t / 0.67)
      splenicRedCell(SplenicFlow.mix(116,SplenicFlow.retainedX,f),SplenicFlow.slitY - 10 * (1 - f),
        scale: 0.96,angle: SplenicFlow.mix(-13,0,f),lessFlexible: true)
    case 3: splenicEngulf(t)
    default: splenicRecycle(t)
    }
  }
  private func splenicEngulf(_ t: Double) {
    let frame = SplenicFlow.capture(t)
    splenicMacrophage(frame.extensionAmount)
    splenicRedCell(frame.x,frame.y,scale: frame.scale,angle: frame.angle,lessFlexible: true)
    if t > 0.43 {
      stroke(SplenicCapture.arc(frame.x - 22 - frame.spread,frame.y - 14 - frame.spread,
        frame.x + 22 + frame.spread,frame.y + 14 + frame.spread,start: 100,sweep: frame.sweep),0xF5E5BD,2.5)
    }
  }
  private func splenicRecycle(_ t: Double) {
    splenicMacrophage(0)
    let breakdown = SplenicFlow.ease(t / 0.30)
    if breakdown < 1 {
      splenicRedCell(109,259,scale: 0.85 * (1 - breakdown),angle: -18,lessFlexible: true)
      let ring = Path(ellipseIn: CGRect(x: 87 + 14 * breakdown, y: 245 + 8 * breakdown, width: 44 - 28 * breakdown, height: 28 - 16 * breakdown))
      stroke(ring,0xF5E5BD,2.5 * (1 - breakdown))
    }
    for i in 0...2 {
      let reuse = SplenicFlow.reuse(t,index: i)
      if reuse.size > 0 { at(SplenicFlow.reuseRun,reuse.fraction) { splenicIron($0,$1,scale: reuse.size) } }
    }
  }
}
