import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func clitoralSensoryScene(_ step: Int, _ t: Double) {
    switch step {
    case 0: clitoralStructure(t)
    case 1: clitoralEndings(t)
    case 2: clitoralDorsal(t)
    default: clitoralSacral(t)
    }
  }
  private func clitoralStructure(_ t: Double) {
    context.draw(Image("HealthAtlasRegionalClitoralCutaway"), in: CGRect(x: 0, y: 36, width: 360, height: 280))
    clitoralLeader(121, 91, 176, 119); clitoralLeader(232, 132, 181, 156)
    clitoralLeader(75, 258, 104, 210); clitoralLeader(241, 264, 215, 223)
    label("clitoral_sensory_body", 78, 91, 82); label("clitoral_sensory_glans", 274, 132, 78)
    label("clitoral_sensory_crura", 68, 279, 118); label("clitoral_sensory_bulbs", 254, 285, 146)
    let index = min(3, Int(t * 4)), phase = t * 4 - Double(index)
    let anchors = [CGPoint(x: 176, y: 119), CGPoint(x: 181, y: 156), CGPoint(x: 104, y: 210), CGPoint(x: 215, y: 223)]
    let point = anchors[index], radius = 5 + 4 * phase
    var local = context; local.opacity = Double(Int(125 * (1 - wave(phase + 0.25)))) / 255
    copy(local).stroke(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: 2 * radius, height: 2 * radius)), 0x307E83, 1.2)
  }
  private func clitoralEndings(_ t: Double) {
    let g = GalaxySSIHealthAtlasClitoralSensoryGeometry.self
    gradient(g.endingTissue, 96, 244, 0xF9E1D4, 0xCC9CA9); stroke(g.endingTissue, 0xAB7F8E, 1.5)
    stroke(g.endingEdge, 0xFFF0E2, 3); stroke(g.endingBranches, 0xAA7745, 2)
    stroke(g.endingRoute, 0xAA7745, 4); stroke(g.endingRoute, 0xE7C993, 1.8)
    clitoralPulse(g.endingRouteTrack, t)
    clitoralLeader(113, 69, 112, 135); clitoralLeader(223, 301, 249, 277)
    label("clitoral_sensory_endings", 113, 59, 145); label("clitoral_sensory_afferent", 220, 321, 160)
  }
  private func clitoralDorsal(_ t: Double) {
    let g = GalaxySSIHealthAtlasClitoralSensoryGeometry.self
    context.draw(Image("HealthAtlasRegionalClitoralCutaway"), in: CGRect(x: 0, y: 25, width: 360, height: 280))
    var mirrored = context; mirrored.translateBy(x: 180, y: 0); mirrored.scaleBy(x: -1, y: 1); mirrored.translateBy(x: -180, y: 0)
    copy(mirrored).stroke(g.pudendalBranch, 0xC5A985, 2); copy(mirrored).stroke(g.dorsalRoute, 0xC5A985, 3)
    stroke(g.pudendalBranch, 0xC5A985, 2)
    stroke(g.dorsalRoute, 0xAA7745, 4.4); stroke(g.dorsalRoute, 0xE7C993, 2)
    clitoralPulse(g.dorsalRouteTrack, t)
    clitoralLeader(104, 78, 142, 123); clitoralLeader(99, 301, 66, 262)
    label("clitoral_sensory_dorsal_nerve", 89, 64, 158); label("clitoral_sensory_pudendal", 98, 321, 155)
  }
  private func clitoralSacral(_ t: Double) {
    let g = GalaxySSIHealthAtlasClitoralSensoryGeometry.self
    oval(221, 121, 326, 244, top: 122, bottom: 243, from: 0xF8E4D5, to: 0xD3A8AF, border: 0xA5808D)
    fill(g.grayMatter, 0xBC8C9B); stroke(g.grayMatter, 0xA67989, 1.2)
    disc(273, 183, 2.5, Self.cream, border: 0xA67989); stroke(g.ventralRoot, 0xCCB3A5, 4)
    oval(153, 122, 189, 150, fill: 0xECD8B5, border: 0xAA7745)
    stroke(g.sacralRoute, 0xAA7745, 5); stroke(g.sacralRoute, 0xE7C993, 2)
    clitoralPulse(g.sacralRouteTrack, t)
    clitoralLeader(164, 100, 172, 134); clitoralLeader(275, 101, 273, 123); clitoralLeader(95, 270, 76, 228)
    label("clitoral_sensory_dorsal_root", 155, 88, 112); label("clitoral_sensory_cord", 277, 88, 111)
    label("clitoral_sensory_pudendal", 97, 292, 145)
  }
  private func clitoralLeader(_ x: Double, _ y: Double, _ atX: Double, _ atY: Double) {
    line(x, y, atX, atY, 0x778D91, 1); disc(atX, atY, 2.1, Self.cream, border: 0x778D91)
  }
  private func clitoralPulse(_ track: GalaxySSIHealthAtlasRegionalTrack, _ t: Double) {
    guard track.length > 0 else { return }
    let head = t * track.length
    if head > 0 { stroke(track.path.trimmedPath(from: max(0, head - 26) / track.length, to: t), 0x307E83, 3.1) }
    at(track.route, t) { x, y in disc(x, y, 4.1, 0xF7F6DF, border: 0x307E83) }
  }
}
