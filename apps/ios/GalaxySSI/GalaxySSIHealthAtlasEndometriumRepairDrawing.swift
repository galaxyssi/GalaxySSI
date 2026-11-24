import SwiftUI

private typealias EndometriumRepair = GalaxySSIHealthAtlasEndometriumMotion
private typealias EndometriumRepairInk = GalaxySSIHealthAtlasEndometriumGeometry

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func endometriumOutside(_ tissue: Path) -> Self {
    var outside = Path(CGRect(x: 0, y: 0, width: 360, height: 360)); outside.addPath(tissue)
    var local = context; local.clip(to: outside,style: FillStyle(eoFill: true))
    return copy(local)
  }
  func endometriumFragments(_ t: Double, tissue: Path) {
    let art = endometriumOutside(tissue)
    for i in 0...3 {
      guard let fragment = EndometriumRepair.fragment(t,index: i) else { continue }
      let x = fragment.x, y = fragment.y
      var path = Path(); path.move(to: CGPoint(x: x - 7, y: y))
      path.addQuadCurve(to: CGPoint(x: x + 6, y: y - 3), control: CGPoint(x: x - 2, y: y - 7))
      path.addQuadCurve(to: CGPoint(x: x + 1, y: y + 4), control: CGPoint(x: x + 9, y: y + 3))
      path.addQuadCurve(to: CGPoint(x: x - 7, y: y), control: CGPoint(x: x - 5, y: y + 6)); path.closeSubpath()
      var local = art.context; local.opacity *= Double(fragment.alpha) / 255
      copy(local).fill(path,0xBB788C)
    }
  }
  func endometriumRepair(_ t: Double) {
    let reach = 5 + 16 * EndometriumRepair.ramp(t,from: 0.06,to: 0.82)
    line(EndometriumRepair.left + 2,EndometriumRepair.basal - 1,EndometriumRepair.left + reach,EndometriumRepair.basal - 1,EndometriumRepairInk.lining,4.3)
    for (i, x) in EndometriumRepair.glandSites.enumerated() { endometriumRepairEdge(x,radius: EndometriumRepair.repairRadius(t,index: i)) }
  }
  func endometriumRepairEdge(_ x: Double, radius: Double) {
    guard radius > 3 else { return }
    line(max(EndometriumRepair.left + 2,x - radius),EndometriumRepair.basal - 1,x - 3,EndometriumRepair.basal - 1,EndometriumRepairInk.lining,4.3)
    line(x + 3,EndometriumRepair.basal - 1,min(EndometriumRepair.right - 2,x + radius),EndometriumRepair.basal - 1,EndometriumRepairInk.lining,4.3)
  }
}
