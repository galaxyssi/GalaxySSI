import SwiftUI

private typealias AdrenalLocator = GalaxySSIHealthAtlasAdrenalGeometry
private typealias AdrenalLocatorMotion = GalaxySSIHealthAtlasAdrenalMotion

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func adrenalLocate(_ t: Double) {
    gradient(AdrenalLocator.kidney,134,271,0xDFA2A3,0xBD7780); stroke(AdrenalLocator.kidney,AdrenalLocator.medullaInk,1.7)
    oval(53,162,92,248,fill: 0xD9989E,border: 0xCC8791); line(107,203,138,213,0xC08286,4)
    gradient(AdrenalLocator.gland,97,254,0xF6DBA3,0xDFA26C); stroke(AdrenalLocator.gland,AdrenalLocator.rim,1.7)
    line(121,123,197,138,AdrenalLocator.guide,1); line(121,143,167,201,AdrenalLocator.guide,1)
    gradient(AdrenalLocator.cortex,97,254,0xF6DBA3,0xDFA26C); stroke(AdrenalLocator.cortex,AdrenalLocator.rim,1.7)
    var radial = context; radial.clip(to: AdrenalLocator.cortex)
    let rind = copy(radial)
    for i in 0...17 { at(AdrenalLocator.cortexRoute,Double(i) / 18) { x, y in rind.line(x,y,244,186,0xC48961,1) } }
    gradient(AdrenalLocator.medulla,130,223,0xE8B9B7,0xC78E9D); stroke(AdrenalLocator.medulla,AdrenalLocator.medullaInk,1.7)
    for i in 0...8 {
      let x = 215 + Double(i) * 7.5, y = 182 + 12 * wave(0.11 * Double(i))
      oval(x - 3,y - 2,x + 3,y + 2,fill: 0xD4A4AD,border: 0xB57D8C)
    }
    let frame = AdrenalLocatorMotion.locator(t), edge = frame.outer ? AdrenalLocator.cortex : AdrenalLocator.medulla
    if frame.end > 0 { adrenalAlpha(frame.alpha).stroke(edge.trimmedPath(from: 0,to: CGFloat(frame.end)),frame.outer ? 0x985528 : AdrenalLocator.cargo,3.2) }
    adrenalLeader("adrenal_medulla_story_art_gland",80,77,119,96,111)
    adrenalLeader("adrenal_medulla_story_art_kidney",76,302,100,72,256)
    adrenalLeader("adrenal_medulla_story_art_cortex",264,67,112,268,115)
    adrenalLeader("adrenal_medulla_story_art_medulla",249,292,116,248,201)
  }
}
