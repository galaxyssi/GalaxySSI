import Foundation
import CoreGraphics

enum GalaxySSIHealthAtlasCurveLength {
  typealias Route = GalaxySSIHealthAtlasSectionLesson.Route
  static func route(_ route: Route, width: Double, height: Double, accuracy: Double = 0.0001) -> Double? {
    guard route.start.fits(width: width, height: height), (1...16).contains(route.commands.count),
      route.commands.allSatisfy({ $0.fits(width: width, height: height) }),
      accuracy.isFinite, accuracy >= 0.0000001, accuracy <= 1 else { return nil }
    var start = CGPoint(x: route.start.x, y: route.start.y), total = 0.0
    for command in route.commands {
      let points = [start] + command.points.map { CGPoint(x: $0.x, y: $0.y) }
      guard let length = bezier(points, accuracy: accuracy / Double(route.commands.count)) else { return nil }
      total += length; start = points[points.count - 1]
    }
    return total
  }
  static func bezier(_ points: [CGPoint], accuracy: Double = 0.0001) -> Double? {
    guard (2...4).contains(points.count), points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
      accuracy.isFinite, accuracy > 0 else { return nil }
    var pending = [(points: points, tolerance: accuracy, depth: 0)], total = 0.0
    while let part = pending.popLast() {
      let first = part.points[0], last = part.points[part.points.count - 1]
      let chord = hypot(last.x - first.x, last.y - first.y)
      let polygon = zip(part.points, part.points.dropFirst()).reduce(0.0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
      guard chord.isFinite, polygon.isFinite else { return nil }
      // Chord/control-polygon bounds under subdivision: Gravesen (1997), doi:10.1016/0925-7721(95)00054-2.
      if polygon - chord <= 2 * part.tolerance { total += (polygon + chord) / 2; continue }
      guard part.depth < 20 else { return nil }
      var row = part.points, left = [row[0]], right = [row[row.count - 1]]
      while row.count > 1 {
        row = zip(row, row.dropFirst()).map { CGPoint(x: ($0.0.x + $0.1.x) / 2, y: ($0.0.y + $0.1.y) / 2) }
        left.append(row[0]); right.append(row[row.count - 1])
      }
      pending.append((Array(right.reversed()), part.tolerance / 2, part.depth + 1))
      pending.append((left, part.tolerance / 2, part.depth + 1))
    }
    return total
  }
}
