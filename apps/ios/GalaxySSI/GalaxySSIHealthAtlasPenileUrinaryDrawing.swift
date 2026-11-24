import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func penileUrinaryScene(_ step: Int, _ t: Double) {
    if step == 0 { penileTransverse(t) }
    else { penileLongitudinal(t, distal: step == 2) }
  }
  private func penileTransverse(_ t: Double) {
    let g = GalaxySSIHealthAtlasPenileUrinaryGeometry.self
    penileSurface(g.section, 94, 267, 0xFFE9DC, 0xE8B6B3, 0xA7828D)
    for side in 0..<2 {
      var local = context
      if side == 1 { local.translateBy(x: 180, y: 0); local.scaleBy(x: -1, y: 1); local.translateBy(x: -180, y: 0) }
      let art = copy(local)
      art.penileSurface(g.cavernosa, 102, 215, 0xEEE5F4, 0xC8B4D4, 0x897395)
      art.stroke(g.weave, 0xAD97B9, 1.4)
    }
    penileSurface(g.spongiosum, 191, 277, 0xFFDBC6, 0xE6A49A, Self.coral)
    oval(164, 225, 196, 239, fill: 0xFFEBBD, border: 0x9A6845)
    var local = context
    local.opacity = Double(Int(90 + 108 * (0.5 + 0.5 * wave(t)))) / 255
    // The Android overlay border is transparent; draw a fill only.
    copy(local).fill(Path(ellipseIn: CGRect(x: 166, y: 227, width: 28, height: 10)), 0xEFB962)
    label("penile_urinary_dorsal", 180, 44, 100)
    label("penile_urinary_cavernosa", 180, 76, 155)
    penileLeader(151, 82, 125, 136); penileLeader(209, 82, 235, 136)
    penileCallout("spongiosum", 86, 310, 148, 148, 242, above: false)
    penileCallout("spongy", 273, 330, 148, 182, 232, above: false)
  }
  private func penileLongitudinal(_ t: Double, distal: Bool) {
    let g = GalaxySSIHealthAtlasPenileUrinaryGeometry.self
    oval(59, 166, 122, 205, top: 166, bottom: 213, from: 0xEADFEE, to: 0xC9B8CE, border: 0x897395)
    penileSurface(g.shaftSection, 180, 243, 0xEEE6F2, 0xBFACCB, 0x897395)
    penileSurface(g.spongySection, 203, 262, 0xFFE2CE, 0xE6AB9E, Self.coral)
    penileSurface(g.bladder, 94, 267, 0xFFE9DC, 0xE8B6B3, 0xA7828D)
    penileSurface(g.bladderInterior, 79, 178, 0xFFF3DB, 0xF0C88C, 0xD7A171)
    stroke(g.route, 0x9A6845, 7); stroke(g.route, 0xFFECBE, 4.5)
    let flow = g.flow, spongyStart = g.proximalTrack.length
    let start = distal ? spongyStart : 0, end = distal ? flow.length : spongyStart
    let distance = start + t * (end - start + 24)
    let tail = max(distance - 24, start), head = min(distance, end)
    if flow.length > 0, head > tail {
      let trace = flow.path.trimmedPath(from: tail / flow.length, to: head / flow.length)
      stroke(trace, 0xC28233, 4.4); stroke(trace, 0xFFD47F, 2.4)
    }
    disc(330, 228, 3, 0xFFECBE, border: 0x9A6845)
    if distal {
      arrow(279, 265, 323, 265, Self.teal)
      penileCallout("spongy", 204, 132, 144, 196, 240)
      penileCallout("spongiosum", 147, 309, 149, 154, 248, above: false)
      penileCallout("meatus", 281, 161, 138, 330, 228)
    } else {
      penileCallout("bladder", 87, 57, 113, 78, 103)
      penileCallout("prostatic", 204, 102, 145, 90, 185)
      penileCallout("membranous", 95, 290, 162, 95, 210, above: false)
      penileCallout("spongy", 267, 311, 142, 251, 233, above: false)
    }
  }
  private func penileSurface(_ path: Path, _ top: Double, _ bottom: Double, _ first: UInt32, _ last: UInt32, _ edge: UInt32) {
    gradient(path, top, bottom, first, last); stroke(path, edge, 1.45)
  }
  private func penileCallout(_ key: String, _ x: Double, _ y: Double, _ width: Double, _ a: Double, _ b: Double, above: Bool = true) {
    penileLeader(x, y + (above ? 5 : -15), a, b)
    label("penile_urinary_" + key, x, y, width)
  }
  private func penileLeader(_ x: Double, _ y: Double, _ a: Double, _ b: Double) {
    line(x, y, a, b, 0x776873, 1.1); disc(a, b, 2, Self.violet, border: Self.cream)
  }
}
