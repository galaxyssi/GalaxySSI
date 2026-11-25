import SwiftUI

private typealias SplenicCells = GalaxySSIHealthAtlasSplenicShapes
private typealias SplenicDeformation = GalaxySSIHealthAtlasSplenicMotion

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func splenicPassingCell(_ x: Double) {
    guard SplenicDeformation.pinch(x) > 0 else { splenicRedCell(x,SplenicDeformation.slitY,scale: 1,angle: 0); return }
    var local = context; local.translateBy(x: x, y: SplenicDeformation.slitY)
    let art = copy(local)
    var outline = Path()
    for (index, point) in SplenicDeformation.passingPoints(x).enumerated() {
      if index == 0 { outline.move(to: CGPoint(x: point.x, y: point.y)) } else { outline.addLine(to: CGPoint(x: point.x, y: point.y)) }
    }
    outline.closeSubpath(); art.gradient(outline,-14,14,0xFFB0AB,0xD56C79); art.stroke(outline,SplenicCells.rose,1.3)
    let centerHeight = SplenicDeformation.centerHeight(x)
    art.oval(-10,-centerHeight,10,centerHeight,top: -7,bottom: 6,from: 0xC77784,to: 0xF1A8AA,border: 0xD48E94)
  }
  func splenicMacrophage(_ extensionAmount: Double) {
    let path = SplenicCells.macrophage(extensionAmount)
    gradient(path,226,300,0xEDDFB7,0xD9B680); stroke(path,SplenicCells.iron,1.5)
    oval(72,254,93,275,fill: 0xB79AB1,border: SplenicCells.plum)
    disc(80,261,2.7,SplenicCells.plum); disc(113,280,3.2,0xE9CA93,border: SplenicCells.iron)
    disc(122,273,2.4,0xEDD5A5,border: SplenicCells.iron)
  }
  func splenicRedCell(_ x: Double, _ y: Double, scale: Double, angle: Double, lessFlexible: Bool = false) {
    var local = context; local.translateBy(x: x, y: y); local.rotate(by: .degrees(angle)); local.scaleBy(x: scale, y: scale)
    let art = copy(local), halfHeight = lessFlexible ? 14.0 : 13.0
    art.oval(-22,-halfHeight,22,halfHeight,top: -14,bottom: 14,
      from: lessFlexible ? 0xE8A8B5 : 0xFFB0AB,to: lessFlexible ? 0xAD627D : 0xD56C79,border: lessFlexible ? SplenicCells.plum : SplenicCells.rose)
    art.oval(-10,-5.5,10,5.5,top: -7,bottom: 6,from: 0xC77784,to: 0xF1A8AA,border: 0xCB8090)
    art.stroke(SplenicCells.arc(-18,-10,18,10,start: 196,sweep: 119),0xFFC7BE,1.4)
  }
  func splenicIron(_ x: Double, _ y: Double, scale: Double) {
    disc(x,y,5 * scale,0xF3CD7D,border: SplenicCells.iron)
    disc(x - scale,y - scale,1.5 * scale,0xFFEFD1)
  }
}
