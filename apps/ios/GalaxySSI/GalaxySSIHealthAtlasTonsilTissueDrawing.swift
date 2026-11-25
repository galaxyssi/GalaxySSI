import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func tonsilPane(_ path: Path, top: Double = 110, bottom: Double = 301, from: UInt32 = 0xF5D9DF, to: UInt32 = 0xDBADC1, edge: UInt32 = 0x855D67) {
    gradient(path, top, bottom, from, to); stroke(path, edge, 1.5)
  }
  func tonsilPane(_ path: Path, fill: UInt32, edge: UInt32 = 0x855D67) {
    self.fill(path, fill); stroke(path, edge, 1.5)
  }
  func tonsilFollicle(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double) {
    oval(x - rx, y - ry, x + rx, y + ry, top: 155, bottom: 282, from: 0xF3D3DF, to: 0xBF8BA9, border: 0xA9788C)
    oval(x - rx * 0.60, y - ry * 0.64, x + rx * 0.70, y + ry * 0.43, fill: 0xF3D7DF, border: 0xCC9CB2)
    for i in 0...5 {
      let dx = Double(i % 3 - 1) * rx * 0.36 + Double(i / 3) * 2
      let dy = (Double(i / 3) - 0.5) * ry * 0.74 + Double(i % 2) * 2
      disc(x + dx, y + dy, 1.25, 0xA9788C)
    }
  }
  func tonsilAntigen(_ x: Double, _ y: Double, _ radius: Double, edge: UInt32 = 0x9E601D) {
    var local = context
    local.translateBy(x: x, y: y); local.rotate(by: .degrees(-27))
    copy(local).oval(-radius, -0.67 * radius, radius, 0.67 * radius, fill: 0xECC17E, border: edge)
  }
  func tonsilAntigenKey() {
    tonsilAntigen(43, 40, 4.8)
    label("tonsil_story_antigen", 120, 45, 130)
  }
  func tonsilEpithelium(_ path: Path, points: [CGPoint], width: Double = 9) {
    stroke(path, 0x855D67, width + 2); stroke(path, 0xEFB7A5, width)
    for point in points {
      disc(point.x, point.y, 1.35, 0x8F4B66)
      if width > 10 { disc(point.x + 2, point.y + 4, 1.15, 0x8F4B66) }
    }
  }
  func tonsilFocus(_ x: Double, _ y: Double, _ radius: Double, _ color: UInt32, _ strength: Double) {
    guard strength > 0 else { return }
    var local = context; local.opacity *= Double(Int(215 * strength)) / 255
    let r = radius + 4 * (1 - strength)
    copy(local).stroke(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), color, 1.65)
  }
}
