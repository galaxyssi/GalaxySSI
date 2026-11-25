import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func smellScene(step: Int, t: Double) {
    switch step {
    case 0: nasal(t)
    case 1, 2: smellReceptors(active: step == 2, t: t)
    case 3: smellBulb(t)
    default: corticalPattern(t)
    }
  }
  private func nasal(_ t: Double) {
    var face = Path(); face.move(to: CGPoint(x: 291, y: 319))
    face.addCurve(to: CGPoint(x: 325, y: 210), control1: CGPoint(x: 264, y: 280), control2: CGPoint(x: 296, y: 269))
    face.addCurve(to: CGPoint(x: 258, y: 44), control1: CGPoint(x: 351, y: 157), control2: CGPoint(x: 325, y: 62))
    face.addCurve(to: CGPoint(x: 100, y: 125), control1: CGPoint(x: 183, y: 19), control2: CGPoint(x: 107, y: 51))
    face.addCurve(to: CGPoint(x: 58, y: 219), control1: CGPoint(x: 95, y: 177), control2: CGPoint(x: 67, y: 192))
    face.addQuadCurve(to: CGPoint(x: 95, y: 233), control: CGPoint(x: 57, y: 232))
    face.addQuadCurve(to: CGPoint(x: 102, y: 247), control: CGPoint(x: 103, y: 235))
    face.addQuadCurve(to: CGPoint(x: 136, y: 254), control: CGPoint(x: 108, y: 257))
    face.addQuadCurve(to: CGPoint(x: 113, y: 276), control: CGPoint(x: 105, y: 264))
    face.addCurve(to: CGPoint(x: 208, y: 309), control1: CGPoint(x: 112, y: 307), control2: CGPoint(x: 165, y: 303))
    face.addLine(to: CGPoint(x: 221, y: 332)); face.closeSubpath()
    chemicalFigure(face, 42, 304, 0xFFE6D3, 0xE0A4A5, Self.coral)
    var cavity = Path(); cavity.move(to: CGPoint(x: 84, y: 216))
    cavity.addCurve(to: CGPoint(x: 152, y: 128), control1: CGPoint(x: 116, y: 199), control2: CGPoint(x: 121, y: 153))
    cavity.addCurve(to: CGPoint(x: 244, y: 116), control1: CGPoint(x: 170, y: 105), control2: CGPoint(x: 219, y: 100))
    cavity.addCurve(to: CGPoint(x: 251, y: 232), control1: CGPoint(x: 264, y: 155), control2: CGPoint(x: 265, y: 214))
    cavity.addQuadCurve(to: CGPoint(x: 207, y: 236), control: CGPoint(x: 222, y: 244))
    cavity.addCurve(to: CGPoint(x: 84, y: 216), control1: CGPoint(x: 177, y: 213), control2: CGPoint(x: 119, y: 234)); cavity.closeSubpath()
    chemicalFigure(cavity, 100, 276, 0xEBF4EF, 0xB8D1CE, Self.blue)
    for i in 0...2 {
      var concha = Path(); concha.move(to: CGPoint(x: Double(218 + i * 6), y: Double(143 + 28 * i)))
      concha.addCurve(to: CGPoint(x: Double(153 + i * 5), y: Double(167 + 24 * i)),
        control1: CGPoint(x: 206, y: Double(136 + 30 * i)), control2: CGPoint(x: 163, y: Double(147 + 29 * i))); stroke(concha, 0x8FB4B5, 5.5)
    }
    line(181, 114, 231, 112, Self.teal, 5.5)
    let airway = GalaxySSIHealthAtlasChemicalSenseMotion.airway
    stroke(GalaxySSIHealthAtlasSectionLessonView.path(airway, width: 360, height: 360), 0x8AB4BE, 1.8)
    chemicalParticles(airway, t, Self.sienna, 5)
    chemicalLeader("sense_smell_patch", 185, 70, 205, 111, Self.teal); chemicalLeader("sense_smell_cavity", 273, 268, 235, 227, Self.blue)
  }
  private func smellReceptors(active: Bool, t: Double) {
    typealias Motion = GalaxySSIHealthAtlasChemicalSenseMotion
    var mirrored = context; mirrored.translateBy(x: 0, y: 360); mirrored.scaleBy(x: 1, y: -1); let drawing = copy(mirrored)
    drawing.rounded(27, 162, 333, 249, 17, 0xF6D8CD); drawing.rounded(27, 120, 333, 160, 17, 0xC5DDDA)
    for i in 0...7 {
      let x = Double(48 + i * 38)
      drawing.oval(x - 15, 189, x + 15, 238, fill: Self.peach, border: Self.coral); drawing.disc(x, 218, 5, Self.violet)
    }
    for i in 0...2 {
      let x = Double(80 + i * 99)
      drawing.line(x, 221, x, 278, Self.teal, 4.3)
      drawing.oval(x - 12, 176, x + 12, 222, top: 110, bottom: 275, from: 0xDBEFE9, to: 0x8EB7AA, border: Self.teal)
      drawing.line(x, 175, x, 147, Self.teal, 3.5)
      for side in [-1.0, 1.0] {
        for j in 0...2 {
          var cilium = Path(); cilium.move(to: CGPoint(x: x, y: 145))
          cilium.addQuadCurve(to: CGPoint(x: x + side * Double(24 + 7 * j), y: Double(138 - j * 5)),
            control: CGPoint(x: x + side * 10, y: Double(133 + j * 6))); drawing.stroke(cilium, Self.teal, 1.4)
        }
      }
      for j in 0...2 {
        let f = Motion.transfer(t, index: j)
        drawing.disc(x + Double(j - 1) * 12 + 3 * wave(t + Double(i)), 79 + 53 * f - Double(j) * 11, 3.2, Self.sienna, border: Self.cream)
      }
      if active && i != 1 {
        let f = Motion.transfer(t, index: 0, startsAt: 0.2)
        drawing.disc(x, 149 + 118 * f, 5.1, Self.violet, border: Self.cream)
      }
    }
    chemicalLeader("sense_smell_cilia", 83, 314, 55, 216, Self.teal); chemicalLeader("sense_smell_layer", 269, 314, 311, 236, Self.blue)
  }
  private func smellBulb(_ t: Double) {
    typealias Motion = GalaxySSIHealthAtlasChemicalSenseMotion
    let variants = Motion.odorChannels(false), colors = [Self.blue, Self.violet, Self.teal]
    oval(34, 58, 326, 110, top: 42, bottom: 304, from: 0xFFE6D3, to: 0xE0A4A5, border: Self.coral)
    rounded(24, 126, 336, 148, 7, 0xDCC49E)
    label("sense_smell_bulb_label", 180, 43, 164); label("sense_smell_plate", 222, 170, 83); line(222, 155, 222, 148, Self.sienna, 1.25)
    for i in 0...2 {
      let x = Double(79 + i * 94), color: UInt32 = variants.contains(i) ? colors[i] : 0xA1B4AE
      disc(x, 137, 6, Self.cream)
      stroke(GalaxySSIHealthAtlasSectionLessonView.path(Motion.smellRoutes[i], width: 360, height: 360), color, 3.5)
      disc(x, 88, 13, color, border: Self.cream)
      oval(x - 13, 216, x + 13, 245, top: 110, bottom: 275, from: 0xDBEFE9, to: 0x8EB7AA, border: Self.teal)
      if variants.contains(i) { chemicalParticles(Motion.smellRoutes[i], t, color, 3) }
    }
    label("sense_smell_patch", 180, 295, 240)
  }
  private func corticalPattern(_ t: Double) {
    let variants = GalaxySSIHealthAtlasChemicalSenseMotion.odorChannels(t > 0.52), colors = [Self.blue, Self.violet, Self.teal]
    oval(23, 74, 115, 277, top: 42, bottom: 304, from: 0xFFE6D3, to: 0xE0A4A5, border: Self.coral)
    var cortex = Path(); cortex.move(to: CGPoint(x: 290, y: 80))
    cortex.addCurve(to: CGPoint(x: 283, y: 145), control1: CGPoint(x: 273, y: 101), control2: CGPoint(x: 304, y: 123))
    cortex.addCurve(to: CGPoint(x: 289, y: 219), control1: CGPoint(x: 261, y: 169), control2: CGPoint(x: 311, y: 194))
    cortex.addCurve(to: CGPoint(x: 295, y: 280), control1: CGPoint(x: 275, y: 234), control2: CGPoint(x: 306, y: 252))
    stroke(cortex, 0xAE83A5, 25); stroke(cortex, 0xE0BAD7, 16)
    for i in 0...2 {
      let y = Double(116 + i * 59), color: UInt32 = variants.contains(i) ? colors[i] : 0x9DABA8
      disc(69, y, 13, color, border: Self.cream); line(82, y, 285, y, color, 2.1)
      if variants.contains(i) { disc(92 + 177 * (t * 2.1).truncatingRemainder(dividingBy: 1), y, 5.1, color, border: Self.cream) }
    }
    label("sense_smell_bulb_label", 71, 314, 128); label("sense_smell_cortex", 278, 314, 142)
  }
}
