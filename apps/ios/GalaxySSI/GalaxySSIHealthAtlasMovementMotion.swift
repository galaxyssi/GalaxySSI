import Foundation
import CoreGraphics

struct GalaxySSIHealthAtlasMovementMotion {
  let bone: Bool
  let chapter: Int
  let fraction: Double
  init(courseID: String, chapter: Int, fraction: Double) {
    bone = courseID == "BONE_REMODELING"
    self.chapter = min(4, max(0, chapter))
    self.fraction = fraction.isFinite ? min(1, max(0, fraction)) : 0
  }
  static let actinLength = 80.0, myosinLength = 122.0
  static func ease(_ t: Double) -> Double { t * t * (3 - 2 * t) }
  static func sarcomereHalfWidth(_ t: Double) -> Double { 111 - 33 * ease(t) }
  static func elbowAngle(extending: Bool, fraction: Double) -> Double { 96 * ease(extending ? 1 - fraction : fraction) }
  static func erosionDepth(chapter: Int, fraction: Double) -> Double {
    chapter == 0 ? 0 : chapter == 1 ? 62 * ease(fraction) : 62
  }
  static func exposedDepth(chapter: Int, fraction: Double) -> Double {
    chapter == 3 ? 62 - 48 * ease(fraction) : chapter == 4 ? 14 : erosionDepth(chapter: chapter, fraction: fraction)
  }
  static func boneY(_ x: Double, depth: Double) -> Double {
    let local = min(1, max(0, (x - 81) / 178)), cup = sin(local * .pi)
    return 151 + cup * cup * depth
  }
  static func surfacePoints(_ depth: Double) -> [CGPoint] {
    [CGPoint(x: 22, y: boneY(22, depth: depth))] +
      stride(from: 26, through: 318, by: 4).map { CGPoint(x: Double($0), y: boneY(Double($0), depth: depth)) }
  }
  static func cycle(_ t: Double) -> Double { t.isFinite ? t.truncatingRemainder(dividingBy: 1) : 0 }
  static func blend(_ from: UInt32, _ to: UInt32, fraction: Double) -> UInt32 {
    let t = fraction.isFinite ? min(1, max(0, fraction)) : 0
    func channel(_ shift: UInt32) -> UInt32 {
      UInt32(Double((from >> shift) & 255) * (1 - t) + Double((to >> shift) & 255) * t)
    }
    return 0xFF000000 | channel(16) << 16 | channel(8) << 8 | channel(0)
  }
  static let nerve = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 29, y: 112), commands: [
    .init(kind: .cubic, points: [.init(x: 91, y: 113), .init(x: 91, y: 55), .init(x: 149, y: 77)]),
    .init(kind: .cubic, points: [.init(x: 174, y: 86), .init(x: 164, y: 120), .init(x: 174, y: 131)])
  ])
  static let tubule = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 33, y: 139), commands: [
    .init(kind: .line, points: [.init(x: 151, y: 139)]),
    .init(kind: .quad, points: [.init(x: 166, y: 139), .init(x: 166, y: 158)]),
    .init(kind: .line, points: [.init(x: 166, y: 224)]),
    .init(kind: .quad, points: [.init(x: 166, y: 246), .init(x: 177, y: 246)]),
    .init(kind: .quad, points: [.init(x: 188, y: 246), .init(x: 188, y: 224)]),
    .init(kind: .line, points: [.init(x: 188, y: 159)]),
    .init(kind: .quad, points: [.init(x: 188, y: 139), .init(x: 202, y: 139)]),
    .init(kind: .line, points: [.init(x: 303, y: 139)])
  ])
}
