import Foundation

enum GalaxySSIHealthAtlasMarrowMotion {
  typealias Point = GalaxySSIHealthAtlasSectionLesson.Point
  static func progress(_ t: Double, start: Double, end: Double) -> Double {
    let f = t.isFinite ? min(1,max(0,(t - start) / (end - start))) : 0
    return f * f * (3 - 2 * f)
  }
  static func vesselY(_ x: Double) -> Double { 231 + 11 * sin(((x - 20) / 320 + 0.13) * 2 * .pi) }
  static let lumenPoints: [Point] = {
    var points = [Point(x: 18,y: vesselY(18) - 26)]
    for x in stride(from: 22, through: 342, by: 4) { points.append(.init(x: Double(x),y: vesselY(Double(x)) - 26)) }
    for x in stride(from: 342, through: 18, by: -4) { points.append(.init(x: Double(x),y: vesselY(Double(x)) + 26)) }
    return points
  }()
  struct Renewal {
    let separation: Double
    var distance: Double { 132 * separation }
    var radius: Double { 34 - 6 * separation }
    var right: Double { 108 + distance }
    var shared: Bool { distance < 2 * radius }
    var mid: Double { (108 + right) * 0.5 }
    var neck: Double { max(2,radius - distance * 0.5) }
    var bend: Double { min(radius * 0.55,distance * 0.38) }
    var arc: Double { radius * 0.55 }
  }
  static func renewal(_ t: Double) -> Renewal { .init(separation: progress(t,start: 0.14,end: 0.86)) }
  struct Maturation {
    let x: Double; let radius: Double; let nucleusX: Double; let nucleusY: Double; let nucleusRadius: Double; let extrude: Double
  }
  static func maturation(_ t: Double) -> Maturation {
    let condense = progress(t,start: 0.03,end: 0.44), extrude = progress(t,start: 0.29,end: 0.87)
    return .init(x: 176 - 3 * extrude,radius: 24 - 4 * condense,nucleusX: 176 + 29 * extrude,
      nucleusY: 169 + 13 * extrude,nucleusRadius: 12 - 5 * condense,extrude: extrude)
  }
  struct Release { let x: Double; let y: Double; let scaleX: Double; let scaleY: Double }
  static func release(_ t: Double, fromX: Double, fromY: Double, entryX: Double, endX: Double) -> Release {
    let approach = progress(t,start: 0,end: 0.25), cross = progress(t,start: 0.18,end: 0.51)
    let flow = t.isFinite ? min(1,max(0,(t - 0.44) / 0.56)) : 0
    let x = fromX + (entryX - fromX) * approach + (endX - entryX) * flow
    let y = fromY + (vesselY(x) - 4 - fromY) * cross, squeeze = 4 * cross * (1 - cross)
    return .init(x: x,y: y,scaleX: 1 - 0.28 * squeeze,scaleY: 1 + 0.16 * squeeze)
  }
  static func bloodX(flow: Double, index: Int) -> Double { 8 + 344 * (flow * 0.55 + Double(index) / 7).truncatingRemainder(dividingBy: 1) }
}
