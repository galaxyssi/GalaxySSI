import SwiftUI

private typealias BrainstemFlow = GalaxySSIHealthAtlasBrainstemMotion
private typealias BrainstemFlowInk = GalaxySSIHealthAtlasBrainstemShapes

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func brainstemAirway() {
    stroke(BrainstemFlowInk.bronchi,0xB48676,8); stroke(BrainstemFlowInk.bronchi,0xF1D3B3,5.5)
    let airway = GalaxySSIHealthAtlasSectionLessonView.path(BrainstemFlow.airway,width: 360,height: 360)
    stroke(airway,0xB48676,9); stroke(airway,0xF5DCC0,6.6)
    for y in stride(from: 144, through: 184, by: 7) { line(172,Double(y),178,Double(y),0xC39783,1) }
  }
  func brainstemMotor(step: Int, t: Double) {
    stroke(BrainstemFlowInk.cord,0xA78DB5,8.5); stroke(BrainstemFlowInk.cord,0xE0C7E4,6)
    let left = GalaxySSIHealthAtlasSectionLessonView.path(BrainstemFlow.leftNerve,width: 360,height: 360)
    let right = GalaxySSIHealthAtlasSectionLessonView.path(BrainstemFlow.rightNerve,width: 360,height: 360)
    stroke(left,BrainstemFlowInk.quietNeural,2.2); stroke(right,BrainstemFlowInk.quietNeural,2.2)
    disc(197,145,3.1,Self.cream,border: BrainstemFlowInk.quietNeural)
    if step == 2 {
      let progress = BrainstemFlow.motor(t)
      if let descending = progress.descending { brainstemSignal(BrainstemFlow.descending,progress: descending) }
      if let branch = progress.branch { brainstemSignal(BrainstemFlow.leftNerve,progress: branch); brainstemSignal(BrainstemFlow.rightNerve,progress: branch) }
    }
  }
  private func brainstemSignal(_ route: GalaxySSIHealthAtlasSectionLesson.Route, progress: Double) {
    let end = min(1,max(0,progress)), path = GalaxySSIHealthAtlasSectionLessonView.path(route,width: 360,height: 360)
    if end > 0 { stroke(path.trimmedPath(from: CGFloat(max(0,end - 0.23)),to: CGFloat(end)),BrainstemFlowInk.neural,3.3) }
    at(route,end) { disc($0,$1,4,Self.cream,border: BrainstemFlowInk.neural) }
  }
  func brainstemAirflow(_ t: Double, inward: Bool) {
    for i in 0...2 {
      guard let flow = BrainstemFlow.airflow(t,index: i,inward: inward) else { continue }
      at(BrainstemFlow.airRoute,flow.tail) { x1, y1 in
        at(BrainstemFlow.airRoute,flow.head) { x2, y2 in arrow(x1,y1,x2,y2,BrainstemFlowInk.movingAir) }
      }
    }
  }
}
