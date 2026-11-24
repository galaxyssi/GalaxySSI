import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func ankleScene(_ step: Int, _ t: Double) {
    let phase = GalaxySSIHealthAtlasFunctionCatalogue.Story.safePhase(t)
    let ease = phase * phase * (3 - 2 * phase)
    switch step {
    case 0: ankleOverview(sin(phase * .pi))
    case 1: ankleCradle(0, sin(phase * .pi))
    case 2: ankleSide(16 * ease, advancing: true)
    case 3: ankleCradle(ease * 10, 1)
    default: ankleSide(16 * (1 - ease), advancing: false)
    }
  }
  private func ankleOverview(_ highlight: Double) {
    let geometry = GalaxySSIHealthAtlasAnkleGeometry.self
    var local = context; local.translateBy(x: 18, y: -8)
    let art = copy(local)
    art.ankleSurface(geometry.overviewTibia, 0xF6DBAD, 0xD2AA7C, 0x9C7F6C, 36, 251)
    art.ankleSurface(geometry.overviewFibula, 0xD7E6EA, 0xA3BDCC, 0x627D91, 65, 252)
    art.stroke(Path { p in
      p.move(to: CGPoint(x: 158, y: 88))
      p.addCurve(to: CGPoint(x: 159, y: 209), control1: CGPoint(x: 164, y: 117), control2: CGPoint(x: 164, y: 169))
    }, 0xFFF1CD, 3.2)
    art.line(217, 111, 209, 193, 0xE8F4F5, 2.8)
    art.ankleSurface(geometry.tarsus, 0xE7A99B, 0xCF858A, 0x976477, 256, 281)
    local.opacity = Double(Int(95 + highlight * 140)) / 255
    copy(local).stroke(Path(ellipseIn: CGRect(x: 129, y: 219, width: 95, height: 66)), 0x458E84, 2 + 2 * highlight)
    ankleCallout("tibia", 55, 107, 164, 103, left: true)
    ankleCallout("fibula", 306, 112, 237, 114, left: false)
    ankleCallout("ankle", 286, 287, 229, 244, left: false)
  }
  private func ankleCradle(_ shift: Double, _ emphasis: Double) {
    let geometry = GalaxySSIHealthAtlasAnkleGeometry.self
    ankleSurface(geometry.cradleTibia, 0xF6DBAD, 0xD2AA7C, 0x9C7F6C, 52, 214)
    stroke(Path { p in
      p.move(to: CGPoint(x: 106, y: 78)); p.addQuadCurve(to: CGPoint(x: 112, y: 168), control: CGPoint(x: 120, y: 115))
    }, 0xFFF0CD, 4)
    ankleSurface(geometry.cradleFibula(shift), 0xD7E6EA, 0xA3BDCC, 0x627D91, 57, 223)
    line(215 + shift, 83, 208 + shift, 134, 0xE5F2F4, 3)
    for index in 0..<3 {
      let y = 115 + Double(index) * 10
      line(190, y, 202 + shift, y + 9, 0xAF9093, 2.4)
    }
    ankleSurface(geometry.talus, 0xE7A99B, 0xCF858A, 0x976477, 186, 243)
    stroke(Path { p in
      p.move(to: CGPoint(x: 132, y: 196)); p.addQuadCurve(to: CGPoint(x: 191, y: 201), control: CGPoint(x: 159, y: 183))
    }, 0xE6D1AA, 2.5 + emphasis * 1.6)
    if shift > 0.2 {
      arrow(206, 254, 206 + shift * 2.4 + 10, 254, 0x458E84)
      label("ankle_mortise_exaggerated", 181, 287, 270)
    }
    ankleCallout("tibia", 70, 117, 121, 109, left: true)
    ankleCallout("fibula", 283, 95, 223 + shift, 84, left: false)
    ankleCallout("syndesmosis", 294, 160, 196 + shift / 2, 129, left: false)
    ankleCallout("talus", 86, 251, 151, 223, left: true)
  }
  private func ankleSide(_ angle: Double, advancing: Bool) {
    let geometry = GalaxySSIHealthAtlasAnkleGeometry.self
    ankleSurface(geometry.sideTibia, 0xF6DBAD, 0xD2AA7C, 0x9C7F6C, 65, 185)
    var local = context
    local.translateBy(x: 157, y: 190); local.rotate(by: .degrees(-angle)); local.translateBy(x: -157, y: -190)
    let art = copy(local)
    art.ankleSurface(geometry.foot, 0xF6DBAD, 0xD2AA7C, 0x9C7F6C, 195, 250)
    art.ankleSurface(geometry.contact, 0xE7A99B, 0xCF858A, 0x976477, 185, 214)
    art.stroke(Path { p in
      p.move(to: CGPoint(x: 193, y: 222)); p.addQuadCurve(to: CGPoint(x: 254, y: 234), control: CGPoint(x: 229, y: 221))
    }, 0xFFEDCB, 3)
    disc(157, 190, 4, 0x458E84, border: Self.cream)
    if advancing { arrow(293, 245, 291, 211, 0x458E84) }
    else { arrow(291, 211, 293, 245, 0x458E84) }
    ankleCallout("ankle", 70, 179, 153, 185, left: true)
    ankleCallout("tibia", 261, 107, 175, 105, left: false)
    label(advancing ? "ankle_mortise_dorsiflex" : "ankle_mortise_neutral", 189, 297, 272)
  }
  private func ankleSurface(_ path: Path, _ light: UInt32, _ dark: UInt32, _ border: UInt32, _ top: Double, _ bottom: Double) {
    gradient(path, top, bottom, light, dark); stroke(path, border, 1.8)
  }
  private func ankleCallout(_ key: String, _ tx: Double, _ ty: Double, _ x: Double, _ y: Double, left: Bool) {
    line(tx + (left ? 19 : -19), ty + 4, x, y, 0x758C91, 1)
    disc(x, y, 3, 0x458E84, border: Self.cream)
    label("ankle_mortise_" + key, tx, ty, 118)
  }
}
