import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func toothDentalArch(_ t: Double) {
    typealias Geometry = GalaxySSIHealthAtlasToothGeometry
    gradient(Geometry.palate, 62, 278, 0xDC9B97, 0xEAB0A9)
    stroke(Geometry.palate, 0x986A70, 1.4)
    toothArea(Geometry.palatalVault, 0xEFBDB3, 0xC99491, 1)
    line(180, 118, 180, 255, 0xBE8A88, 1)
    for side in [-1.0, 1] {
      for i in 0...2 {
        let y = 135 + 11 * Double(i)
        line(176 + 2 * (1 + side), y, 180 + side * (24 + 6 * Double(i)), y - 4, 0xC99491, 1.6)
      }
      for tooth in GalaxySSIHealthAtlasToothAnatomyData.halfArch {
        var local = context
        local.translateBy(x: 180 + side * (180 - tooth.x), y: tooth.y)
        local.rotate(by: .degrees(-side * tooth.angle))
        local.scaleBy(x: tooth.w / 2, y: tooth.h / 2)
        let art = copy(local), crown: Path
        switch tooth.kind {
        case .incisor: crown = Geometry.archIncisor
        case .canine: crown = Geometry.archCanine
        case .premolar: crown = Geometry.archPremolar
        case .molar: crown = Geometry.archMolar
        }
        art.toothArea(crown, 0xFFFCF4, 0x8E8073, 0.085)
        let strength = min(1, max(0, 1 - abs(3 * t - Double(tooth.kind.rawValue))))
        if strength > 0 {
          let alpha = Int(160 * strength)
          var wash = local; wash.opacity *= Double(alpha) / 255
          copy(wash).fill(crown, 0x88C8BB)
          var border = local; border.opacity *= Double(alpha + 64) / 255
          copy(border).stroke(crown, 0x3B8175, 0.105)
        }
        if tooth.kind == .molar || tooth.kind == .premolar {
          art.stroke(Geometry.archFissure, 0x8E8073, 0.075)
          if tooth.kind == .molar {
            art.line(0.02, -0.67, 0, -0.09, 0x8E8073, 0.075)
            art.line(0, -0.09, 0.2, 0.6, 0x8E8073, 0.075)
          }
        } else {
          art.line(-0.36, 0.35, 0.36, 0.35, 0xE8DECD, 0.11)
        }
      }
    }
    toothCallout("tooth_mastication_story_incisors", 54, 60, 84, 84, 61, 162, 79)
    toothCallout("tooth_mastication_story_canines", 47, 118, 74, 85, 121, 111, 118)
    toothCallout("tooth_mastication_story_premolars", 315, 159, 81, 310, 166, 257, 176)
    toothCallout("tooth_mastication_story_molars", 312, 242, 76, 301, 249, 256, 247)
  }
}
