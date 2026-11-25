import SwiftUI

private typealias MelaninMotion = GalaxySSIHealthAtlasMelaninMotion
private typealias MelaninShapes = GalaxySSIHealthAtlasMelaninShapes

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func melaninScene(step: Int, t: Double) {
    melaninTissue(focus: step == 0 ? t : nil)
    if step < 4 { for p in MelaninMotion.residentPigment { melaninCore(p.x, p.y, amount: 0.73) } }
    switch step {
    case 0: melaninStorage(0, count: 3)
    case 1: melaninStorage(t, count: MelaninMotion.storage.count)
    case 2: melaninStorage(1, count: 3); melaninDendriteCargo(t)
    case 3:
      melaninStorage(1, count: 3); melaninDendriteCargo(1, sideBranchesOnly: true)
      for i in MelaninMotion.arrivals.indices {
        switch MelaninMotion.transfer(t, index: i) {
        case .envelope(let f): at(MelaninMotion.branches[0], f) { x, y in melaninCapsule(x, y) }
        case .core(let f): at(MelaninMotion.transferTracks[i], f) { x, y in melaninCore(x, y) }
        }
      }
    case 4:
      melaninStorage(1, count: 3); melaninDendriteCargo(1, sideBranchesOnly: true)
      if let dispersed = MelaninMotion.residentPigment.last { melaninCore(dispersed.x, dispersed.y, amount: 0.73) }
      for (i, track) in MelaninMotion.capTracks.enumerated() { at(track, MelaninMotion.capFraction(t, index: i)) { x, y in melaninCore(x, y) } }
      for i in 0...2 {
        let uv = MelaninMotion.uv(t, index: i)
        melaninAlpha(43).line(uv.x, 83, uv.x + 5, uv.backgroundEnd, 0x7963A7, 1.05)
        melaninAlpha(uv.alpha).line(uv.endX - 0.7, max(80, uv.endY - 12), uv.endX, uv.endY, 0x7963A7, 2.2)
      }
    default: break
    }
    melaninLabels(step)
  }
  func melaninAlpha(_ alpha: Int) -> Self { var local = context; local.opacity *= Double(min(255, max(0, alpha))) / 255; return copy(local) }
  private func melaninStorage(_ t: Double, count: Int) {
    for i in 0..<count { let p = MelaninMotion.storage[i]; melaninCapsule(p.x, p.y, amount: MelaninMotion.storageAmount(t, index: i)) }
  }
  private func melaninDendriteCargo(_ t: Double, sideBranchesOnly: Bool = false) {
    if !sideBranchesOnly {
      for i in MelaninMotion.arrivals.indices { at(MelaninMotion.branches[0], MelaninMotion.mainFraction(t, index: i)) { x, y in melaninCapsule(x, y) } }
    }
    for i in 1...2 { at(MelaninMotion.branches[i], MelaninMotion.sideFraction(t, branch: i)) { x, y in melaninCapsule(x, y) } }
  }
  private func melaninCapsule(_ x: Double, _ y: Double, amount: Double = 1) {
    oval(x - 4.1, y - 3.1, x + 4.1, y + 3.1, fill: 0xFFD99E, border: 0xAD794D); melaninCore(x, y, amount: amount)
  }
  private func melaninCore(_ x: Double, _ y: Double, amount: Double = 1) {
    let r = 1 + 1.9 * amount
    fill(Path(ellipseIn: CGRect(x: x - r, y: y - 0.73 * r, width: 2 * r, height: 1.46 * r)), MelaninShapes.pigment)
  }
  private func melaninLabels(_ step: Int) {
    melaninCallout("melanin_story_label_surface", 77, 72, 77, 105)
    melaninCallout("melanin_story_label_keratinocyte", 282, 72, 279, 167, elbowX: 294, elbowY: 143)
    melaninCallout("melanin_story_label_melanocyte", 93, 324, 119, 277, elbowX: 93, elbowY: 305)
    melaninCallout("melanin_story_label_basement", 266, 324, 266, 285)
    let key: String
    switch step {
    case 0: line(108, 342, 120, 342, MelaninShapes.membrane, 4); key = "melanin_story_label_dendrite"
    case 1, 2: melaninCapsule(114, 342); key = "melanin_story_label_melanosome"
    case 3: melaninCore(114, 342); key = "melanin_story_label_core"
    default:
      for i in -1...1 { melaninCore(114 + Double(i) * 5, Double(341 + i * i)) }
      key = "melanin_story_label_cap"
    }
    label(key, 183, 347, 110)
  }
  private func melaninCallout(_ key: String, _ x: Double, _ baseline: Double, _ ax: Double, _ ay: Double, elbowX: Double? = nil, elbowY: Double? = nil) {
    let bx = elbowX ?? x, by = elbowY ?? ((baseline + ay) / 2), start = baseline + (ay > baseline ? 6 : -16)
    label(key, x, baseline, 150); line(x, start, bx, by, MelaninShapes.leader, 1.05); line(bx, by, ax, ay, MelaninShapes.leader, 1.05)
    disc(ax, ay, 2, MelaninShapes.leader, border: Self.cream)
  }
}
