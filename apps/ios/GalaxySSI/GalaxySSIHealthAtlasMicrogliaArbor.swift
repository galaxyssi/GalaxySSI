import Foundation

enum GalaxySSIHealthAtlasMicrogliaArbor {
  struct Branch {
    let x: Double, y: Double, cx: Double, cy: Double, endX: Double, endY: Double, base: Double, tip: Double
    init(_ x: Double, _ y: Double, _ cx: Double, _ cy: Double, _ endX: Double, _ endY: Double, _ base: Double, _ tip: Double) {
      self.x=x; self.y=y; self.cx=cx; self.cy=cy; self.endX=endX; self.endY=endY; self.base=base; self.tip=tip
    }
  }
  static func branches(_ step: Int, _ t: Double) -> [Branch] {
    let reach = step == 2 ? GalaxySSIHealthAtlasMicrogliaMotion.ease(t, 0.08, 0.88) : (step == 3 || step == 4) ? 1 : 0
    let cycle = step == 1 ? 1.55*t : t
    let motion = step == 1 ? 1.0 : (step == 2 || step == 3) ? 0.28 : 0.58
    let a = motion*sin(2 * .pi*cycle), b = motion*sin(2 * .pi*(cycle+0.31)), d = motion*sin(2 * .pi*(cycle+0.62))
    return [
      .init(135, 168, 105, 133, 101, 143, 5.5, 3),
      .init(101, 143, 78, 141, 54 + 12 * a, 159 - 7 * a, 3.1, 0.9),
      .init(77.75 + 3 * a, 146 - 1.75 * a, 67, 142, 51 + 7 * b, 129 + 5 * b, 1.8, 0.7),
      .init(101, 143, 89, 117, 102 + 5 * b, 99 - 14 * b, 3, 0.8),
      .init(95.25 + 1.25 * b, 119 - 3.5 * b, 83, 117, 80 + 4 * d, 98 - 7 * d, 1.6, 0.65),
      .init(155, 162, 148, 129, 159, 121, 5.6, 2.7),
      .init(159, 121, 151, 95, 137 + 4 * d, 78 + 10 * d, 2.8, 0.85),
      .init(149.5 + d, 97.25 + 2.5 * d, 149, 84, 159 - 6 * a, 67 - 8 * a, 1.8, 0.65),
      .init(159, 121, 170, 119, 183, 116, 2.7, 2),
      .init(183, 116, 197, 108, 201 + 9 * a, 89 - 10 * a, 2, 0.75),
      .init(183, 116, 206, 115, 220 + 10 * b, 100 + 8 * b, 2.1, 0.75),
      .init(171, 169, 200, 155, 212, 159, 5.8, 3.3),
      .init(212, 159, 225, 150, 228 + 25 * reach + 5 * b * (1 - reach), 133 + 17 * reach - 10 * a * (1 - reach), 3.3, 1.45),
      .init(212, 159, 226, 167, 243 + 8 * a, 176 + 8 * a, 2.7, 0.8),
      .init(226.75 + 2 * a, 167.25 + 2 * a, 239, 163, 247 + 6 * d, 169 + 6 * d, 1.45, 0.6),
      .init(153, 184, 164, 208, 158, 225, 5.7, 2.65),
      .init(158, 225, 161, 248, 177 + 7 * b, 267 + 8 * b, 2.7, 0.8),
      .init(158, 225, 141, 238, 142 - 9 * d, 258 + 7 * d, 2.4, 0.7),
      .init(168.1 + 3.24 * b, 254.4 + 3.7 * b, 185, 250, 199 + 10 * b, 261 + 7 * b, 1.5, 0.6),
      .init(135, 181, 114, 206, 95, 209, 4.5, 2.55),
      .init(95, 209, 73, 202, 54 - 9 * b, 212 + 8 * b, 2.55, 0.8),
      .init(95, 209, 89, 221, 79 + 7 * a, 241 + 8 * a, 2.4, 0.75),
      .init(87.2 + 2.1 * a, 224.6 + 2.42 * a, 104, 231, 103 + 5 * d, 249 + 6 * d, 1.55, 0.6),
    ]
  }
}
