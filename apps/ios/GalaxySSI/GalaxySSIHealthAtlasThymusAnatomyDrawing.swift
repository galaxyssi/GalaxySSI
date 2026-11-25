import SwiftUI

private typealias ThymusAnatomy = GalaxySSIHealthAtlasThymusShapes

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func thymusAnatomy() {
    fill(ThymusAnatomy.shoulders,0xF5EAE4); stroke(ThymusAnatomy.shoulders,0xBCA7A0,1.15)
    fill(ThymusAnatomy.lung,0xC6E1DF)
    var mirror = context; mirror.translateBy(x: 103, y: 0); mirror.scaleBy(x: -1, y: 1)
    copy(mirror).fill(ThymusAnatomy.lung,0xC6E1DF)
    fill(ThymusAnatomy.thymicLobe,0xD995AA); stroke(ThymusAnatomy.thymicLobe,ThymusAnatomy.capsuleEdge,1.1)
    var lobe = context; lobe.translateBy(x: 51.5, y: 67); lobe.scaleBy(x: -1, y: 1.04); lobe.translateBy(x: -51.5, y: -67)
    copy(lobe).fill(ThymusAnatomy.thymicLobe,0xE5A9B8); copy(lobe).stroke(ThymusAnatomy.thymicLobe,ThymusAnatomy.capsuleEdge,1.1)
    line(61,78,115,115,0xA38591,1.15)
    gradient(ThymusAnatomy.tissue,80,296,0xF5D8DF,0xDFA8BB); stroke(ThymusAnatomy.tissue,ThymusAnatomy.capsuleEdge,1.8)
    var cortex = context; cortex.clip(to: ThymusAnatomy.tissue)
    let cortical = copy(cortex)
    for row in 0...13 {
      for col in 0...15 {
        let seed = (row * 17 + col * 13) % 7
        let x = 88 + 15 * col + (row % 2) * 5 - seed, y = 88 + 15 * row + seed
        cortical.disc(Double(x),Double(y),1.2 + Double(seed) * 0.13,0xC98DA6)
      }
    }
    gradient(ThymusAnatomy.medulla,139,266,0xFFECD6,0xF3CCAF); stroke(ThymusAnatomy.medulla,ThymusAnatomy.medullaEdge,1.8)
    var medulla = context; medulla.clip(to: ThymusAnatomy.medulla)
    let medullary = copy(medulla)
    for row in 0...5 {
      for col in 0...5 {
        let x = 146 + 22 * col - row % 2 * 6, y = 151 + 21 * row + (col * 11 % 7)
        medullary.disc(Double(x),Double(y),1.4,0xDAAB9B)
      }
    }
    stroke(ThymusAnatomy.entryVessel,ThymusAnatomy.capsuleEdge,13.5); stroke(ThymusAnatomy.entryVessel,0xF5D5D7,10.5)
    stroke(ThymusAnatomy.exitVessel,ThymusAnatomy.vesselBlue,13.5); stroke(ThymusAnatomy.exitVessel,0xD1E7EE,10.5)
  }
  func thymusLabels() {
    label("thymus_story_thymus",51,29,94)
    label("thymus_story_lobule",157,51,111); thymusLeader(157,58,157,72,157,84)
    label("thymus_story_cortex",285,53,95); thymusLeader(285,60,285,82,272,113)
    label("thymus_story_medulla",327,242,60); thymusLeader(327,229,287,215,251,205)
    label("thymus_story_blood_vessel",286,316,123); thymusLeader(286,303,286,298,279,290)
  }
  func thymusLeader(_ x: Double, _ y: Double, _ elbowX: Double, _ elbowY: Double, _ tx: Double, _ ty: Double) {
    line(x,y,elbowX,elbowY,ThymusAnatomy.guide,1); line(elbowX,elbowY,tx,ty,ThymusAnatomy.guide,1)
    disc(tx,ty,1.6,ThymusAnatomy.guide)
  }
}
