import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  private func toothJawContext(_ angle: Double) -> GraphicsContext {
    var local = context
    local.translateBy(x: 307, y: 136); local.rotate(by: .degrees(angle)); local.translateBy(x: -307, y: -136)
    return local
  }
  func toothProfileBones(_ angle: Double) {
    typealias Geometry = GalaxySSIHealthAtlasToothGeometry
    toothArea(Geometry.profileVault, 0xEFD2AA, 0xA77C67, 1.5)
    toothArea(Geometry.profileUpperGum, 0xDC9B97, 0x986A70, 1.2)
    let art = copy(toothJawContext(angle))
    art.toothArea(Geometry.profileJaw, 0xEFD2AA, 0xA77C67, 1.55)
    art.stroke(Geometry.profileJawContour, 0xCEA687, 1.6)
    art.toothArea(Geometry.profileLowerGum, 0xEFBDB3, 0x986A70, 1.2)
  }
  func toothProfileCrowns(_ angle: Double, focus: GalaxySSIHealthAtlasToothAnatomyData.Kind) {
    for tooth in GalaxySSIHealthAtlasToothAnatomyData.profile {
      toothCrown(tooth.kind, tooth.x, tooth.y, tooth.w, tooth.h, focus: tooth.kind == focus)
    }
    let art = copy(toothJawContext(angle))
    for tooth in GalaxySSIHealthAtlasToothAnatomyData.profile {
      art.toothCrown(tooth.kind, tooth.x + 4, 211, tooth.w - 2, -tooth.h + 3, focus: tooth.kind == focus)
    }
    toothCallout("tooth_mastication_story_jaw", 254, 322, 103, 254, 304, 254, 245)
  }
  func toothCrown(_ kind: GalaxySSIHealthAtlasToothAnatomyData.Kind, _ x: Double, _ y: Double, _ w: Double, _ h: Double, focus: Bool) {
    typealias Geometry = GalaxySSIHealthAtlasToothGeometry
    var local = context; local.translateBy(x: x, y: y); local.scaleBy(x: w / 2, y: h)
    let art = copy(local), outline: Path
    switch kind {
    case .incisor: outline = Geometry.cuttingEdge
    case .canine: outline = Geometry.pointedCusp
    case .premolar, .molar: outline = Geometry.grindingCusps
    }
    art.toothArea(outline, focus ? 0xF4FAF1 : 0xFFFCF4, focus ? 0x52676A : 0x8E8073, 0.052)
    art.line(-0.48, 0.23, -0.5, 0.64, 0xE8DECD, 0.055)
    if kind == .molar || kind == .premolar { art.line(-0.06, 0.90, 0.01, 0.45, 0xE8DECD, 0.065) }
  }
}
