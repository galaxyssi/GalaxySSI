import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func intercalatedLabels() {
    label("intercalated_story_label_duct", 180, 29, 245)
    intercalatedLeader(180, 34, 180, 47)
    label("intercalated_story_label_lumen", 71, 105, 90)
    intercalatedLeader(71, 110, 86, 123)
    label("intercalated_story_label_apical", 280, 140, 100)
    intercalatedLeader(244, 136, 216, 145)
    label("intercalated_story_label_principal", 74, 213, 96)
    intercalatedLeader(74, 201, 76, 188)
    label("intercalated_story_label_type_a", 115, 248, 91)
    intercalatedLeader(153, 243, 153, 222)
    label("intercalated_story_label_basolateral", 272, 248, 122)
    intercalatedLeader(225, 243, 212, 225)
    label("intercalated_story_label_blood", 94, 321, 143)
    intercalatedLeader(94, 308, 96, 296)
    line(24, 330, 336, 330, 0xB8CBC1, 1)
    intercalatedProton(34, 344)
    label("intercalated_story_label_h", 53, 349, 30)
    intercalatedBicarbonate(104, 344)
    label("intercalated_story_label_hco3", 136, 349, 54)
    intercalatedBufferGlyph(185, 344, phosphate: false, bound: true)
    label("intercalated_story_label_nh4", 215, 349, 48)
    intercalatedBufferGlyph(265, 344, phosphate: true, bound: true)
    label("intercalated_story_label_h2po4", 303, 349, 59)
  }
  func intercalatedLeader(_ fromX: Double, _ fromY: Double, _ x: Double, _ y: Double) {
    line(fromX, fromY, x, y, 0x52686B, 1)
    disc(x, y, 1.65, Self.cream, border: 0x52686B)
  }
}
