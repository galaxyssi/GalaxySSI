import SwiftUI

private typealias CalciumFlowMotion = GalaxySSIHealthAtlasCalciumMotion
private typealias CalciumFlowInk = GalaxySSIHealthAtlasCalciumShapes

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func calciumOpacity(_ alpha: Int) -> Self {
    var local = context; local.opacity *= Double(min(255, max(0, alpha))) / 255; return copy(local)
  }
  func calciumVessel(_ route: GalaxySSIHealthAtlasSectionLesson.Route, width: Double) {
    let path = GalaxySSIHealthAtlasSectionLessonView.path(route, width: 360, height: 360)
    stroke(path, CalciumFlowInk.clay, width); stroke(path, CalciumFlowInk.blood, width - 2.8)
  }
  func calciumFlow(_ route: GalaxySSIHealthAtlasSectionLesson.Route, _ t: Double, cargo: GalaxySSIHealthAtlasCalciumMotion.Cargo, count: Int, strength: Double = 1) {
    for i in 0..<count {
      let alpha = CalciumFlowMotion.flowAlpha(t, index: i, count: count, strength: strength)
      guard alpha > 0 else { continue }
      let f = CalciumFlowMotion.fraction(t, index: i, count: count), art = calciumOpacity(alpha)
      at(route, f) { x, y in
        switch cargo {
        case .pth:
          var local = art.context; local.translateBy(x: x, y: y); local.rotate(by: .degrees(45))
          copy(local).fill(Path(CGRect(x: -4, y: -4, width: 8, height: 8)), Self.violet)
        case .vitaminD:
          art.disc(x - 2.4, y + 1.4, 3.5, CalciumFlowInk.gold); art.disc(x + 2.8, y - 1.5, 2.8, CalciumFlowInk.gold)
        case .calcium: art.disc(x, y, 4, Self.teal)
        }
      }
    }
  }
}
