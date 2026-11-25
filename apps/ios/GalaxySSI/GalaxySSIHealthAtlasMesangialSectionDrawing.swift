import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func mesangialSection(_ tension: Double) {
    typealias Geometry = GalaxySSIHealthAtlasMesangialGeometry
    typealias Motion = GalaxySSIHealthAtlasMesangialMotion
    let edge = tension == 0 ? Geometry.relaxedOutline : Geometry.sectionOutline(tension)
    gradient(edge, 150, 277, 0xF4E5BB, 0xDEC29A); stroke(edge, 0x927344, 3.3)
    var local = context
    local.translateBy(x: Motion.loopHinge, y: 208)
    local.scaleBy(x: Motion.loopScale(tension), y: 1)
    local.translateBy(x: -Motion.loopHinge, y: -208)
    copy(local).mesangialLumen(Geometry.leftLumen, 69, 184)
    mesangialLumen(Geometry.rightLumen, 195, 180)
    for fiber in GalaxySSIHealthAtlasMesangialRoutes.fibers { stroke(fiber.path, 0xB39A70, 1.7) }
    if tension > 0 { stroke(Geometry.relaxedEdge, 0xAEAAA1, 1.3) }
  }
  private func mesangialLumen(_ path: Path, _ x: Double, _ y: Double) {
    gradient(path, 140, 278, 0xFFEDE2, 0xEFBDB3)
    stroke(path, 0xCE8C90, 4.2); stroke(path, 0x995E66, 1.1)
    mesangialRedCell(x, y, -26)
    mesangialRedCell(x + 14, y + 25, 32)
    mesangialRedCell(x - 5, y + 49, -9)
  }
  private func mesangialRedCell(_ x: Double, _ y: Double, _ tilt: Double) {
    var local = context
    local.translateBy(x: x, y: y); local.rotate(by: .degrees(tilt))
    let art = copy(local)
    art.oval(-10, -5, 10, 5, fill: 0xCB7B82, border: 0x995E66)
    art.oval(-5.5, -2, 5.5, 2, fill: 0xE6A29E, border: 0xB96D77)
  }
}
