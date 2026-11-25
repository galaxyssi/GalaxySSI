import SwiftUI

extension GalaxySSIHealthAtlasSignalDrawing {
  func myelinScene(_ motion: Motion) {
    switch motion.chapter {
    case 0: glialBranches(motion.fraction)
    case 1: wrapping(motion.fraction)
    case 2, 3: myelinRelay(active: motion.chapter == 3, t: motion.fraction)
    default: compare(motion.fraction)
    }
  }
  private func glialBranches(_ t: Double) {
    let x = 180.0, branches = [CGPoint(x: 89, y: 181), CGPoint(x: 241, y: 222), CGPoint(x: 147, y: 263)]
    for point in branches {
      var path = Path(); path.move(to: CGPoint(x: x, y: 110)); path.addQuadCurve(to: point, control: CGPoint(x: point.x + 10, y: 125))
      stroke(path, 0x8EBEB1, 8); stroke(path, Self.teal, 1.5)
    }
    oval(x, 91, 28, 25, 0x93C3B8); oval(x - 2, 91, 13, 12, Self.violet)
    for point in branches { line(33, point.y, 327, point.y, Self.coral, 10) }
    for point in branches {
      let width = 18 + 19 * t; sheath(point.x - width, point.y, point.x + width, 15)
      ring(point.x, point.y, 8 + 4 * sin(.pi * t), Self.cream)
    }
    leader(182, 42, 181, 78, "myelin_oligo", Self.teal); leader(271, 309, 155, 263, "myelin_cover", Self.gold)
  }
  private func wrapping(_ t: Double) {
    let x = 160.0, y = 186.0
    oval(x, y, 72, 72, 0xEFE1BC); oval(x, y, 23, 23, 0xDD9B91); ring(x, y, 23, Self.coral)
    for i in 0...3 {
      let r = Double(27 + 10 * i), turn = min(1, max(0.05, t * 1.4 - Double(i) * 0.15)) * 345
      var path = Path(); path.addArc(center: CGPoint(x: x, y: y), radius: r, startAngle: .degrees(-93), endAngle: .degrees(-93 + turn), clockwise: false)
      stroke(path, i % 2 == 0 ? 0x9A6D55 : Self.gold, 4.5)
    }
    oval(219, 145, 21, 15, 0xD4AE98); oval(221, 145, 10, 6.5, Self.violet)
    leader(255, 87, 222, 140, "myelin_schwann", Self.violet)
    leader(81, 298, 107, 209, "myelin_cover", Self.gold); leader(243, 298, 170, 192, "neuro_axon", Self.coral)
  }
  private func myelinRelay(active: Bool, t: Double) {
    axonSection(176, wrapped: true)
    if active {
      let head = 37 + 287 * t
      line(max(34, head - 38), 176, head, 176, Self.blue, 2); dot(head, 176, 4.3, Self.blue)
      for node in Motion.nodes {
        let closeness = min(1, max(0, 1 - abs(head - node) / 17))
        if closeness > 0 { ring(node, 176, 7 + 10 * closeness, Self.gold) }
      }
      leader(212, 272, 176, 177, "myelin_current", Self.blue)
    } else {
      let node = Motion.nodes[min(Motion.nodes.count - 1, Int(t * Double(Motion.nodes.count)))]
      ring(node, 176, 9 + 4 * sin(t * 15), Self.blue)
      leader(214, 96, node, 176, "myelin_node", Self.blue); leader(111, 262, 124, 186, "myelin_cover", Self.gold)
    }
  }
  private func compare(_ t: Double) {
    for myelinated in [true, false] {
      let y = myelinated ? 131.0 : 244
      axonSection(y, wrapped: myelinated)
      let x = 34 + 292 * Motion.axonTravel(t, myelinated: myelinated)
      dot(x, y, 4.8, Self.blue)
      if !myelinated || Motion.nodes.contains(where: { abs($0 - x) < 14 }) { ring(x, y, 8 + 3 * sin(t * 13), Self.gold) }
      label(180, y + 49, myelinated ? "myelin_yes" : "myelin_no")
    }
  }
  private func axonSection(_ y: Double, wrapped: Bool) {
    line(33, y, 327, y, Self.coral, 11)
    if wrapped {
      var previous = 36.0
      for node in Motion.nodes { sheath(previous, y, node - 6, 14); previous = node + 6 }
      sheath(previous, y, 326, 14)
    }
    line(34, y, 326, y, 0xEFB4A9, 2.1)
  }
  private func sheath(_ start: Double, _ y: Double, _ end: Double, _ thick: Double) {
    let path = Path(roundedRect: CGRect(x: start, y: y - thick, width: end - start, height: 2 * thick), cornerRadius: 9)
    gradient(path, 115, 220, 0xF4E4B9, 0xC89170); stroke(path, Self.gold, 1.1)
    line(start + 5, y - thick + 5, end - 5, y - thick + 5, Self.cream, 1)
  }
}
