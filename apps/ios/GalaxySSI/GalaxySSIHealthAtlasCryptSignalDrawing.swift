import SwiftUI

extension GalaxySSIHealthAtlasCryptWallDrawing {
  // Shift local x by 100 for the existing bounded route sampler; undo at draw time.
  private static let capillary = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 23, y: 73), commands: [
    .init(kind: .cubic, points: [.init(x: 48, y: 64), .init(x: 75, y: 56), .init(x: 100, y: 58)]),
    .init(kind: .cubic, points: [.init(x: 127, y: 60), .init(x: 154, y: 80), .init(x: 182, y: 83)])])
  private static let delivery = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 100, y: 19.5), commands: [
    .init(kind: .cubic, points: [.init(x: 94.5, y: 28), .init(x: 106, y: 42), .init(x: 100, y: 58)])])
  private func localAt(_ route: GalaxySSIHealthAtlasSectionLesson.Route, _ p: Double, draw: (Double, Double) -> Void) {
    art.at(route, p) { draw($0 - 100, $1) }
  }
  func endocrineSignal(_ step: Int, _ t: Double) {
    let pose = Self.centers[21], cell = atPose(pose), hormone: UInt32 = 0x694776
    cell.endocrineVessel(step, t)
    var body = Path(); body.move(to: CGPoint(x: -2.2, y: 0.3))
    for (cx, cy, x, y) in [(-2.4, 5.0, -5.4, 9.6), (-9.5, 15.5, -8.8, 19.2),
      (0.0, 20.0, 8.8, 19.2), (9.1, 14.0, 5.2, 9.4), (2.4, 5.0, 2.2, 0.3)] {
      body.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: cx, y: cy))
    }
    body.closeSubpath(); cell.art.fill(body, 0xCEA8D2); cell.art.stroke(body, hormone, 1.2)
    cell.flatOval(-2.65, 6, 2.65, 12.5, 0x805675); cell.art.line(-2.3, -0.5, 2.3, -0.5, 0x267A7B, 1.8)
    switch step {
    case 0: cell.endocrineVesicles(0); cell.endocrineSense(t)
    case 1: cell.endocrineVesicles(Self.ease(t, 0.07, 0.97))
    case 2:
      cell.art.disc(-4.6, 15.6, 1.4, hormone)
      for i in 0...2 {
        let p = Self.ease(t, 0.14 * Double(i), 0.66 + 0.16 * Double(i))
        if p == 0 { cell.art.disc(Double(i - 1) * 4, 17, 1.55, hormone) }
        else { cell.localAt(Self.delivery, p) { cell.art.disc($0 + Double(i - 1) * 3.1 * (1 - p), $1, 2, hormone) } }
      }
    default: cell.art.disc(-4.6, 15.6, 1.4, hormone)
    }
    art.label("crypt_lumen", 166, 97, 122)
    leader("enteroendocrine_signal_cell", pose.at(-5, 5), 201, 207, 153, 94, hormone)
    art.label("enteroendocrine_signal_capillary", 298, 266, 74)
    if step == 0 { art.label("enteroendocrine_signal_cue", 167, 130, 122) }
    else if step == 1 { leader("enteroendocrine_signal_basal", pose.at(4, 18), 216, 133, 180, 105, hormone) }
    else { art.disc(263, 288, 2.9, hormone); art.label("enteroendocrine_signal_hormone", 297, 292, 59) }
  }
  private func endocrineVessel(_ step: Int, _ t: Double) {
    var local = context; local.translateBy(x: -100, y: 0)
    let shifted = GalaxySSIHealthAtlasIllustratedDrawing(context: local, language: language)
    let path = GalaxySSIHealthAtlasSectionLessonView.path(Self.capillary, width: 360, height: 360)
    shifted.stroke(path, 0xB16E78, 17); shifted.stroke(path, 0xF4BDBA, 13.5)
    for i in 0...4 {
      let p = step == 3 ? (Double(i) * 0.19 + 0.43 * t).truncatingRemainder(dividingBy: 1) : 0.08 + Double(i) * 0.2
      localAt(Self.capillary, p) { flatOval($0 - 4.4, $1 - 2.3, $0 + 4.4, $1 + 2.3, 0xCE777E) }
    }
    if step == 3 {
      for i in 0...2 {
        let p = Self.ease(t, Double(i) * 0.12, 0.76 + 0.12 * Double(i))
        localAt(Self.capillary, 0.49 + 0.48 * p) { art.disc($0, $1 + Double(i - 1) * 2.2, 2.25, 0x694776) }
      }
    }
  }
  private func endocrineVesicles(_ p: Double) {
    for i in 0...3 {
      let x = (Double(i) - 1.5) * 3.9, start = 12.5 + Double(i % 2) * 2
      art.disc(x, start + (17.2 - Double(i) * 0.35 - start) * p, 1.55, 0x694776)
    }
  }
  private func endocrineSense(_ t: Double) {
    for i in 0...2 {
      let p = Self.ease(t, 0.12 * Double(i), 0.76 + 0.11 * Double(i))
      let x = Double(i - 1) * (25 - 19 * p), start = -72 - 5 * Double(i), y = start + (-5 - start) * p
      for side in [-1.0, 1.0] {
        art.line(x - 3.2, y, x, y + 3.2 * side, 0x267A7B, 1.5)
        art.line(x, y + 3.2 * side, x + 3.2, y, 0x267A7B, 1.5)
      }
    }
    let arrived = Self.ease(t, 0.64, 1)
    ring(0, 0, 3 + 5 * arrived, opacity: arrived * 0.85, width: 1.65, tint: 0x267A7B)
  }
}
