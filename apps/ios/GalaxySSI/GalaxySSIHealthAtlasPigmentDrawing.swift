import SwiftUI

private typealias PigmentInk = GalaxySSIHealthAtlasOcularInk

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func pigmentScene(step: Int, t: Double) {
    switch step {
    case 1: pigmentPhoton(t)
    case 3: pigmentConversion(t)
    default: pigmentSection(step: step, t: t)
    }
  }
  private func pigmentSection(step: Int, t: Double) {
    label("ocular_pigment_rod", 174, 46, 240); rounded(32, 229, 328, 305, 15, 0xE0CCD8)
    for i in 0...5 {
      let x = Double(53 + i * 50)
      oval(x - 24, 233, x + 24, 294, top: 232, bottom: 294, from: 0x987DA2, to: 0x5C496B, border: Self.violet)
      disc(x, 272, 7, 0xD2B6CB, border: Self.cream)
      for j in -2...2 {
        let xpos = x + Double(j) * 7
        line(xpos, 237, xpos + Double(j - 1) * 0.7, Double(224 - (j & 1) * 4), Self.violet, 1.8)
      }
    }
    for k in 0...2 {
      let x = Double(99 + k * 82)
      ocularRod(x, 78, 174, 23)
      if step == 0 { disc(x, 99 + 55 * (t + Double(k) * 0.22).truncatingRemainder(dividingBy: 1), 4.1, PigmentInk.cisRetinal, border: Self.cream) }
    }
    if step == 2 || step == 4 {
      let returning = step == 4, color = returning ? PigmentInk.cisRetinal : PigmentInk.retinol, x = 181.0
      arrow(x + 29, returning ? 224 : 182, x + 29, returning ? 182 : 222, color)
      for i in 0...2 {
        let y = GalaxySSIHealthAtlasOcularMotion.transfer(GalaxySSIHealthAtlasOcularMotion.relayFraction(t, index: i), returnToRod: returning)
        ocularMolecule(x + Double(i) * 7 - 7, y, 0.43, returning ? 0.6 : 0, color)
      }
      label(returning ? "ocular_pigment_cis" : "ocular_pigment_trans_retinol", 263, 210, 83)
    }
    label("ocular_pigment_rpe", 183, 331, 234)
  }
  private func pigmentPhoton(_ t: Double) {
    label("ocular_pigment_photon", 174, 45, 184)
    let y = 58 + 63 * t
    var photon = Path(); photon.move(to: CGPoint(x: 164, y: y)); photon.addLine(to: CGPoint(x: 178, y: y + 8))
    photon.addLine(to: CGPoint(x: 171, y: y + 14)); photon.addLine(to: CGPoint(x: 186, y: y + 23)); stroke(photon, PigmentInk.retinol, 2.6)
    oval(75, 131, 291, 255, top: 126, bottom: 252, from: 0xCBDDD6, to: 0x7CAE9C, border: PigmentInk.transmit)
    oval(132, 166, 236, 218, fill: Self.cream, border: PigmentInk.transmit)
    let moved = min(1, max(0, (t - 0.34) / 0.58))
    ocularMolecule(184, 193, 1.85, 0.88 * (1 - moved), t < 0.42 ? PigmentInk.cisRetinal : PigmentInk.retinol)
    label("ocular_pigment_opsin", 182, 286, 172); label(t < 0.42 ? "ocular_pigment_cis" : "ocular_pigment_trans_retinal", 182, 322, 220)
  }
  private func pigmentConversion(_ t: Double) {
    label("ocular_pigment_rpe", 183, 46, 240); rounded(26, 81, 334, 271, 24, 0xDCCEE2)
    let y = 172.0
    arrow(92, y, 151, y, PigmentInk.retinol); arrow(211, y, 273, y, PigmentInk.cisRetinal)
    disc(72, y, 24, 0xF0DED0, border: PigmentInk.retinol); disc(183, y, 24, 0xF1E8DA, border: Self.sienna); disc(292, y, 24, 0xCDE5D9, border: PigmentInk.cisRetinal)
    ocularMolecule(73 + 219 * t, 141, 0.9, 0.72 * min(1, max(0, (t - 0.52) * 2.1)), t < 0.67 ? PigmentInk.retinol : PigmentInk.cisRetinal)
    label("ocular_pigment_trans_retinol", 73, 221, 91); label("ocular_pigment_ester", 183, 221, 91); label("ocular_pigment_cis", 292, 221, 86)
    ocularScientificText("RPE65", 238, 117)
  }
}
