import Foundation
import CoreGraphics

enum GalaxySSIHealthAtlasBeatStage: Int, CaseIterable {
  case filling, atrialSqueeze, pressureRise, ejection, relaxation
  var fillsVentricles: Bool { self == .filling || self == .atrialSqueeze }
  var ejects: Bool { self == .ejection }
  func valveOpenness(_ valve: GalaxySSIHealthAtlasHeartSection.Valve, fraction: Double) -> Double {
    let f = GalaxySSIHealthAtlasFunctionCatalogue.Story.safePhase(fraction)
    if valve.openAt(0) == true, fillsVentricles { return Self.ease(self == .filling ? f / 0.14 : (1 - f) / 0.14) }
    if valve.openAt(2) == true, ejects { return Self.ease(f / 0.14) * Self.ease((1 - f) / 0.14) }
    return 0
  }
  func ventricularNarrowing(_ fraction: Double) -> Double {
    let f = GalaxySSIHealthAtlasFunctionCatalogue.Story.safePhase(fraction)
    switch self {
    case .filling: return 1 - 0.84 * Self.ease(f)
    case .atrialSqueeze: return 0.16 * (1 - Self.ease(f))
    case .pressureRise: return 0
    case .ejection: return Self.ease(f)
    case .relaxation: return 1
    }
  }
  private static func ease(_ value: Double) -> Double {
    let f = min(1, max(0, value)); return f * f * (3 - 2 * f)
  }
}

struct GalaxySSIHealthAtlasBeatMotion: Equatable {
  let stage: GalaxySSIHealthAtlasBeatStage
  let fraction: Double
  static let artSize: Double = 1254
  static let divisions = 24
  var contraction: Double { stage.ventricularNarrowing(fraction) }
  var atrialSqueeze: Double { stage == .atrialSqueeze ? sin(fraction * .pi) : 0 }
  init(chapter: Int, fraction: Double) {
    stage = GalaxySSIHealthAtlasBeatStage(rawValue: chapter) ?? .filling
    self.fraction = GalaxySSIHealthAtlasFunctionCatalogue.Story.safePhase(fraction)
  }
  func weight(_ y: Double) -> Double { min(1, max(0, (y - 662) / 390)) }
  func warpedX(_ x: Double, y: Double) -> Double { x + (720 - x) * weight(y) * contraction * 0.19 }
  func warpedY(_ y: Double) -> Double { y - weight(y) * contraction * 64 }
  func meshPoint(x: Double, y: Double) -> CGPoint {
    let atrialMask = min(1, max(0, 1 - abs(y - 527) / 132))
    let chamberMask = max(0, max(1 - abs(x - 426) / 135, 1 - abs(x - 850) / 135))
    return CGPoint(x: warpedX(x, y: y),
      y: warpedY(y) + (527 - y) * atrialMask * chamberMask * atrialSqueeze * 0.55)
  }
  var mesh: [CGPoint] {
    (0...Self.divisions).flatMap { row in
      (0...Self.divisions).map { column in
        meshPoint(x: Double(column) * Self.artSize / Double(Self.divisions), y: Double(row) * Self.artSize / Double(Self.divisions))
      }
    }
  }
  func emphasis(_ valve: GalaxySSIHealthAtlasHeartSection.Valve) -> Double {
    (stage == .pressureRise && valve.openAt(0) == true || stage == .relaxation && valve.openAt(2) == true) ? (1 - fraction) * 21 : 0
  }
  static func streamPositions(_ time: Double) -> [Double] {
    guard time.isFinite else { return [] }
    let progress = min(1, max(0, (time - 0.11) / 0.78))
    return (0...4).map { progress * 1.56 - Double($0) * 0.137 }.filter { $0 > 0 && $0 < 1 }
  }
}
