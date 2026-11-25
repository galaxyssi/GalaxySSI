import Foundation

enum GalaxySSIHealthAtlasAstrocyteMotion {
  typealias Route = GalaxySSIHealthAtlasSectionLesson.Route
  typealias Command = GalaxySSIHealthAtlasSectionLesson.Command
  static func travel(_ t: Double, start: Double, duration: Double) -> Double {
    let f = t.isFinite ? min(1, max(0, (t - start) / duration)) : 0
    return f * f * (3 - 2 * f)
  }
  static func signal(_ t: Double, index: Int) -> Double { travel(t, start: 0.22 + 0.09 * Double(index), duration: 0.38) }
  static func uptake(_ t: Double, index: Int) -> Double { travel(t, start: 0.05 + 0.09 * Double(index), duration: 0.62) }
  static func conversion(_ t: Double, index: Int) -> Double { travel(t, start: 0.10 + 0.10 * Double(index), duration: 0.51) }
  static func recycle(_ t: Double, index: Int) -> Double { travel(t, start: 0.02 + 0.10 * Double(index), duration: 0.54) }
  static func buffer(_ t: Double, index: Int) -> Double { travel(t, start: 0.09 + 0.16 * Double(index), duration: 0.54) }
  static func command(_ kind: Command.Kind, _ coordinates: [Double]) -> Command {
    .init(kind: kind, points: stride(from: 0, to: coordinates.count, by: 2).map { .init(x: coordinates[$0], y: coordinates[$0 + 1]) })
  }
  static let signalRoutes: [Route] = (0...2).map { i in
    let x = 129 + 6 * Double(i), y = 149 + 3 * Double(i)
    return .init(start: .init(x: 134, y: 113), commands: [command(.quad, [x,133,x,y])])
  }
  static let uptakeRoutes: [Route] = (0...2).map { i in
    let offset = Double(i) * 3
    return .init(start: .init(x: 129 + 6 * Double(i), y: 149 + offset), commands: [
      command(.cubic, [152,144 + offset,163,147 + offset,175,151 + offset]),
      command(.cubic, [185,163 + offset,205,159 + offset,218,168 + offset])
    ])
  }
  static let conversionRoutes: [Route] = (0...2).map { i in
    let offset = Double(i) * 3
    return .init(start: .init(x: 218, y: 168 + offset), commands: [command(.quad, [229,164 + offset,238 + offset,170 + offset])])
  }
  static let returnRoutes: [Route] = (0...2).map { i in
    let offset = Double(i) * 3
    return .init(start: .init(x: 238 + offset, y: 170 + offset), commands: [
      command(.cubic, [220,148 + offset,216,117 + offset,183,100 + offset]),
      command(.quad, [159,88 + offset,125,91])
    ])
  }
  static let bufferRoutes: [Route] = [
    .init(start: .init(x: 308, y: 212), commands: [command(.quad, [284,206,266,189])]),
    .init(start: .init(x: 290, y: 251), commands: [command(.quad, [268,248,253,220])]),
    .init(start: .init(x: 159, y: 206), commands: [command(.quad, [174,185,191,172])])
  ]
}
