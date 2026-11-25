import SwiftUI

private typealias FibroblastMatrix = GalaxySSIHealthAtlasFibroblastMotion
private typealias FibroblastMatrixInk = GalaxySSIHealthAtlasFibroblastShapes

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func fibroblastMatrix(step: Int, t: Double) {
    let turnover = FibroblastMatrix.turnover(step: step,t: t)
    for fiber in FibroblastMatrix.scaffold { fibroblastFiber(fibroblastPath(fiber),color: FibroblastMatrixInk.collagen,width: 2.7) }
    fibroblastFiber(fibroblastPath(FibroblastMatrix.olderFiber),color: FibroblastMatrixInk.collagen,width: 2.7,alpha: 1 - turnover)
    if turnover > 0 { fibroblastSegment(fibroblastPath(FibroblastMatrix.renewedFiber),start: 0,end: turnover,color: FibroblastMatrixInk.collagen,width: 2.7,alpha: turnover) }
    if step == 0 {
      for index in [1,6] {
        let head = t * 1.25
        fibroblastSegment(fibroblastPath(FibroblastMatrix.scaffold[index]),start: head - 0.25,end: head,color: 0xFFE0A9,width: 3.2)
      }
    }
    if step == 1 { fibroblastRepairCue(t) }
    if step >= 2 {
      let arrangement = FibroblastMatrix.arrangement(step: step,t: t)
      for (i, shapes) in FibroblastMatrix.outgoing.enumerated() {
        let growth = FibroblastMatrix.growth(step: step,t: t,index: i)
        guard growth > 0 else { continue }
        let fiber = shapes.from.interpolated(to: shapes.to,fraction: arrangement), path = fibroblastPath(fiber)
        if growth == 1 { fibroblastFiber(path,color: FibroblastMatrixInk.newFiber,width: 2.7) }
        else { fibroblastSegment(path,start: 0,end: growth,color: FibroblastMatrixInk.newFiber,width: 2.7) }
      }
    }
  }
  private func fibroblastRepairCue(_ t: Double) {
    for i in 0...1 {
      guard let cue = FibroblastMatrix.repairCue(t,index: i) else { continue }
      let circle = Path(ellipseIn: CGRect(x: 112 - cue.radius, y: 174 - cue.radius, width: 2 * cue.radius, height: 2 * cue.radius))
      fibroblastAlpha(cue.alpha).stroke(circle,FibroblastMatrixInk.cue,2)
    }
    let focus = FibroblastMatrix.focus(t)
    if focus > 0 { fibroblastAlpha(Int(125 * focus)).stroke(FibroblastMatrixInk.cell,Self.violet,4) }
  }
  private func fibroblastPath(_ fiber: FibroblastMatrix.Fiber) -> Path {
    GalaxySSIHealthAtlasSectionLessonView.path(fiber.route,width: 360,height: 360)
  }
  private func fibroblastAlpha(_ alpha: Int) -> Self {
    var local = context; local.opacity *= Double(min(255,max(0,alpha))) / 255
    return copy(local)
  }
  private func fibroblastFiber(_ path: Path, color: UInt32, width: Double, alpha: Double = 1) {
    guard alpha > 0 else { return }
    let art = fibroblastAlpha(Int(255 * alpha))
    art.stroke(path,0xFFF4E9,width + 2.3); art.stroke(path,color,width)
  }
  private func fibroblastSegment(_ path: Path, start: Double, end: Double, color: UInt32, width: Double, alpha: Double = 1) {
    let from = min(1,max(0,start)), to = min(1,max(0,end))
    guard to > from else { return }
    fibroblastFiber(path.trimmedPath(from: CGFloat(from),to: CGFloat(to)),color: color,width: width,alpha: alpha)
  }
}
