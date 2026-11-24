import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func microgliaBackground(_ step: Int, _ t: Double) {
    let g = GalaxySSIHealthAtlasMicrogliaGeometry.self
    for (i,p) in g.neuropil.enumerated() {
      stroke(p, i % 2 == 0 ? 0x509490B5 : 0x4091B8AE, 5); stroke(p, 0x99F8FAFC, 1.2)
    }
    for i in 0...45 {
      let x = 18+Double(i*73 % 328), y = 18+Double(i*57 % 319)
      disc(x, y, i % 5 == 0 ? 2.3 : 1.25, 0x5796AAB6)
    }
    microgliaNeuron(59, 93, 0.94, -18); microgliaNeuron(281, 285, 1.05, 165)
    if step == 0 {
      microgliaNeuron(287, 77, 0.64, 16)
      var c = context; c.translateBy(x: 286, y: 217); c.rotate(by: .degrees(151))
      c.scaleBy(x: 0.48, y: 0.48); c.translateBy(x: -153, y: -172)
      copy(c).microgliaArbor(0, t+0.31)
    }
  }
  private func microgliaNeuron(_ x: Double, _ y: Double, _ size: Double, _ angle: Double) {
    var c = context; c.translateBy(x: x, y: y); c.rotate(by: .degrees(angle)); c.scaleBy(x: size, y: size)
    let art = copy(c), p = GalaxySSIHealthAtlasMicrogliaGeometry.neuron
    art.gradient(p, -28, 32, 0xDDD9EB, 0xAEA8C9); art.stroke(p, 0x8E86AD, 1.2)
    art.oval(-15, -12, 15, 11, fill: 0xADA6C9, border: 0x8E86AD); art.disc(2, -1, 3.6, 0x82729D)
    for i in -1...1 { art.line(-10+6*Double(i), 15, -7+6*Double(i), 14, 0xE5E1F0, 1.9) }
  }
}
