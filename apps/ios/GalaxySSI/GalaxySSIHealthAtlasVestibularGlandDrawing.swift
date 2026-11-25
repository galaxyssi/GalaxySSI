import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func vestibularGlandScene(_ step: Int, _ t: Double) {
    switch step {
    case 0: vestibularGlandLocation(t, flow: false)
    case 1: vestibularGlandMicro(t, collecting: false)
    case 2: vestibularGlandMicro(t, collecting: true)
    default: vestibularGlandLocation(t, flow: true)
    }
  }
  private func vestibularGlandLocation(_ t: Double, flow: Bool) {
    let g = GalaxySSIHealthAtlasVestibularGlandGeometry.self
    context.draw(Image("HealthAtlasRegionalGreaterVestibularGlandDucts"), in: CGRect(x: 0, y: 28, width: 360, height: 280))
    if flow {
      vestibularGlandOutlet(g.leftOutletTrack, t)
      vestibularGlandOutlet(g.rightOutletTrack, (t + 0.22).truncatingRemainder(dividingBy: 1))
    } else {
      let r = 19 + 2.5 * wave(t)
      for x in [94.0, 266] { stroke(Path(ellipseIn: CGRect(x: x - r, y: 223 - r, width: 2 * r, height: 2 * r)), 0x6560998D, 1.1) }
    }
    vestibularGlandLeader(146, 93, 180, 110); vestibularGlandLeader(250, 155, 218, 198)
    vestibularGlandLeader(73, 263, 86, 237); vestibularGlandLeader(271, 258, 244, 216)
    label("vestibular_gland_urethral", 81, 92, 129)
    label("vestibular_gland_pores", 286, 147, 133)
    label("vestibular_gland_pair", 76, 283, 135)
    label("vestibular_gland_duct", 279, 280, 130)
  }
  private func vestibularGlandMicro(_ t: Double, collecting: Bool) {
    let g = GalaxySSIHealthAtlasVestibularGlandGeometry.self
    gradient(g.stroma, 77, 280, 0xF5EADF, 0xE3D6D1); stroke(g.stroma, 0xC9B2AC, 1.3)
    let branches = [g.upper, g.middle, g.lower]
    for branch in branches { stroke(branch, 0x6C9A91, 11) }
    stroke(g.main, 0x6C9A91, 18)
    for branch in branches { stroke(branch, 0xEBF2DF, 6.5) }
    stroke(g.main, 0xEBF2DF, 12)
    vestibularGlandAcinus(91, 113, -2); vestibularGlandAcinus(106, 182, 0); vestibularGlandAcinus(91, 251, 2)
    if collecting {
      let tracks = [g.upperTrack, g.middleTrack, g.lowerTrack]
      let slot = min(tracks.count - 1, Int(t * Double(tracks.count)))
      let p = t * Double(tracks.count) - Double(slot), branch = tracks[slot], main = g.mainTrack
      let distance = p * (branch.length + main.length)
      if distance < branch.length, branch.length > 0 {
        at(branch.route, distance / branch.length) { x, y in disc(x, y, 2.5, 0x387B72) }
      } else if main.length > 0 {
        at(main.route, (distance - branch.length) / main.length) { x, y in disc(x, y, 3, 0x387B72, border: 0xEBF2DF) }
      }
      vestibularGlandLeader(166, 77, 151, 144); vestibularGlandLeader(274, 246, 273, 173)
      label("vestibular_gland_branches", 167, 66, 158); label("vestibular_gland_main_duct", 271, 267, 143)
    } else {
      vestibularGlandSecrete(91, 113, t)
      vestibularGlandSecrete(106, 182, (t + 0.25).truncatingRemainder(dividingBy: 1))
      vestibularGlandSecrete(91, 251, (t + 0.5).truncatingRemainder(dividingBy: 1))
      vestibularGlandLeader(107, 69, 92, 93); vestibularGlandLeader(155, 314, 94, 252)
      label("vestibular_gland_cells", 107, 58, 165); label("vestibular_gland_lumen", 166, 334, 155)
    }
  }
  private func vestibularGlandAcinus(_ x: Double, _ y: Double, _ turn: Double) {
    var local = context; local.translateBy(x: x, y: y); local.rotate(by: .degrees(turn))
    let art = copy(local)
    art.oval(-31, -31, 31, 31, top: -32, bottom: 32, from: 0xE5EEE0, to: 0xACCBBF, border: 0x6C9A91)
    art.rounded(2, -3.25, 33, 3.25, 2, 0xEBF2DF); art.disc(0, 0, 11, 0xEBF2DF)
    for sector in 0...7 where sector != 2 {
      var cell = local; cell.rotate(by: .degrees(Double(sector) * 45))
      let cellArt = copy(cell)
      cellArt.oval(-6.3, -28, 6.3, -9, top: -29, bottom: -8, from: 0xD3E9DC, to: 0x91B8AD, border: 0x88ADA2)
      cellArt.disc(0, -23, 2.1, 0x748B8D)
    }
  }
  private func vestibularGlandSecrete(_ x: Double, _ y: Double, _ t: Double) {
    disc(x, y - 10 + 10 * t, 1.8 + 0.7 * t, 0x387B72)
  }
  private func vestibularGlandOutlet(_ track: GalaxySSIHealthAtlasRegionalTrack, _ t: Double) {
    guard track.length > 0 else { return }
    let distance = t * track.length
    if distance > 0 { stroke(track.path.trimmedPath(from: max(0, distance - 8) / track.length, to: t), 0x387B72, 1.35) }
    at(track.route, t) { x, y in disc(x, y, 1.9, 0xEBF2DF, border: 0x387B72) }
  }
  private func vestibularGlandLeader(_ x: Double, _ y: Double, _ atX: Double, _ atY: Double) {
    line(x, y, atX, atY, 0x758B8D, 1); disc(atX, atY, 2, Self.cream, border: 0x758B8D)
  }
}
