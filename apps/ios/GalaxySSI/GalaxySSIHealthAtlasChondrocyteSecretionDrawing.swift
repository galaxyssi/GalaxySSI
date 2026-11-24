import SwiftUI

private typealias ChondrocyteSecretion = GalaxySSIHealthAtlasChondrocyteGeometry
private typealias ChondrocyteSecretionTime = GalaxySSIHealthAtlasChondrocyteMotion

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func chondrocyteZones(_ t: Double) {
    for (index, contour) in ChondrocyteSecretion.focusContours.enumerated() {
      let head = ChondrocyteSecretionTime.zoneHead(t,index: index), color: UInt32 = index == 3 ? ChondrocyteSecretion.collagen : 0x286E63
      chondrocyteRun(contour,from: head - 0.34,to: head,color: 0xEAFFF8E8,width: 5.8)
      chondrocyteRun(contour,from: head - 0.34,to: head,color: color,width: 3.2)
    }
  }
  func chondrocyteCollagen(_ t: Double) {
    for i in ChondrocyteSecretion.collagenRoutes.indices {
      let ride = ChondrocyteSecretionTime.collagenRide(t,index: i)
      if ride > 0 && ride < 1, let sample = GalaxySSIHealthAtlasFunctionPath.sample(ChondrocyteSecretion.collagenRoutes[i],position: ride,width: 360,height: 360) {
        let x = Double(sample.point.x), y = Double(sample.point.y), dx = Double(sample.direction.dx) * 4.5, dy = Double(sample.direction.dy) * 4.5
        line(x - dx,y - dy,x + dx,y + dy,Self.cream,5.8); line(x - dx,y - dy,x + dx,y + dy,ChondrocyteSecretion.collagen,2.8)
      }
      let growth = ChondrocyteSecretionTime.collagenGrowth(t,index: i), path = ChondrocyteSecretion.path(ChondrocyteSecretion.collagenJoins[i])
      chondrocyteRun(path,from: 0,to: growth,color: Self.cream,width: 4.5)
      chondrocyteRun(path,from: 0,to: growth,color: ChondrocyteSecretion.collagen,width: 2.3)
    }
  }
  func chondrocyteAggrecan(_ t: Double) {
    stroke(ChondrocyteSecretion.path(ChondrocyteSecretion.carrier),0xA28864,1.5)
    for (index, deposit) in ChondrocyteSecretion.deposits.enumerated() {
      let f = ChondrocyteSecretionTime.deposit(t,index: index)
      guard f > 0 else { continue }
      if f == 1 { chondrocyteBrush(deposit.x,deposit.y,angle: deposit.angle,scale: 1,color: ChondrocyteSecretion.aggrecan) }
      else if let sample = GalaxySSIHealthAtlasFunctionPath.sample(deposit.route,position: f,width: 360,height: 360) {
        chondrocyteBrush(Double(sample.point.x),Double(sample.point.y),angle: -62 + (deposit.angle + 62) * f,scale: 0.55 + 0.45 * f,color: ChondrocyteSecretion.aggrecan)
      }
    }
  }
  private func chondrocyteRun(_ path: Path, from: Double, to: Double, color: UInt32, width: Double) {
    guard to > 0, from < 1, from < to else { return }
    let start = min(1,max(0,from)), end = min(1,max(0,to))
    if end > start { stroke(path.trimmedPath(from: CGFloat(start),to: CGFloat(end)),color,width) }
  }
}
