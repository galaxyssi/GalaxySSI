import SwiftUI

private typealias ChondrocyteMarkers = GalaxySSIHealthAtlasChondrocyteGeometry
private typealias ChondrocyteCompression = GalaxySSIHealthAtlasChondrocyteMotion

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func chondrocyteAlpha(_ alpha: Int) -> Self {
    var local = context; local.opacity *= Double(min(255,max(0,alpha))) / 255
    return copy(local)
  }
  func chondrocyteWaterMark(_ x: Double, _ y: Double, length: Double, alpha: Int) {
    var detail = Path(); detail.move(to: CGPoint(x: x - length * 0.5, y: y + 1))
    detail.addQuadCurve(to: CGPoint(x: x + length * 0.12, y: y), control: CGPoint(x: x - length * 0.19, y: y - 3))
    detail.addQuadCurve(to: CGPoint(x: x + length * 0.5, y: y - 1), control: CGPoint(x: x + length * 0.28, y: y + 1.5))
    chondrocyteAlpha(alpha).stroke(detail,ChondrocyteMarkers.water,1.65)
  }
  func chondrocyteBrush(_ x: Double, _ y: Double, angle: Double, scale: Double, color: UInt32) {
    var local = context; local.translateBy(x: x, y: y); local.rotate(by: .degrees(angle)); local.scaleBy(x: scale, y: scale)
    var detail = Path(); detail.move(to: .zero); detail.addQuadCurve(to: CGPoint(x: 0, y: -24), control: CGPoint(x: 2, y: -11))
    for i in 0...4 {
      let yy = -5 - Double(i) * 4, width = i == 4 ? 4.0 : 7.0
      detail.move(to: CGPoint(x: 1, y: yy)); detail.addQuadCurve(to: CGPoint(x: -width, y: yy - 4), control: CGPoint(x: -3, y: yy))
      detail.move(to: CGPoint(x: 1, y: yy - 1)); detail.addQuadCurve(to: CGPoint(x: width + 1, y: yy - 5), control: CGPoint(x: 5, y: yy - 1))
    }
    let art = copy(local); art.stroke(detail,0xF9ECD2,3.2); art.stroke(detail,color,1.45)
  }
  func chondrocyteCompression(_ frame: GalaxySSIHealthAtlasChondrocyteMotion) {
    guard frame.compressionAlpha > 0 else { return }
    let art = chondrocyteAlpha(frame.compressionAlpha)
    for x in [46.0,313] {
      let top = ChondrocyteCompression.mappedY(94,scale: frame.scaleY) - 3, base = ChondrocyteCompression.mappedY(260,scale: frame.scaleY) + 3
      let length = 13 + 5 * frame.squeeze
      art.arrow(x,top - length,x,top,0x87532E); art.arrow(x,base + length,x,base,0x87532E)
    }
  }
}
