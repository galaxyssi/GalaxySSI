import SwiftUI

private typealias HairMotion = GalaxySSIHealthAtlasHairMotion
private typealias HairInk = GalaxySSIHealthAtlasHairInk

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func hairScene(_ frame: GalaxySSIHealthAtlasHairMotion, step: Int, t: Double) {
    hairSkin(); hairFollicle(frame.bulb, matrix: frame.matrix, t: t, divide: step == 0)
    hairCallout("hair_cycle_story_label_epidermis", 76, 108, 101, 141); hairCallout("hair_cycle_story_label_follicle", 76, 216, 163, 169)
    if step == 4 { hairRenewal(frame); return }
    if step == 3 {
      let halo = 13 + 5 * wave(t - 0.25)
      var local = context; local.opacity *= Double(Int(145 - 6 * (halo - 8))) / 255
      copy(local).stroke(Path(ellipseIn: CGRect(x: HairMotion.axis(frame.root) - halo, y: frame.root - halo, width: 2 * halo, height: 2 * halo)), Self.teal, 2)
    }
    hairShaft(tip: frame.tip, root: frame.root, club: frame.club)
    if step == 1 { let f = HairMotion.ease(t); arrow(127, 109 - 13 * f, 120 - 4 * f, 96 - 16 * f, Self.teal) }
    hairCallout("hair_cycle_story_label_shaft", 273, 76, HairMotion.axis(104), 104)
    switch step {
    case 0, 1: hairCallout("hair_cycle_story_label_matrix", 273, 284, HairMotion.axis(frame.bulb) + 10, frame.bulb - 4)
    case 2: hairCallout("hair_cycle_story_label_lower", 273, 241, HairMotion.axis(frame.bulb) + 7, frame.bulb - 4)
    case 3: hairCallout("hair_cycle_story_label_club", 273, 195, HairMotion.axis(frame.root), frame.root)
    default: break
    }
  }
  private func hairSkin() {
    let skin = Path(roundedRect: CGRect(x: 24, y: 132, width: 312, height: 197), cornerRadius: 14)
    gradient(skin, 132, 329, 0xFFE1D7, 0xEAD5E1); stroke(skin, 0xBE8694, 1.3)
    for side in 0...1 {
      for i in 0...5 {
        let x = Double(39 + side * 200 + (i % 3) * 23), y = Double(175 + i * 23)
        var path = Path(); path.move(to: CGPoint(x: x, y: y))
        path.addCurve(to: CGPoint(x: x + 39, y: y + 1), control1: CGPoint(x: x + 11, y: y - 6), control2: CGPoint(x: x + 22, y: y + 8)); stroke(path, 0xD8AAB4, 1.15)
      }
    }
    fill(HairInk.epidermis, 0xF4C1B6); stroke(HairInk.epidermis, 0xBC8186, 1.3); line(26, 137, 334, 137, 0xFFE5D6, 2)
    line(187, 161, 219, 155, 0xD59C79, 5)
    for i in 0...2 { let x = 204 + Double(i) * 10, y = i == 1 ? 159.0 : 152; oval(x, y - 9, x + 14, y + 7, fill: 0xFFDAB2, border: 0xBD8B72) }
  }
  private func hairFollicle(_ bulb: Double, matrix: Double, t: Double, divide: Bool) {
    let center = HairMotion.axis(bulb), middle = (170 + bulb) / 2, width = 9 + 11 * (bulb - 201) / 81, curve = 10 + 5 * matrix
    let path = Path { p in
      p.move(to: CGPoint(x: 163, y: 132))
      p.addCurve(to: CGPoint(x: 163, y: 170), control1: CGPoint(x: 160, y: 147), control2: CGPoint(x: 163, y: 158))
      p.addCurve(to: CGPoint(x: center - width, y: bulb), control1: CGPoint(x: 163, y: middle), control2: CGPoint(x: center - width, y: middle))
      p.addCurve(to: CGPoint(x: center + width, y: bulb), control1: CGPoint(x: center - width, y: bulb + curve), control2: CGPoint(x: center + width, y: bulb + curve))
      p.addCurve(to: CGPoint(x: 196, y: 170), control1: CGPoint(x: center + width, y: middle), control2: CGPoint(x: 196, y: middle))
      p.addCurve(to: CGPoint(x: 183, y: 132), control1: CGPoint(x: 196, y: 158), control2: CGPoint(x: 188, y: 147)); p.closeSubpath()
    }
    gradient(path, 132, 296, 0xFFEADB, 0xDBA1BA); stroke(path, HairInk.wallEdge, 1.7)
    line(HairMotion.axis(132), 132, HairMotion.axis(bulb - 13), bulb - 13, 0xECC1C8, 12); line(164, 132, 182, 132, 0xAF7686, 1.1)
    if matrix > 0 {
      for i in -2...2 {
        let x = center + Double(i) * (2 + 3 * matrix), y = bulb - 9 + Double(i * i) * 2.5, split = divide ? 2.6 * (1 + wave(t + 0.18 * Double(i))) : 1.3
        disc(x, y, 3.3 * matrix, 0xA65883, border: Self.cream); disc(x, y - split, 2.4 * matrix, 0xE79DB8, border: Self.cream)
      }
    }
    let papilla = 4 + 3 * matrix
    oval(center - papilla, bulb - 3, center + papilla, bulb + 8, fill: 0xCEC6E6, border: 0x78628E)
  }
  private func hairShaft(tip: Double, root: Double, club: Double, opacity: Double = 1) {
    var path = Path(); path.move(to: CGPoint(x: HairMotion.axis(tip), y: tip))
    if tip < 132 {
      let middle = (tip + 132) / 2
      path.addQuadCurve(to: CGPoint(x: HairMotion.axis(132), y: 132), control: CGPoint(x: HairMotion.axis(132) + 0.19 * (middle - 132), y: middle))
    }
    path.addLine(to: CGPoint(x: HairMotion.axis(root), y: root))
    var ink = context; ink.opacity *= Double(Int(255 * opacity)) / 255
    copy(ink).stroke(path, HairInk.hair, 6.8)
    var light = context; light.opacity *= Double(Int(220 * opacity)) / 255; light.translateBy(x: -1.2, y: 0)
    copy(light).stroke(path, HairInk.light, 1.4)
    if club > 0 {
      let r = 3.1 + 2.1 * club
      copy(ink).fill(Path(ellipseIn: CGRect(x: HairMotion.axis(root) - r, y: root - 5, width: 2 * r, height: r + 5)), HairInk.hair)
    }
  }
  private func hairRenewal(_ frame: HairMotion) {
    if frame.opacity > 0 {
      var local = context; local.translateBy(x: -frame.drift, y: -frame.lift)
      copy(local).hairShaft(tip: 74, root: 183, club: 1, opacity: frame.opacity)
    }
    if frame.opacity > 0.18 { hairCallout("hair_cycle_story_label_shedding", 273, 54, HairMotion.axis(106) - frame.drift, 106 - frame.lift) }
    if frame.renew > 0 {
      hairShaft(tip: frame.replacementTip, root: frame.replacementRoot, club: 0)
      let y = (frame.replacementTip + frame.replacementRoot) / 2
      if frame.renew > 0.08 { hairCallout("hair_cycle_story_label_replacement", 273, 251, HairMotion.axis(y), y) }
    }
  }
  private func hairCallout(_ key: String, _ x: Double, _ y: Double, _ anchorX: Double, _ anchorY: Double) {
    let bend = x + (x < 180 ? 23 : -29)
    label(key, x, y, 116); line(x, y + 6, bend, y + 6, HairInk.leader, 1.25); line(bend, y + 6, anchorX, anchorY, HairInk.leader, 1.25)
    disc(anchorX, anchorY, 2.1, HairInk.leader, border: Self.cream)
  }
}
