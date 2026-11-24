import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func cholangiocyteCell(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ focus: Bool) {
    var c = context
    c.translateBy(x: x, y: y); c.scaleBy(x: w/60, y: h/95)
    let art = copy(c), g = GalaxySSIHealthAtlasCholangiocyteGeometry.self
    art.gradient(g.cellShape, 0, 95, focus ? 0xF5E8D8 : 0xF5E8E6, focus ? 0xD5ADC4 : 0xD2B8CC)
    art.stroke(g.cellShape, 0x826779, 1.15); art.stroke(g.cellRelief, 0xFBF0EC, 1.6)
    art.oval(18, 53, 40, 81, top: 52, bottom: 81, from: 0xD6BAD6, to: 0x9F82AD, border: 0x886993)
    art.disc(31, 63, 2.4, 0x7B6191)
    art.line(7, 3, 53, 3, 0x648986, 1.8)
    for i in 0...6 {
      let xx = 9 + Double(i)*6.7
      art.line(xx, 3, xx-0.35, i % 3 == 0 ? -2.5 : -1, 0x527B79, 0.85)
    }
    art.disc(2, 8, 2, 0x7C6B82); art.disc(58, 8, 2, 0x7C6B82)
  }
  func cholangiocyteCloseWall() {
    let g = GalaxySSIHealthAtlasCholangiocyteGeometry.self
    gradient(g.closeField, 90, 155, 0xF3F5DC, 0xCCDEC4); stroke(g.closeField, 0xA9C0A6, 1.15)
    gradient(g.tissueField, 239, 297, 0xCECBDC, 0xF2E8E6); stroke(g.tissueField, 0xB9ACBD, 1.15)
    stroke(g.fibers, 0xB8ADC6, 1.6)
    cholangiocyteCell(46, 152, 80, 95, false)
    cholangiocyteCell(126, 151, 109, 98, true)
    cholangiocyteCell(235, 150, 78, 97, false)
  }
}
