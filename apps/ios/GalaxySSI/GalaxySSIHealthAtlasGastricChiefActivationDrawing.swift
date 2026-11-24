import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func gastricChiefActivate(_ t: Double) {
    typealias Geometry = GalaxySSIHealthAtlasGastricChiefGeometry
    typealias Motion = GalaxySSIHealthAtlasGastricChiefMotion
    let flow = Motion.acidFlow(t)
    gastricChiefTint(Geometry.glandSection, 82, 274, 0xFBE8DA, 0xE5B3AD)
    stroke(Geometry.glandSection, 0x9A6470, 1.45)
    gastricChiefTint(Geometry.sharedLumen, 67, 289, 0xE5F2EC, 0xC2E0DD)
    var acidTint = context; acidTint.opacity *= Double(Int(143 * flow)) / 255
    copy(acidTint).gastricChiefTint(Geometry.sharedLumen, 105, 246, 0xE8AA92, 0xEDCFAC)
    stroke(Geometry.sharedLumen, 0x568184, 1.35)
    oval(43, 229, 118, 267, fill: 0xF4D8C9, border: 0x9A6470)
    oval(246, 91, 315, 133, fill: 0xF4D8C9, border: 0x9A6470)
    fill(Geometry.parietal, 0xEDB4A1); stroke(Geometry.parietal, 0x9A6470, 1.7)
    oval(57, 155, 89, 187, fill: 0xCA8EAA, border: 0x9A6470)
    for i in 0...2 {
      oval(57 + 11 * Double(i), 127 - 4 * Double(i), 65 + 11 * Double(i), 139 - 4 * Double(i), fill: Self.peach, border: 0x9A6470)
    }
    fill(Geometry.canaliculus, 0xD6E9E5)
    line(122, 145, 122, 158, 0xD6E9E5, 5)
    stroke(Geometry.canaliculus, 0x568184, 1.4)
    gastricChiefTint(Geometry.sectionChief, 94, 263, 0xF0E4EF, 0xB5A5D0)
    stroke(Geometry.sectionChief, 0x6D6088, 1.7)
    oval(278, 181, 309, 218, fill: 0xA18BB9, border: 0x6D6088)
    gastricChiefGranule(248, 173, 7.2); gastricChiefGranule(252, 200, 6.7); gastricChiefGranule(248, 225, 7.2)
    for i in 0...3 {
      let f = min(1, max(0, flow * 1.18 - 0.19 * Double(i)))
      if f > 0 {
        at(GalaxySSIHealthAtlasGastricChiefRoutes.acidTrack, f) { x, y in
          disc(x, y + Double(i % 2) * 5, 2.7, 0xA54539, border: Self.cream)
        }
      }
    }
    let first = Motion.activate(t, 0), second = Motion.activate(t, 1)
    gastricChiefMolecule(174, 191 - 7 * first, 11, cleavage: first)
    gastricChiefMolecule(195, 238 - 12 * second, 9, cleavage: second)
  }
}
