import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func glucoseTransport(_ t: Double) {
    typealias Motion = GalaxySSIHealthAtlasAbsorptionMotion
    let leader: UInt32 = 0x637E81, sodium: UInt32 = 0x97602C
    oval(162, 114, 179, 132, fill: 0x22FFF8EB, border: leader); line(180, 122, 206, 117, leader, 1)
    rounded(204, 73, 348, 270, 8, 0xDCEEED); rounded(204, 118, 348, 230, 5, 0xF4D0B8)
    line(205, 230, 347, 230, Self.coral, 3)
    for x in stride(from: 209, through: 345, by: 5) { line(Double(x), 117, Double(x), 111, 0x8A6052, 1.5) }
    oval(291, 147, 326, 165, fill: 0xE0B5BD, border: Self.coral)
    rounded(240, 109, 272, 129, 6, Self.teal); rounded(239, 224, 263, 236, 4, Self.teal)
    rounded(299, 222, 330, 238, 5, Self.teal)
    stroke(GalaxySSIHealthAtlasSectionLessonView.path(Motion.glucoseTrack, width: 360, height: 360), Self.blue, 1.8)
    stroke(GalaxySSIHealthAtlasSectionLessonView.path(Motion.sodiumTrack, width: 360, height: 360), sodium, 1.8)
    arrow(251, 245, 251, 260, Self.blue); arrow(307, 241, 307, 252, sodium); arrow(323, 251, 323, 206, Self.violet)
    for index in 0...1 {
      let fraction = GalaxySSIHealthAtlasSignalMotion.loop(t + Double(index) * 0.5)
      at(Motion.glucoseTrack, fraction) { x, y in disc(x, y, 3.8, Self.blue, border: Self.cream) }
      at(Motion.sodiumTrack, fraction) { x, y in rounded(x - 3.3, y - 3.3, x + 3.3, y + 3.3, 0.7, sodium) }
      disc(323, 250 - 40 * fraction, 2.6, Self.violet, border: Self.cream)
    }
    label("absorption_story_label_lumen", 275, 62, 132)
    label("absorption_story_sglt1", 309, 121, 62); label("absorption_story_glut2", 226, 221, 41)
    label("absorption_story_pump", 314, 196, 65); label("absorption_story_tissue_side", 276, 288, 143)
    disc(212, 312, 3.8, Self.blue, border: Self.cream); label("absorption_story_glucose", 247, 316, 60)
    rounded(280, 309, 286, 315, 0.7, sodium); label("absorption_story_sodium", 300, 316, 24)
    disc(321, 312, 3, Self.violet, border: Self.cream); label("absorption_story_potassium", 336, 316, 19)
  }
}
