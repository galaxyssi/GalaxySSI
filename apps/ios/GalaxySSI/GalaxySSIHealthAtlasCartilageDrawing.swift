import SwiftUI

private typealias CartilageMotion = GalaxySSIHealthAtlasCartilageMotion
private typealias CartilageInk = GalaxySSIHealthAtlasCartilageInk

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func cartilageTrochlea(_ motion: GalaxySSIHealthAtlasCartilageMotion, step: Int, t: Double) {
    let depth = motion.depth
    var bone = Path()
    bone.move(to: CGPoint(x: 32, y: CartilageMotion.baseY(32)))
    for x in stride(from: 36, through: 328, by: 4) { bone.addLine(to: CGPoint(x: Double(x), y: CartilageMotion.baseY(Double(x)))) }
    bone.addCurve(to: CGPoint(x: 284, y: 281), control1: CGPoint(x: 326, y: 255), control2: CGPoint(x: 315, y: 278))
    bone.addLine(to: CGPoint(x: 76, y: 281))
    bone.addCurve(to: CGPoint(x: 32, y: CartilageMotion.baseY(32)), control1: CGPoint(x: 45, y: 278), control2: CGPoint(x: 34, y: 255)); bone.closeSubpath()
    gradient(bone, 227, 283, 0xE4BD9E, 0xFFEBCF)
    var boneClip = context; boneClip.clip(to: bone)
    let trabeculae = copy(boneClip)
    for i in 0...13 {
      let x = 43 + 21 * Double(i), y = CartilageMotion.baseY(x) + 7 + Double(6 * (i % 3))
      trabeculae.line(x, y, x + 16, y + 11, 0xC79B7E, 1.5); trabeculae.line(x + 16, y + 11, x + 23, y + 5, 0xC79B7E, 1.5)
    }
    stroke(bone, CartilageInk.boneEdge, 1.6)
    var surface = Path(); surface.move(to: CGPoint(x: 32, y: CartilageMotion.faceY(32, depth: depth)))
    for x in stride(from: 36, through: 328, by: 4) { surface.addLine(to: CGPoint(x: Double(x), y: CartilageMotion.faceY(Double(x), depth: depth))) }
    var band = surface
    for x in stride(from: 328, through: 32, by: -4) { band.addLine(to: CGPoint(x: Double(x), y: CartilageMotion.baseY(Double(x)))) }
    band.closeSubpath(); gradient(band, 174, 246, 0xD4EFE6, 0xA3CABE)
    var bandClip = context; bandClip.clip(to: band)
    let matrix = copy(bandClip)
    if motion.pressure > 0 {
      var fluid = bandClip; fluid.opacity *= Double(Int(150 * motion.pressure)) / 255
      let y = CartilageMotion.faceY(180, depth: depth)
      copy(fluid).fill(Path(ellipseIn: CGRect(x: 107, y: y - 7, width: 146, height: 34)), 0x75BACC)
    }
    for row in 1...3 {
      let fraction = Double(row) * 0.23
      var detail = Path(); detail.move(to: CGPoint(x: 32, y: CartilageMotion.matrixY(32, depth: depth, fraction: fraction)))
      for x in stride(from: 36, through: 328, by: 4) { detail.addLine(to: CGPoint(x: Double(x), y: CartilageMotion.matrixY(Double(x), depth: depth, fraction: fraction))) }
      matrix.stroke(detail, 0x79AFA0, 1.25)
    }
    for i in 0...11 {
      let drift = step == 0 ? 8 * wave(t + Double(i) * 0.21) : 0, x = 48 + 24 * Double(i) + drift
      let fraction = 0.32 + 0.20 * Double(i % 3) + (step == 0 ? 0.08 * wave(t + Double(i) * 0.21 + 0.25) : 0)
      matrix.disc(x, CartilageMotion.matrixY(x, depth: depth, fraction: fraction), 3.3, CartilageInk.fluid, border: Self.cream)
    }
    stroke(band, Self.teal, 1.4); stroke(surface, Self.teal, 2.6)
  }
  func cartilagePatella(travel: Double) {
    var local = context; local.translateBy(x: 0, y: travel)
    let art = copy(local)
    var bone = Path(); bone.move(to: CGPoint(x: 68, y: CartilageMotion.patellarFaceY(68) - 18))
    bone.addCurve(to: CGPoint(x: 180, y: 76), control1: CGPoint(x: 87, y: 81), control2: CGPoint(x: 131, y: 76))
    bone.addCurve(to: CGPoint(x: 292, y: CartilageMotion.patellarFaceY(292) - 18), control1: CGPoint(x: 229, y: 76), control2: CGPoint(x: 273, y: 81))
    for x in stride(from: 292, through: 68, by: -4) { bone.addLine(to: CGPoint(x: Double(x), y: CartilageMotion.patellarFaceY(Double(x)) - 18)) }
    bone.closeSubpath(); art.gradient(bone, 76, 152, 0xFFEDDB, 0xE1BA99); art.stroke(bone, CartilageInk.boneEdge, 1.6)
    var band = Path(); band.move(to: CGPoint(x: 68, y: CartilageMotion.patellarFaceY(68)))
    for x in stride(from: 72, through: 292, by: 4) { band.addLine(to: CGPoint(x: Double(x), y: CartilageMotion.patellarFaceY(Double(x)))) }
    for x in stride(from: 292, through: 68, by: -4) { band.addLine(to: CGPoint(x: Double(x), y: CartilageMotion.patellarFaceY(Double(x)) - 18)) }
    band.closeSubpath(); art.fill(band, 0xB7DDCF); art.stroke(band, Self.teal, 1.6)
  }
  func cartilageLoad(travel: Double, t: Double, arriving: Bool) {
    for i in -1...1 {
      let x = 180 + Double(i) * 25, y = 68 + travel - (arriving ? 9 * (1 - t) : 0)
      cartilageForceArrow(x, y - 24, y, CartilageInk.load)
    }
  }
  func cartilageFlow(depth: Double, t: Double, returning: Bool) {
    let alpha = CartilageMotion.flowAlpha(t, returning: returning)
    guard alpha > 0 else { return }
    var local = context; local.opacity *= Double(alpha) / 255
    let flow = copy(local)
    for side in [-1, 1] {
      let route = CartilageMotion.flowRoute(side: side, depth: depth)
      for i in 0...1 {
        let f = CartilageMotion.flowFraction(t, index: i), head = returning ? 1 - f : f, tail = head + (returning ? 0.18 : -0.18)
        at(route, tail) { x1, y1 in at(route, head) { x2, y2 in flow.arrow(x1, y1, x2, y2, CartilageInk.fluid) } }
      }
    }
  }
  func cartilageLabels(depth: Double, travel: Double) {
    label("cartilage_story_label_patella", 83, 42, 104)
    line(83, 49, 113, 92 + travel, CartilageInk.boneEdge, 1.1); disc(113, 92 + travel, 2.2, CartilageInk.boneEdge, border: Self.cream)
    let space = (CartilageMotion.patellarFaceY(303) + travel + CartilageMotion.faceY(303, depth: depth)) / 2
    label("cartilage_story_label_joint_space", 290, 42, 116)
    line(318, 49, 318, space, CartilageInk.space, 1.1); line(318, space, 303, space, CartilageInk.space, 1.1); disc(303, space, 2.2, CartilageInk.space, border: Self.cream)
    label("cartilage_story_label_trochlea", 98, 309, 145)
    line(98, 295, 107, 262, CartilageInk.boneEdge, 1.1); disc(107, 262, 2.2, CartilageInk.boneEdge, border: Self.cream)
    label("cartilage_story_label_matrix", 263, 309, 147)
    line(305, 296, 336, 273, Self.teal, 1.1); line(336, 273, 336, 216, Self.teal, 1.1); line(336, 216, 305, 216, Self.teal, 1.1); disc(305, 216, 2.2, Self.teal, border: Self.cream)
    line(23, 323, 337, 323, 0xC6C9B8, 1)
    disc(35, 342, 3.6, CartilageInk.fluid, border: Self.cream); label("cartilage_story_label_fluid", 112, 347, 132)
    cartilageForceArrow(211, 335, 348, CartilageInk.load); label("cartilage_story_label_load", 270, 347, 100)
  }
  private func cartilageForceArrow(_ x: Double, _ from: Double, _ tip: Double, _ color: UInt32) {
    line(x, from, x, tip - 1, color, 3); line(x - 5, tip - 6, x, tip, color, 3); line(x + 5, tip - 6, x, tip, color, 3)
  }
}
