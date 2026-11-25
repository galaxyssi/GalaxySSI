import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func accessoryGlandScene(_ step: Int, _ t: Double) {
    let routes = GalaxySSIHealthAtlasAccessoryGlandRoutes.self
    var local = context; local.translateBy(x: 0, y: 40)
    let art = copy(local)
    local.draw(Image("HealthAtlasRegionalAccessoryGlandRoutingCutaway"), in: CGRect(x: 0, y: 0, width: 360, height: 280))
    for (index, track) in routes.tracks.enumerated() {
      let active = routes.active(index, step: step), color: UInt32 = active ? routes.colors[index] : 0x786C74
      var mirrored = local
      mirrored.translateBy(x: 180, y: 0); mirrored.scaleBy(x: -1, y: 1); mirrored.translateBy(x: -180, y: 0)
      let pair = [art, copy(mirrored)]
      for pairArt in pair { pairArt.stroke(track.path, color, active ? 4 : 3) }
      for pairArt in pair { pairArt.stroke(track.path, 0xF9ECDD, 1.5) }
    }
    switch step {
    case 1: art.accessoryGlandFlow(routes.vesicle, 0x985944, t)
    case 2: art.accessoryGlandFlow(routes.ejaculatory, 0x6B5683, t)
    case 3:
      art.accessoryGlandFlow(routes.prostateUpper, 0x426E8B, t)
      art.accessoryGlandFlow(routes.prostateLower, 0x426E8B, t, delay: 0.17)
    case 4: art.accessoryGlandFlow(routes.bulb, 0x2A746D, t)
    default: break
    }
    let labels = GalaxySSIHealthAtlasAccessoryGlandLabels.forStep(step)
    let landmark = step == 0 ? min(labels.count - 1, max(0, Int(t * Double(labels.count)))) : -1
    for (index, callout) in labels.enumerated() { art.accessoryGlandAnnotate(callout, active: index == landmark) }
  }
  private func accessoryGlandFlow(_ track: GalaxySSIHealthAtlasRegionalTrack, _ color: UInt32, _ t: Double, delay: Double = 0) {
    let p = GalaxySSIHealthAtlasAccessoryGlandRoutes.progress(t, delay: delay)
    for side in 0..<2 {
      var local = context
      if side == 1 { local.translateBy(x: 180, y: 0); local.scaleBy(x: -1, y: 1); local.translateBy(x: -180, y: 0) }
      let art = copy(local)
      if p > 0 { art.stroke(track.path.trimmedPath(from: max(0, p - 0.22), to: p), color, 2.8) }
      art.at(track.route, p) { x, y in art.disc(x, y, 3.15, Self.cream, border: color) }
    }
  }
  private func accessoryGlandAnnotate(_ callout: GalaxySSIHealthAtlasAccessoryGlandLabels.Callout, active: Bool) {
    let end = callout.left ? 107.0 : 246, bend = callout.x + (callout.left ? -9 : 9)
    let color: UInt32 = active ? Self.teal : 0x5F7375
    line(callout.x, callout.y, bend, callout.row, color, 1)
    line(bend, callout.row, end, callout.row, color, 1)
    if active { disc(callout.x, callout.y, 5, 0x3A337B6D, border: Self.teal) }
    disc(callout.x, callout.y, 2, Self.cream, border: color)
    label("accessory_gland_routing_" + callout.key, callout.left ? 64 : 293, callout.row - 5, callout.left ? 116 : 120)
  }
}
