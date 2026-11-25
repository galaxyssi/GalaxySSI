import Foundation

enum GalaxySSIHealthAtlasMelaninMotion {
  typealias Point = GalaxySSIHealthAtlasSectionLesson.Point
  typealias Route = GalaxySSIHealthAtlasSectionLesson.Route
  struct Cell { let x: Double; let y: Double; let rx: Double; let ry: Double }
  enum Transfer { case envelope(Double), core(Double) }
  struct UV { let x: Double; let backgroundEnd: Double; let endX: Double; let endY: Double; let alpha: Int }
  static func safe(_ t: Double) -> Double { t.isFinite ? min(1, max(0, t)) : 0 }
  static func progress(_ t: Double, start: Double, end: Double) -> Double {
    guard t.isFinite, start.isFinite, end.isFinite, end > start else { return 0 }
    let f = min(1, max(0, (t - start) / (end - start)))
    return f * f * (3 - 2 * f)
  }
  static func storageAmount(_ t: Double, index: Int) -> Double { 0.22 + 0.78 * progress(t, start: Double(index) * 0.07, end: 0.52 + Double(index) * 0.07) }
  static func mainFraction(_ t: Double, index: Int) -> Double { progress(t, start: 0.11 * Double(index), end: 0.69 + 0.13 * Double(index)) * (0.99 - 0.15 * Double(index)) }
  static func sideFraction(_ t: Double, branch: Int) -> Double { 0.84 * progress(t, start: 0.11 * Double(branch), end: 0.95) }
  static func transfer(_ time: Double, index: Int) -> Transfer {
    let event = (safe(time) - Double(index) * 0.21) / 0.52
    if event < 0.24 {
      let advance = progress(event, start: 0, end: 0.24), parked = 0.99 - 0.15 * Double(index)
      return .envelope(parked + (1 - parked) * advance)
    }
    return .core(progress(event, start: 0.24, end: 1))
  }
  static func capFraction(_ t: Double, index: Int) -> Double { progress(t, start: 0.04 * Double(index), end: 0.58 + 0.04 * Double(index)) }
  static func uv(_ time: Double, index: Int) -> UV {
    let x = 223 + 17 * Double(index), y = index == 1 ? 161.0 : 166
    let f = progress(safe(time), start: 0.27 + 0.07 * Double(index), end: 0.83 + 0.07 * Double(index))
    let end = 83 + (index == 2 ? 122 : y - 70) * f
    return UV(x: x, backgroundEnd: index == 2 ? 209 : y + 16, endX: x + 5 * f, endY: end,
      alpha: index == 2 ? 170 : Int(195 - 155 * progress(end, start: y - 5, end: y + 9)))
  }
  private static func route(_ x: Double, _ y: Double, _ c: [Double]) -> Route {
    .init(start: .init(x: x, y: y), commands: [.init(kind: .cubic,
      points: stride(from: 0, to: c.count, by: 2).map { .init(x: c[$0], y: c[$0 + 1]) })])
  }
  static let cells: [Cell] = [
    .init(x: 56, y: 137, rx: 29, ry: 13), .init(x: 115, y: 135, rx: 28, ry: 12), .init(x: 177, y: 134, rx: 31, ry: 12),
    .init(x: 246, y: 133, rx: 33, ry: 11), .init(x: 307, y: 137, rx: 25, ry: 13), .init(x: 53, y: 173, rx: 27, ry: 22),
    .init(x: 109, y: 169, rx: 25, ry: 21), .init(x: 172, y: 169, rx: 29, ry: 24), .init(x: 308, y: 176, rx: 25, ry: 24),
    .init(x: 49, y: 220, rx: 23, ry: 22), .init(x: 111, y: 207, rx: 24, ry: 18), .init(x: 312, y: 224, rx: 21, ry: 22),
    .init(x: 52, y: 263, rx: 27, ry: 19), .init(x: 205, y: 258, rx: 28, ry: 24), .init(x: 260, y: 253, rx: 26, ry: 29), .init(x: 309, y: 265, rx: 24, ry: 17)
  ]
  static let storage: [Point] = [.init(x: 106, y: 256), .init(x: 111, y: 266), .init(x: 143, y: 270), .init(x: 114, y: 244), .init(x: 126, y: 235), .init(x: 139, y: 237), .init(x: 155, y: 248)]
  static let arrivals: [Point] = [.init(x: 219, y: 198), .init(x: 218, y: 187), .init(x: 222, y: 177)]
  static let residentPigment: [Point] = [.init(x: 247, y: 153), .init(x: 267, y: 171), .init(x: 268, y: 193)]
  static let branches = [route(145, 242, [169,239,172,208,197,200]), route(111, 250, [87,244,83,217,79,192]), route(132, 238, [145,227,135,211,144,190])]
  static let transferTracks = arrivals.map { target in
    GalaxySSIHealthAtlasMelaninMotion.route(197, 200, [206,197,213,target.y + 3,target.x,target.y])
  }
  static let capTracks = (arrivals + Array(residentPigment.prefix(2))).enumerated().map { item in
    let (index, start) = item, endX = [228.0, 236, 243, 251, 259][index], endY = [168.0, 163, 162, 163, 168][index]
    let guideX = index < 3 ? 216 + 3 * Double(index) : start.x
    return GalaxySSIHealthAtlasMelaninMotion.route(start.x, start.y, [guideX,endY + 4,guideX,endY - 3,endX,endY])
  }
}
