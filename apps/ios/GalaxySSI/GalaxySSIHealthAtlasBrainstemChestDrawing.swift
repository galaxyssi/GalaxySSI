import SwiftUI

private typealias BrainstemChest = GalaxySSIHealthAtlasBrainstemShapes

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func brainstemChest(_ expansion: Double, contracting: Bool) {
    for side in 0...1 {
      var local = context; local.translateBy(x: 181, y: 0); local.scaleBy(x: side == 0 ? -1 : 1, y: 1)
      let art = copy(local)
      var ribs = Path()
      for i in 0...4 {
        let y = 175 + Double(i) * 21
        ribs.move(to: CGPoint(x: 6, y: y))
        ribs.addCurve(to: CGPoint(x: 68, y: y + 13), control1: CGPoint(x: 31, y: y - 12), control2: CGPoint(x: 63, y: y - 7))
      }
      art.stroke(ribs,0xE2B6A9,2)
      let lung = BrainstemChest.lung(expansion,side: side)
      art.gradient(lung,168,290,0xFFE1D8,0xE9B0B2); art.stroke(lung,0xB77887,1.3)
      local.clip(to: lung)
      var fissures = Path()
      fissures.move(to: CGPoint(x: 5, y: 214)); fissures.addQuadCurve(to: CGPoint(x: 63, y: 241), control: CGPoint(x: 35, y: 222))
      if side == 0 {
        fissures.move(to: CGPoint(x: 22, y: 226)); fissures.addQuadCurve(to: CGPoint(x: 61, y: 213), control: CGPoint(x: 45, y: 220))
      }
      copy(local).stroke(fissures,0xCE939D,1.2)
    }
    let diaphragm = BrainstemChest.diaphragm(expansion)
    stroke(diaphragm,BrainstemChest.muscle,contracting ? 8 : 7)
    stroke(diaphragm,contracting ? 0xEFAC9A : 0xEDC0AE,4.3)
  }
}
