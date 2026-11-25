import Foundation

struct GalaxySSIHealthAtlasPlacentalAmounts: Equatable, Sendable {
  let maternal: Double
  let fetal: Double
  init?(total: Double, finalTransfer: Double, phase: Double) {
    guard total.isFinite, (40...120).contains(total), finalTransfer.isFinite,
      (0...total / 2).contains(finalTransfer), phase.isFinite, (0...1).contains(phase) else { return nil }
    let moved = finalTransfer * phase
    maternal = total - moved; fetal = moved
  }
}

struct GalaxySSIHealthAtlasTubuleRetentionAmounts: Equatable, Sendable {
  let starting = 100.0
  let afterA: Double
  let remaining: Double
  var reclaimedInA: Double { starting - afterA }
  var reclaimedInB: Double { afterA - remaining }
  var totalReclaimed: Double { starting - remaining }
  init?(segmentA: Double, segmentB: Double) {
    guard segmentA.isFinite, segmentB.isFinite, (0...80).contains(segmentA), (0...80).contains(segmentB) else { return nil }
    afterA = 100 * (1 - segmentA / 100)
    remaining = afterA * (1 - segmentB / 100)
  }
}
