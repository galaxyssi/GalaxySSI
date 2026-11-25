import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func scrotalHeatScene(_ step: Int, _ t: Double) {
    if step == 2 { scrotalExchange(t) }
    else { scrotalSection(t, coverings: step == 1) }
  }
  private func scrotalSection(_ t: Double, coverings: Bool) {
    let g = GalaxySSIHealthAtlasScrotalHeatGeometry.self, emphasis = 0.5 + 0.5 * wave(t)
    scrotalFill(g.sac, 111, 294, 0xFFEFE0, 0xEFD4CA, 0xA98089)
    if coverings { stroke(g.dartos, 0xEDC5CF, 9 + 2 * emphasis) }
    stroke(g.dartos, 0xA36979, coverings ? 4.4 : 3)
    stroke(g.septum, 0xBA8995, 3.7)
    for side in 0..<2 {
      var local = context
      if side == 1 {
        local.translateBy(x: 0, y: 10)
        local.translateBy(x: 180, y: 0); local.scaleBy(x: -1, y: 1); local.translateBy(x: -180, y: 0)
      }
      let art = copy(local)
      art.scrotalFill(g.cord, 66, 160, 0xFFEAC5, 0xE8BC9A, 0xA48271)
      art.stroke(g.cordCore, 0xAD847A, 2.4)
      if !coverings { art.stroke(g.cordCore, 0xFFE2AF, 0.8 + emphasis) }
      if coverings { art.stroke(g.tunica, 0xBEDFD7, 8 + 2 * emphasis) }
      art.stroke(g.tunica, 0x6A9993, 4.3)
      art.stroke(g.tunica, 0xE6F0E9, 1.8)
      art.scrotalFill(g.testis, 143, 270, 0xFFE3BE, 0xE8B497, 0xB28570)
      art.stroke(g.testisContour, 0xD5A487, 1.4)
    }
    if coverings {
      scrotalCallout("dartos", 80, 319, 127, 61, 237, above: false)
      scrotalCallout("tunica", 271, 329, 132, 289, 231, above: false)
      scrotalCallout("septum", 179, 92, 131, 173, 146)
    } else {
      scrotalCallout("cord", 110, 42, 150, 95, 92)
      scrotalCallout("septum", 185, 92, 131, 173, 146)
      label("scrotal_heat_testes", 180, 326, 130)
      scrotalLeader(154, 310, 110, 219); scrotalLeader(206, 310, 250, 229)
    }
  }
  private func scrotalExchange(_ t: Double) {
    let g = GalaxySSIHealthAtlasScrotalHeatGeometry.self
    rounded(83, 64, 278, 296, 28, 0xF7E6D8)
    scrotalVessel(g.artery, 0xDF9A83, 0xEDC2AA, 0x9F6359, 20)
    scrotalVessel(g.veinBranches, 0xACAFBD, 0x88B6C6, 0x648998, 7)
    scrotalVessel(g.vein, 0xACAFBD, 0x88B6C6, 0x597F93, 16)
    scrotalPulse(g.arteryTrack, t, 0xFFE5C6)
    scrotalPulse(g.veinTrack, t, 0xE8F7F5)
    arrow(65, 130, 65, 222, Self.coral); arrow(296, 222, 296, 130, Self.blue)
    for i in 0...2 {
      let y = 130 + 54 * Double(i)
      var local = context
      local.opacity = Double(Int(170 + 85 * (0.5 + 0.5 * wave(t * 2 - Double(i) * 0.24)))) / 255
      copy(local).arrow(139, y, 194, y, 0x96652F)
    }
    label("scrotal_heat_heat_transfer", 169, 181, 83)
    scrotalCallout("artery", 91, 43, 136, 112, 74)
    scrotalCallout("plexus", 253, 43, 167, 243, 74)
    label("scrotal_heat_to_testis", 104, 327, 143)
    label("scrotal_heat_from_testis", 253, 327, 143)
  }
  private func scrotalPulse(_ track: GalaxySSIHealthAtlasScrotalHeatGeometry.Track, _ t: Double, _ color: UInt32) {
    guard track.length > 0 else { return }
    let head = t * (track.length + 22)
    let start = max(head - 22, 0), end = min(head, track.length)
    if end > start { stroke(track.path.trimmedPath(from: start / track.length, to: end / track.length), color, 4.5) }
  }
  private func scrotalVessel(_ path: Path, _ top: UInt32, _ bottom: UInt32, _ edge: UInt32, _ width: Double) {
    stroke(path, edge, width + 2.4)
    context.stroke(path, with: .linearGradient(Gradient(colors: [Self.color(top), Self.color(bottom)]),
      startPoint: CGPoint(x: 0, y: 80), endPoint: CGPoint(x: 0, y: 285)),
      style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
  }
  private func scrotalFill(_ path: Path, _ top: Double, _ bottom: Double, _ first: UInt32, _ last: UInt32, _ edge: UInt32) {
    gradient(path, top, bottom, first, last); stroke(path, edge, 1.45)
  }
  private func scrotalCallout(_ key: String, _ x: Double, _ y: Double, _ width: Double, _ a: Double, _ b: Double, above: Bool = true) {
    scrotalLeader(x, y + (above ? 5 : -15), a, b)
    label("scrotal_heat_" + key, x, y, width)
  }
  private func scrotalLeader(_ x: Double, _ y: Double, _ a: Double, _ b: Double) {
    line(x, y, a, b, 0x776873, 1.1); disc(a, b, 2, Self.violet, border: Self.cream)
  }
}
