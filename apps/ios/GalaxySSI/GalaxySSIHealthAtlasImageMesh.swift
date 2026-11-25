import Foundation
import CoreGraphics

enum GalaxySSIHealthAtlasImageMesh {
  static func indices(columns: Int, rows: Int) -> [UInt16] {
    guard (1...64).contains(columns), (1...64).contains(rows) else { return [] }
    return (0..<rows).flatMap { row in
      (0..<columns).flatMap { column -> [UInt16] in
        let i = UInt16(row * (columns + 1) + column), step = UInt16(columns + 1)
        // Match AOSP drawBitmapMesh's lower-left then upper-right triangles.
        return [i, i + step, i + step + 1, i, i + step + 1, i + 1]
      }
    }
  }
  static func sourcePoints(columns: Int, rows: Int, size: CGSize) -> [CGPoint] {
    guard (1...64).contains(columns), (1...64).contains(rows), size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return [] }
    return (0...rows).flatMap { row in
      (0...columns).map { column in CGPoint(x: Double(column) * size.width / Double(columns), y: Double(row) * size.height / Double(rows)) }
    }
  }
  static func transform(source: [CGPoint], destination: [CGPoint]) -> CGAffineTransform? {
    guard source.count == 3, destination.count == 3,
      (source + destination).allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
    let s0 = source[0], s1 = source[1], s2 = source[2], d0 = destination[0], d1 = destination[1], d2 = destination[2]
    let sx1 = s1.x - s0.x, sy1 = s1.y - s0.y, sx2 = s2.x - s0.x, sy2 = s2.y - s0.y
    let dx1 = d1.x - d0.x, dy1 = d1.y - d0.y, dx2 = d2.x - d0.x, dy2 = d2.y - d0.y
    let determinant = sx1 * sy2 - sx2 * sy1
    guard abs(determinant) > 0.000001 else { return nil }
    let a = (dx1 * sy2 - dx2 * sy1) / determinant, c = (dx2 * sx1 - dx1 * sx2) / determinant
    let b = (dy1 * sy2 - dy2 * sy1) / determinant, d = (dy2 * sx1 - dy1 * sx2) / determinant
    return CGAffineTransform(a: a, b: b, c: c, d: d, tx: d0.x - a * s0.x - c * s0.y, ty: d0.y - b * s0.x - d * s0.y)
  }
}
