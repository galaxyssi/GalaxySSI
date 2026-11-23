import SwiftUI

private typealias CalciumNeckMotion = GalaxySSIHealthAtlasCalciumMotion
private typealias CalciumNeckShapes = GalaxySSIHealthAtlasCalciumShapes

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func calciumParathyroids(_ state: GalaxySSIHealthAtlasCalciumMotion.State, t: Double) {
    let calcium = state.calcium, hormone = state.hormone
    rounded(77, 26, 99, 121, 7, 0xDFD7C5)
    for y in stride(from: 37, through: 113, by: 11) { line(79, Double(y), 97, Double(y), 0xBAA997, 1.3) }
    rounded(67, 72, 109, 86, 7, 0xE5A3A5)
    for side in [-1.0, 1.0] {
      var local = context; local.translateBy(x: 88, y: 0); local.scaleBy(x: -side, y: 1); local.translateBy(x: -88, y: 0)
      let art = copy(local)
      art.gradient(CalciumNeckShapes.thyroidLobe, 28, 113, 0xF7C6B9, 0xD68D96); art.stroke(CalciumNeckShapes.thyroidLobe, CalciumNeckShapes.clay, 1.3)
      art.oval(51, 44, 63, 61, fill: CalciumNeckShapes.glandGold, border: CalciumNeckShapes.gold)
      art.oval(55, 83, 67, 100, fill: CalciumNeckShapes.glandGold, border: CalciumNeckShapes.gold)
    }
    line(119, 52, 159, 52, CalciumNeckShapes.gold, 1); line(131, 82, 176, 82, CalciumNeckShapes.guide, 1)
    label("calcium_feedback_story_art_glands", 240, 57, 149); label("calcium_feedback_story_art_thyroid", 240, 87, 122)
    gradient(CalciumNeckShapes.chiefCell, 175, 258, 0xFFE7D3, 0xEAB4B3); stroke(CalciumNeckShapes.chiefCell, CalciumNeckShapes.clay, 1.8)
    oval(81, 218, 131, 244, fill: 0xCFAFCB, border: Self.violet); disc(109, 229, 4, 0xA77DA8)
    for i in 0...3 { disc(165 + Double(i) * 15, Double(234 + (i % 2) * 9), 4.5, 0xE9D4EB, border: Self.violet) }
    for x in stride(from: 108, through: 246, by: 69) {
      oval(Double(x - 6), 170, Double(x + 6), 184, fill: 0xD6E7DD, border: Self.teal)
      calciumOpacity(Int(255 * calcium)).disc(Double(x), 174, 3.3, Self.teal)
    }
    for i in 0...6 {
      let f = CalciumNeckMotion.wrap(0.62 * t + Double(i) / 7), alpha = Int(255 * CalciumNeckMotion.presence(calcium, index: i, count: 7))
      calciumOpacity(alpha).disc(43 + 272 * f, 153 + 8 * wave(f + Double(i) * 0.3), 4, Self.teal)
    }
    calciumVessel(CalciumNeckMotion.neckBlood, width: 28); calciumFlow(CalciumNeckMotion.release, t, cargo: .pth, count: 5, strength: hormone)
    label("calcium_feedback_story_art_calcium", 85, 136, 117); label("calcium_feedback_story_art_receptor", 273, 136, 118)
    line(273, 141, 249, 168, CalciumNeckShapes.guide, 1); label("calcium_feedback_story_art_chief", 104, 211, 112)
    label("calcium_feedback_story_art_blood", 87, 332, 126)
    if hormone > 0 { label("calcium_feedback_story_art_pth", 265, 332, 154) }
  }
}
