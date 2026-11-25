import SwiftUI

private typealias UrineMapMotion = GalaxySSIHealthAtlasUrineMotion
private typealias UrineMapShapes = GalaxySSIHealthAtlasUrineShapes

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func urineOverview(_ t: Double) {
    line(180, 281, 180, 321, Self.coral, 12); line(180, 281, 180, 321, Self.peach, 9); line(180, 285, 180, 321, Self.cream, 3)
    let bladder = UrineMapShapes.bladder(half: 52, top: 219, base: 291, neck: 6)
    fill(bladder, Self.peach); stroke(bladder, Self.coral, 1.4)
    fill(UrineMapShapes.bladder(half: 45, top: 226, base: 287, neck: 2), 0xFFE7B3)
    for side in 0...1 {
      var local = context
      if side == 1 { local.translateBy(x: 360, y: 0); local.scaleBy(x: -1, y: 1) }
      let art = copy(local)
      art.gradient(UrineMapShapes.kidney, 54, 163, 0xF8D2CB, 0xD58C9E); art.stroke(UrineMapShapes.kidney, Self.coral, 1.5)
      art.fill(UrineMapShapes.medulla, 0xF2BAB3); art.stroke(UrineMapShapes.medulla, 0xCB8992, 1)
      let ureter = GalaxySSIHealthAtlasSectionLessonView.path(UrineMapMotion.overviewUreter, width: 360, height: 360)
      art.stroke(ureter, Self.coral, 9); art.stroke(ureter, 0xF6D3BF, 6.5)
      art.stroke(UrineMapShapes.calyces, 0xB8847A, 6); art.stroke(UrineMapShapes.calyces, 0xFFEDC4, 4)
      art.oval(121, 103, 141, 119, fill: 0xFFE4AA, border: 0xB8847A)
      art.urinePulse(UrineMapMotion.pelvisRoute, front: (t * 1.25 + Double(side) * 0.38).truncatingRemainder(dividingBy: 1.15), length: 0.12, width: 3.7)
    }
    urineCallout("urine_route_story_renal_pelvis", 180, 33, 130, 138, 108)
    urineCallout("urine_route_story_ureters", 76, 195, 95, 139, 203)
    urineCallout("urine_route_story_bladder", 278, 236, 95, 224, 248)
    urineCallout("urine_route_story_urethra", 257, 299, 95, 184, 311)
  }
}
