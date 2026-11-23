import SwiftUI

extension GalaxySSIHealthAtlasInsulinDrawing {
  func scene(_ motion: Motion) {
    switch motion.chapter {
    case 0: glucoseEntry(motion.fraction)
    case 1: potassiumGate(motion)
    case 2: calciumGate(motion)
    case 3: granuleRelease(motion)
    default: bloodTransport(motion.fraction)
    }
  }
  private func glucoseEntry(_ t: Double) {
    cellCutaway(129, gate: 116); channel(116, 129, Self.glucose, 1)
    label(86, 57, "glucose"); leader(260, 88, 139, 124, "transporter", Self.glucose)
    for i in 0...4 {
      let f = Motion.wrap(t * 1.06 + Double(i) / 5), x = 116 + 14 * sin(6.2 * f) * (f > 0.50 ? 1.4 : 1)
      sugar(x, 75 + 110 * f)
    }
    mitochondrion()
    for i in 0...3 {
      let f = Motion.wrap(t * 1.51 + Double(i) / 4)
      particle(218 + 45 * f, 216 + (Double(i) - 1.5) * (3 + 7 * f), Self.energy, 3)
    }
    label(227, 283, "energy")
  }
  private func potassiumGate(_ motion: Motion) {
    cellCutaway(146, gate: 182)
    let t = motion.fraction, open = Motion.potassiumOpen(t)
    channel(182, 146, Self.potassium, open); label(84, 79, "potassium")
    label(250, 61, open >= 0.4 ? "k_open" : "k_closed")
    for p in motion.potassiumParticles { particle(p.x, p.y, Self.potassium, 4) }
    for i in 0...3 { particle(238 + 51 * Motion.wrap(t * 1.2 + Double(i) / 4), Double(202 + i * 10), Self.energy, 3) }
    label(243, 275, "energy")
  }
  private func calciumGate(_ motion: Motion) {
    cellCutaway(146, gate: 182)
    let t = motion.fraction, open = Motion.calciumOpen(t)
    channel(182, 146, Self.calcium, open); label(83, 72, "calcium")
    leader(259, 58, 205, 142, "ca_gate", Self.calcium)
    for p in motion.calciumParticles { particle(p.x, p.y, Self.calcium, 4.2) }
    for i in 0...2 {
      let radius = 13 + 10 * Motion.wrap(t * 1.65 + Double(i) / 3)
      if open > 0.64 { stroke(Path(ellipseIn: CGRect(x: 182 - radius, y: 193 - radius / 2, width: 2 * radius, height: radius)), 0x84287C72, 1.2) }
    }
  }
  private func granuleRelease(_ motion: Motion) {
    let t = motion.fraction, aperture = Motion.aperture(t), centerY = motion.granuleCenterY
    cellCutaway(141, pore: aperture)
    if aperture < 0.09 {
      var local = context; local.translateBy(x: 180, y: centerY); let drawing = copy(local)
      let vesicle = circlePath(0, 0, 31)
      drawing.gradient(vesicle, -35, 35, 0xDEEBEC, 0x83AEBA); drawing.stroke(vesicle, Self.insulin, 1.5)
      drawing.insulinMolecule(0, 0, 1)
    } else {
      for i in 0...2 {
        let f = Motion.release(t, index: i), x = 180 + Double(i - 1) * 37 * f
        insulinMolecule(x, 177 - 94 * f, 0.54)
      }
    }
    for i in 0...4 {
      let f = Motion.wrap(t * 1.5 + Double(i) * 0.2)
      particle(114 + 14 * f + Double(i) * 4, 187 + Double(i) * 9 + f * 5, Self.calcium, 3.1)
    }
    label(265, 55, "hormone")
    leader(192, 286, 190, centerY + (t < 0.54 ? 22 : 10), "granule", Self.insulin)
  }
  private func bloodTransport(_ t: Double) {
    var local = context; local.translateBy(x: 0, y: 47); let drawing = copy(local)
    local.draw(local.resolve(Image("HealthAtlasFunctionIslet")), in: CGRect(x: 0, y: 0, width: 360, height: 280))
    for i in 0...5 {
      let f = Motion.wrap(t * 1.1 + Double(i) / 6)
      if let sample = GalaxySSIHealthAtlasFunctionPath.sample(Motion.bloodRoute, position: f, width: 360, height: 280) {
        drawing.insulinMolecule(sample.point.x, sample.point.y, 0.32)
      }
    }
    leader(154, 65, 184, 126, "beta", Self.calcium); leader(273, 259, 251, 162, "capillary", Self.membrane)
    insulinMolecule(126, 316, 0.55); label(179, 321, "hormone")
  }
}
