import SwiftUI

extension GalaxySSIHealthAtlasCryptWallDrawing {
  private static let lineage: UInt32 = 0x286B62
  func stemRenewal(_ step: Int, _ t: Double) {
    art.label("crypt_lumen", 166, 97, 122)
    let niche = Self.centers[14], neighbor = Self.centers[13], adjacent = atPose(neighbor), cell = atPose(niche)
    adjacent.panethBody(active: false)
    adjacent.art.disc(-3.3, 4.6, 1.65, 0xA96253); adjacent.art.disc(1, 5.4, 1.65, 0xA96253); adjacent.art.disc(3.7, 8, 1.3, 0xA96253)
    switch step {
    case 0:
      cell.renewalCell(0x92C4A6)
      let junction = -Self.cellSpan * 0.46
      cell.art.line(junction, 2.2, junction, 5.5 + (18.7 - 5.5) * Self.ease(t), Self.lineage, 2.45)
    case 1: cell.dividingStem(t)
    default: cell.renewalCell(0x92C4A6)
    }
    leader("intestinal_stem_renewal_cell", niche.at(0, 16), 232, 326, 271, 93, Self.lineage)
    switch step {
    case 0: leader("intestinal_stem_renewal_paneth", neighbor.at(-2, 12), 114, 319, 71, 99, 0xA96253)
    case 1:
      let p = Self.ease(t, 0.55, 1); daughter(15.5 - 0.52 * (1 - p), p)
    case 2:
      for i in stride(from: 2, through: 0, by: -1) {
        let p = Self.ease(t, Double(i) * 0.085, 0.86 + Double(i) * 0.07)
        let slot = 15.5 + (26.5 - Double(i) - 15.5) * p
        daughter(slot, i == 0 ? 1 : Self.ease(t, 0.13 + 0.13 * Double(i), 0.24 + 0.13 * Double(i)))
      }
      leader("intestinal_stem_renewal_toward_villus", Self.centers[24].at(0, 3), 216, 58, 172, 115, Self.lineage)
    default:
      for i in stride(from: 2, through: 0, by: -1) {
        let p = Self.ease(t, 0.1 + Double(i) * 0.11, 0.76 + Double(i) * 0.11)
        if let pose = Self.sample(26.5 - Double(i) + Self.ease(t) * 0.65) {
          atPose(pose).renewalCell(p > 0.52 ? 0xCFDF9F : 0xB5D5AA, brush: p)
        }
      }
      leader("intestinal_stem_renewal_lining", Self.centers[27].at(0, 2), 238, 50, 195, 100, Self.lineage)
    }
  }
  private func renewalBody(_ tint: UInt32, _ half: Double) {
    let shape = Path(roundedRect: CGRect(x: -half, y: 0.6, width: 2 * half, height: 18.9), cornerRadius: 3.1)
    art.fill(shape, tint); art.stroke(shape, Self.lineage, 1.1)
  }
  private func renewalCell(_ tint: UInt32, brush: Double = 0) {
    renewalBody(tint, Self.cellSpan * 0.43); flatOval(-3.15, 8.5, 3.15, 15.1, Self.lineage)
    if brush > 0 {
      art.line(-7.5, 1, 7.5, 1, Self.lineage, 1.15)
      for i in -3...3 { let x = Double(i) * 2.25; art.line(x, 0.5, x, 0.5 - brush * (3.5 + Double(i & 1)), Self.lineage, 1.3) }
    }
  }
  private func dividingStem(_ t: Double) {
    let split = Self.ease(t, 0.08, 0.65), retained = Self.ease(t, 0.61, 0.94)
    renewalBody(0x92C4A6, Self.cellSpan * (0.43 + 0.06 * split * (1 - retained)))
    if split == 0 { flatOval(-3.15, 8.5, 3.15, 15.1, Self.lineage) }
    else {
      let x = 3.8 * split, a = x * (1 - retained), r = 1.9 + (3.1 - 1.9) * retained
      flatOval(-a - r, 8.5, -a + r, 15.1, Self.lineage)
      var fading = context; fading.opacity = Double(Int(255 * (1 - retained))) / 255
      let local = Self(context: fading, language: language)
      local.flatOval(x - 1.85, 9.1, x + 1.85, 14.7, Self.lineage)
      local.art.line(0, 0.7, 0, 7.5 * split, Self.lineage, 1.35)
      local.art.line(0, 19.1 - 6.7 * split, 0, 19.1, Self.lineage, 1.35)
    }
  }
  private func daughter(_ slot: Double, _ amount: Double) {
    guard amount > 0, let pose = Self.sample(slot) else { return }
    var local = atPose(pose).context
    let s = 0.65 + 0.35 * amount
    local.translateBy(x: 0, y: 10); local.scaleBy(x: s, y: s); local.translateBy(x: 0, y: -10)
    Self(context: local, language: language).renewalCell(0xB5D5AA)
  }
}
