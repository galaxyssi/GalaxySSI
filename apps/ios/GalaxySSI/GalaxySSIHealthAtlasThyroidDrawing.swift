import SwiftUI

extension GalaxySSIHealthAtlasSignalDrawing {
  func thyroidScene(_ motion: Motion) {
    switch motion.chapter {
    case 0: trh(motion.fraction)
    case 1: tsh(motion.fraction)
    case 2: secretion(motion.fraction)
    case 3: conversion(motion.fraction)
    default: feedback(motion.fraction)
    }
  }
  private func trh(_ t: Double) {
    var local = context; local.translateBy(x: 0, y: 41); let drawing = copy(local)
    drawing.plate("HealthAtlasFunctionPituitary", 0, 0, 360, 280)
    for i in 0...5 { drawing.marker(Motion.portal, Motion.loop(t * 1.14 + Double(i) / 6)) { drawing.dot($0, $1, 3.7, Self.teal) } }
    leader(247, 54, 189, 90, "thyroid_hypo", Self.teal); leader(115, 317, 132, 228, "thyroid_anterior", Self.coral)
    legend(264, 317, "TRH", Self.teal)
  }
  private func tsh(_ t: Double) {
    plate("HealthAtlasFunctionPituitary", 22, 55, 171, 171); plate("HealthAtlasFunctionThyroid", 185, 145, 338, 264)
    let path = GalaxySSIHealthAtlasSectionLessonView.path(Motion.tshRoute, width: 360, height: 360)
    stroke(path, 0xE1A3A6, 21); stroke(path, 0xF2C9C1, 12)
    for i in 0...4 {
      marker(Motion.tshRoute, Motion.loop(t * 1.25 + Double(i) / 5)) { rounded($0 - 3.5, $1 - 3.5, $0 + 3.5, $1 + 3.5, 1.5, Self.gold) }
    }
    label(99, 46, "thyroid_anterior"); label(259, 282, "thyroid_gland"); legend(165, 294, "TSH", Self.gold)
  }
  private func secretion(_ t: Double) {
    var local = context; local.translateBy(x: 0, y: 37); let drawing = copy(local)
    drawing.plate("HealthAtlasFunctionThyroid", 0, 0, 360, 280)
    for i in 0...5 {
      drawing.marker(Motion.thyroidOut, Motion.loop(t * 1.11 + Double(i) / 6)) {
        drawing.dot($0, $1, i % 5 == 0 ? 3 : 4.6, i % 5 == 0 ? Self.teal : Self.violet)
      }
    }
    leader(93, 56, 124, 107, "thyroid_follicle", Self.coral); leader(263, 313, 236, 272, "thyroid_blood", Self.coral)
    legend(105, 316, "T4", Self.violet); legend(168, 316, "T3", Self.teal)
  }
  private func conversion(_ t: Double) {
    box(30, 101, 330, 255, 24, 246, 317, 0xE0EDE6, 0xADD0C1)
    let fraction = min(1, t * 1.2), x = 113 + fraction * 133, y = 179 + 10 * sin(fraction * .pi)
    arrow(108, 215, 252, 215, Self.teal)
    for i in 0...3 {
      if i == 3 && fraction > 0.53 { dot(x + 21 * fraction, y - 17 - fraction * 18, 4, Self.violet) }
      else {
        let angle = Double(i) * 1.57
        dot(x + 10 * cos(angle), y + 10 * sin(angle), 6, fraction < 0.53 ? Self.violet : Self.teal)
      }
    }
    label(180, 65, "thyroid_tissue"); legend(109, 298, "T4", Self.violet); legend(255, 298, "T3", Self.teal)
  }
  private func feedback(_ t: Double) {
    let drive = Motion.upstreamDrive(t), positions = [74.0, 161, 250], center = 151.0
    let captions = ["thyroid_hypo", "thyroid_anterior", "thyroid_gland"], tones = [Self.teal, Self.gold, Self.violet]
    for i in positions.indices {
      let y = positions[i]
      oval(center, y, 21, 14, 0xEED7C9); dot(center, y, i == 2 ? 5 + 5 * t : 4 + 3 * drive, tones[i])
      label(66, y + 5, captions[i])
    }
    let bars = max(1, Int(4 * drive))
    for i in 0...1 {
      let start = positions[i] + 18, end = positions[i + 1] - 18
      arrow(center, start, center, end, tones[i])
      for j in 0..<bars {
        let f = Motion.loop(t * 1.5 + Double(j) / 4)
        dot(center, start + (end - start) * f, 2.7, tones[i])
      }
    }
    legend(208, 121, "TRH", Self.teal); legend(208, 209, "TSH", Self.gold)
    line(178, 250, 272, 250, Self.feedbackInk, 2.1); line(272, 250, 272, 74, Self.feedbackInk, 2.1)
    for y in positions.prefix(2) {
      line(272, y, 183, y, Self.feedbackInk, 2); line(183, y - 6, 183, y + 6, Self.feedbackInk, 2.6)
    }
    let f = Motion.loop(t * 1.3)
    dot(272, 248 - f * 172, 3.8, Self.feedbackInk); legend(245, 287, "T4 / T3", Self.violet)
    label(223, 326, "thyroid_inhibition")
  }
}
