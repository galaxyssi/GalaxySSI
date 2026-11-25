import SwiftUI

private typealias AdrenalPrimitives = GalaxySSIHealthAtlasAdrenalGeometry
private typealias AdrenalParticle = GalaxySSIHealthAtlasAdrenalMotion

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func adrenalAlpha(_ value: Double) -> Self {
    var local = context; local.opacity *= Double(AdrenalParticle.alpha(value)) / 255
    return copy(local)
  }
  func adrenalCellTissue(_ path: Path) {
    gradient(path,96,260,0xFFE7D3,0xE9B4AA); stroke(path,AdrenalPrimitives.cellInk,1.7)
  }
  func adrenalNucleus(_ x: Double, _ y: Double, rx: Double, ry: Double) {
    oval(x - rx,y - ry,x + rx,y + ry,fill: 0xD6B3C9,border: 0xA37999)
    disc(x - rx * 0.23,y + ry * 0.12,ry * 0.24,0xAA7F9D)
  }
  func adrenalVesicle(_ x: Double, _ y: Double, size: Double) {
    disc(x,y,size,0xF1D7DD,border: 0xA57492); adrenalHormone(x,y,size: size * 0.45)
  }
  func adrenalHormone(_ x: Double, _ y: Double, size: Double, alpha: Double = 1) {
    guard alpha > 0 else { return }
    var local = adrenalAlpha(alpha).context
    local.translateBy(x: x, y: y); local.rotate(by: .degrees(45))
    copy(local).fill(Path(CGRect(x: -size * 0.7, y: -size * 0.7, width: size * 1.4, height: size * 1.4)),AdrenalPrimitives.cargo)
  }
  func adrenalVessel(_ path: Path, width: Double) {
    stroke(path,AdrenalPrimitives.vesselInk,width); stroke(path,0xD99AA2,width - 2.6); stroke(path,0xF4C4C4,width - 9)
  }
  func adrenalBloodCells(_ route: GalaxySSIHealthAtlasSectionLesson.Route, phase: Double) {
    for i in 0...4 {
      let blood = AdrenalParticle.blood(phase: phase,index: i)
      at(route,blood.phase) { x, center in
        let y = center + 8 * wave(Double(i) * 0.37), art = adrenalAlpha(blood.alpha)
        art.oval(x - 9,y - 4,x + 9,y + 4,fill: 0xCE7F88,border: AdrenalPrimitives.vesselInk)
        art.line(x - 3,y,x + 3,y,0xEBB1B4,1.3)
      }
    }
  }
  func adrenalLeader(_ key: String, _ x: Double, _ y: Double, _ width: Double, _ tx: Double, _ ty: Double) {
    line(x,ty > y ? y + 5 : y - 15,tx,ty,AdrenalPrimitives.guide,1)
    disc(tx,ty,2,AdrenalPrimitives.guide); label(key,x,y,width)
  }
}
