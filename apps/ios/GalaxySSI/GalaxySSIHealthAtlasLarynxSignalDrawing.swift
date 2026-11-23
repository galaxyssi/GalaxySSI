import SwiftUI

private typealias LarynxMotion = GalaxySSIHealthAtlasLarynxMotion
private typealias LarynxSignal = GalaxySSIHealthAtlasLarynxShapes

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func larynxScene(_ frame: GalaxySSIHealthAtlasLarynxMotion, step: Int, t: Double) {
    larynxSuperior(frame.gap); larynxFrontal(frame.gap)
    if frame.outgoing > 0 { larynxAirwayFlow(2 * t, up: true, below: frame.outgoing, above: frame.above) }
    if step == 0 || step == 4 { larynxAirwayFlow(3 * t, up: frame.breath < 0, below: abs(frame.breath), above: abs(frame.breath)) }
    if frame.sound > 0 {
      for i in 0...1 {
        let pulse = LarynxMotion.acoustic(cycle: frame.cycle, index: i, strength: frame.sound)
        var detail = Path(); detail.move(to: CGPoint(x: 180 - pulse.halfWidth, y: pulse.y + 2))
        detail.addQuadCurve(to: CGPoint(x: 180 + pulse.halfWidth, y: pulse.y + 2), control: CGPoint(x: 180, y: pulse.y - 4))
        larynxAlpha(pulse.alpha).stroke(detail, LarynxSignal.pulse, 1.8)
      }
    }
  }
  private func larynxAlpha(_ alpha: Int) -> Self { var local = context; local.opacity *= Double(min(255, max(0, alpha))) / 255; return copy(local) }
  private func larynxAirwayFlow(_ travel: Double, up: Bool, below: Double, above: Double) {
    for i in 0...4 {
      guard let flow = LarynxMotion.airflow(travel: travel, index: i, up: up, below: below, above: above) else { continue }
      let art = larynxAlpha(flow.alpha), x = flow.x, y = flow.y, direction = flow.direction
      art.line(x, y - direction * 4, x, y + direction * 3, LarynxSignal.flow, 1.7)
      art.line(x - 2.8, y, x, y + direction * 3, LarynxSignal.flow, 1.4); art.line(x + 2.8, y, x, y + direction * 3, LarynxSignal.flow, 1.4)
    }
  }
  func larynxLeader(_ x: Double, _ y: Double, _ bendX: Double, _ bendY: Double, _ toX: Double, _ toY: Double) {
    line(x, y, bendX, bendY, LarynxSignal.guide, 1.05); line(bendX, bendY, toX, toY, LarynxSignal.guide, 1.05); disc(toX, toY, 1.6, LarynxSignal.guide)
  }
}
