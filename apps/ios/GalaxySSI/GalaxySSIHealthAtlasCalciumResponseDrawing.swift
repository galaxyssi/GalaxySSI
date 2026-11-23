import SwiftUI

private typealias CalciumResponseMotion = GalaxySSIHealthAtlasCalciumMotion
private typealias CalciumResponseShapes = GalaxySSIHealthAtlasCalciumShapes

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func calciumRenalResponse(_ t: Double) {
    gradient(CalciumResponseShapes.kidney, 87, 250, 0xF7C6BE, 0xD9949D); stroke(CalciumResponseShapes.kidney, CalciumResponseShapes.clay, 1.6)
    fill(CalciumResponseShapes.renalCortex, 0xE5A4A8); stroke(CalciumResponseShapes.renalCortex, 0xCA878D, 1.1)
    for i in 0...3 {
      let y = 126 + Double(i) * 27, x = i == 0 || i == 3 ? 79.0 : 59
      var local = context; local.translateBy(x: x + 27, y: y); local.rotate(by: .degrees(Double(24 - i * 16))); local.translateBy(x: -x - 27, y: -y)
      copy(local).oval(x, y - 8, x + 49, y + 8, fill: 0xC7828D, border: CalciumResponseShapes.clay)
      line(x + 33, y, 117, 170, 0xF7D6B5, 5)
    }
    line(117, 170, 139, 172, 0xF7D6B5, 7); line(151, 117, 171, 135, CalciumResponseShapes.guide, 1)
    let tubule = GalaxySSIHealthAtlasSectionLessonView.path(CalciumResponseMotion.tubule, width: 360, height: 360)
    stroke(tubule, CalciumResponseShapes.gold, 29); stroke(tubule, 0xF8DFB2, 26); stroke(tubule, 0xFFF2D4, 15)
    calciumVessel(CalciumResponseMotion.renalBlood, width: 23)
    arrow(234, 165, 234, 200, Self.teal); calciumFlow(CalciumResponseMotion.retention, t, cargo: .calcium, count: 4)
    label("calcium_feedback_story_art_kidney", 91, 68, 125); label("calcium_feedback_story_art_tubule", 250, 106, 156)
    label("calcium_feedback_story_art_calcium", 291, 183, 104); label("calcium_feedback_story_art_blood", 252, 252, 125)
    label("calcium_feedback_story_art_activation", 235, 283, 186); calciumFlow(CalciumResponseMotion.activeVitaminD, t, cargo: .vitaminD, count: 3)
  }
  func calciumIntestinalResponse(_ t: Double) {
    gradient(CalciumResponseShapes.intestinalWall, 90, 285, 0xFFEBD4, 0xEFB6AE)
    stroke(CalciumResponseShapes.villus, Self.coral, 15); stroke(CalciumResponseShapes.villus, 0xF3BCB2, 12.5)
    for p in CalciumResponseShapes.villusDots { disc(Double(p.x), Double(p.y), 2.1, 0xBA7D8F) }
    calciumVessel(CalciumResponseMotion.villusBlood, width: 16)
    line(221, 130, 263, 101, CalciumResponseShapes.guide, 1); arrow(83, 190, 125, 190, Self.teal)
    calciumFlow(CalciumResponseMotion.uptake, t, cargo: .calcium, count: 5); calciumFlow(CalciumResponseMotion.intestinalSignal, t, cargo: .vitaminD, count: 3)
    label("calcium_feedback_story_art_lumen", 76, 85, 124); label("calcium_feedback_story_art_calcium", 72, 134, 106)
    label("calcium_feedback_story_art_villus", 278, 96, 135); label("calcium_feedback_story_art_blood", 84, 320, 128); label("calcium_feedback_story_art_vitamin_d", 266, 320, 159)
  }
}
