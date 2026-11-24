import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  private enum SentinelPortrait { case tissue, display, contact }
  private static let sentinelFill: UInt32 = 0x84BDB1, sentinelEdge: UInt32 = 0x246C66
  private static let keratinEdge: UInt32 = 0xAD7172, sampleFill: UInt32 = 0xF7CE73, sampleEdge: UInt32 = 0x905D2F
  func langerhansScene(_ step: Int, _ t: Double) {
    switch step {
    case 0:
      rounded(28, 91, 332, 293, 10, 0xF8E6D1); rounded(28, 265, 332, 293, 8, 0xEED0B9)
      for row in 0...1 { for col in 0...5 {
        let x = 36 + 48 * Double(col) + 9 * Double(row), y = 95 + 14 * Double(row)
        rounded(x, y, x + 43, y + 10, 4, row == 0 ? 0xD9A17F : 0xEDB39E)
      } }
      var rotated = context; rotated.translateBy(x: 193, y: 207); rotated.rotate(by: .degrees(-24)); rotated.translateBy(x: -193, y: -207)
      copy(rotated).langerhansSentinel(193, 207, 0.55, 0.40 + 0.14 * wave(t))
      for row in 0...3 { for col in 0...5 {
        if row == 2 && col == 3 { continue }
        langerhansKeratinocyte(52 + 47 * Double(col) + 12 * Double(row % 2), 139 + 35 * Double(row), 21, 15, (row + col) % 2 == 0)
      } }
      line(34, 263, 326, 263, Self.keratinEdge, 1.4)
      langerhansCallout("surface", 180, 65, 170, 181, 95)
      line(25, 95, 25, 263, 0x526064, 1.2); line(25, 95, 32, 95, 0x526064, 1.2); line(25, 263, 32, 263, 0x526064, 1.2)
      langerhansCallout("epidermis", 72, 321, 110, 25, 263); langerhansCallout("cell", 241, 321, 151, 196, 208)
    case 1:
      rounded(28, 71, 332, 292, 10, 0xF8E6D1)
      for i in 0...2 {
        let y = 107 + 72 * Double(i), dx = 14 * Double(i % 2)
        langerhansKeratinocyte(100 - dx, y, 55, 29, i % 2 == 0); langerhansKeratinocyte(260 + dx, y, 49, 29, i % 2 != 0)
      }
      let reach = 0.5 + 0.5 * wave(t - 0.25)
      langerhansSentinel(180, 208, 1, reach); langerhansSample(193, 114, 4.5); langerhansSample(169, 102, 3)
      if reach > 0.68 { langerhansRing(193, 114, 9 + 3 * reach, 1.2) }
      langerhansCallout("sample", 180, 46, 185, 193, 107); langerhansCallout("keratinocyte", 86, 320, 134, 98, 254)
      langerhansCallout("branch", 269, 320, 119, 240, 220)
    case 2:
      rounded(34, 86, 326, 277, 12, 0xF6F1DD); langerhansSentinel(163, 176, 1.44, 0.22, portrait: .display)
      langerhansSample(184, 163, 4.2); langerhansSample(181, 177, 3.2); langerhansDisplay(197, 170); langerhansDisplay(200, 187)
      langerhansRing(208, 179, 17 + 4 * (1 + wave(t - 0.25)), 1.6)
      langerhansCallout("sample", 92, 64, 144, 180, 160); langerhansCallout("display", 255, 303, 161, 214, 189)
      label("langerhans_sentinel_art_cell", 92, 303, 139)
    default:
      rounded(29, 88, 331, 278, 12, 0xF6F1DD); langerhansSentinel(123, 177, 1.46, 0.20, portrait: .contact); langerhansDisplay(162, 176)
      let close = min(1, t / 0.58), x = 241 - 19 * close * close * (3 - 2 * close)
      oval(x - 46, 136, x + 42, 218, fill: 0xB6C7E5, border: 0x4E638A); oval(x - 24, 150, x + 23, 199, fill: 0x889FC8, border: 0x4E638A)
      line(x - 45, 176, x - 49, 176, 0x4E638A, 2.3); line(x - 49, 176, x - 52, 171, 0x4E638A, 1.7); line(x - 49, 176, x - 52, 181, 0x4E638A, 1.7)
      if close >= 0.86 { langerhansRing(170, 176, 10 + 3 * (1 + wave(t - 0.25)), 1.6) }
      langerhansCallout("cell", 88, 69, 140, 117, 164); langerhansCallout("t_cell", 263, 69, 125, x + 14, 146)
      langerhansCallout("contact", 180, 311, 153, 170, 191)
    }
  }
  private func langerhansSentinel(_ x: Double, _ y: Double, _ scale: Double, _ reach: Double, portrait: SentinelPortrait = .tissue) {
    typealias G = GalaxySSIHealthAtlasLangerhansGeometry
    var local = context; local.translateBy(x: x, y: y); local.scaleBy(x: scale, y: scale); let art = copy(local)
    let inTissue = portrait == .tissue, length = inTissue ? 74.0 : 52.0
    var tip = Path(); tip.move(to: CGPoint(x: 3, y: -12))
    tip.addCurve(to: CGPoint(x: 12, y: -length - 15 * reach), control1: CGPoint(x: -7, y: -33), control2: CGPoint(x: 15, y: -48))
    tip.move(to: CGPoint(x: 8, y: -40)); tip.addQuadCurve(to: CGPoint(x: -17, y: 15 - length - 7 * reach), control: CGPoint(x: -1, y: -46))
    tip.move(to: CGPoint(x: -14, y: -8))
    if inTissue {
      tip.addCurve(to: CGPoint(x: -47, y: -59 - 6 * reach), control1: CGPoint(x: -28, y: -14), control2: CGPoint(x: -33, y: -50))
      tip.move(to: CGPoint(x: -30, y: -36)); tip.addQuadCurve(to: CGPoint(x: -40, y: -49), control: CGPoint(x: -35, y: -39))
    } else {
      tip.addCurve(to: CGPoint(x: -58, y: -39 - 6 * reach), control1: CGPoint(x: -38, y: -10), control2: CGPoint(x: -31, y: -33))
      tip.move(to: CGPoint(x: -35, y: -24)); tip.addQuadCurve(to: CGPoint(x: -63, y: -21), control: CGPoint(x: -46, y: -17))
    }
    art.langerhansBranch(inTissue ? G.tissueBranches : G.detailBranches)
    if portrait == .display { art.langerhansBranch(G.displayBranches) }
    art.langerhansBranch(tip); art.fill(G.body, Self.sentinelFill); art.stroke(G.body, Self.sentinelEdge, 1.5)
    art.oval(-12, -13, 9, 12, fill: 0x498C84, border: Self.sentinelEdge)
  }
  private func langerhansBranch(_ path: Path) { stroke(path, Self.sentinelEdge, 7); stroke(path, Self.sentinelFill, 4.6) }
  private func langerhansKeratinocyte(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double, _ light: Bool) {
    var local = context; local.translateBy(x: x, y: y); local.scaleBy(x: rx, y: ry); let art = copy(local)
    art.fill(GalaxySSIHealthAtlasLangerhansGeometry.keratinocyte, light ? 0xF3C8AE : 0xEDB39E)
    art.stroke(GalaxySSIHealthAtlasLangerhansGeometry.keratinocyte, Self.keratinEdge, 1.2 / rx)
    oval(x - 0.2 * rx, y - 0.32 * ry, x + 0.24 * rx, y + 0.25 * ry, fill: 0xBC8184, border: Self.keratinEdge)
  }
  private func langerhansDisplay(_ x: Double, _ y: Double) {
    line(x, y, x + 4, y, Self.sentinelEdge, 2.4); line(x + 4, y - 3, x + 4, y + 3, Self.sentinelEdge, 1.8)
    langerhansSample(x + 7, y, 3.5)
  }
  private func langerhansSample(_ x: Double, _ y: Double, _ size: Double) {
    var local = context; local.translateBy(x: x, y: y); local.scaleBy(x: size, y: size); let art = copy(local)
    art.fill(GalaxySSIHealthAtlasLangerhansGeometry.diamond, Self.sampleFill)
    art.stroke(GalaxySSIHealthAtlasLangerhansGeometry.diamond, Self.sampleEdge, 1.15 / size)
  }
  private func langerhansRing(_ x: Double, _ y: Double, _ r: Double, _ width: Double) {
    stroke(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), Self.sampleEdge, width)
  }
  private func langerhansCallout(_ key: String, _ x: Double, _ y: Double, _ width: Double, _ tipX: Double, _ tipY: Double) {
    line(x, y > tipY ? y - 15 : y + 5, tipX, tipY, 0x526064, 1.1)
    disc(tipX, tipY, 2.1, Self.cream, border: 0x526064); label("langerhans_sentinel_art_" + key, x, y, width)
  }
}
