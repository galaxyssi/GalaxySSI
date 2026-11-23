import SwiftUI

extension GalaxySSIHealthAtlasMovementDrawing {
  func remodeling(chapter: Int, t: Double) {
    let depth = Motion.exposedDepth(chapter: chapter, fraction: t), original = Motion.erosionDepth(chapter: chapter, fraction: t)
    matrix(depth: original, filled: true)
    if chapter >= 3 {
      var osteoid = surface(depth)
      for x in stride(from: 318, through: 22, by: -4) { osteoid.addLine(to: CGPoint(x: Double(x), y: Motion.boneY(Double(x), depth: original))) }
      osteoid.closeSubpath()
      let ratio = chapter == 4 ? t : 0
      fill(osteoid, Motion.blend(0x8AC2B2, 0xECD5AB, fraction: ratio))
      if chapter == 4 {
        for i in 0...14 {
          let x = 111 + Double(i) * 8.5
          let y = Motion.boneY(x, depth: depth) + 4 + (Motion.boneY(x, depth: original) - Motion.boneY(x, depth: depth) - 8) * (0.15 + 0.11 * Double(i % 5))
          if t > Double(i) * 0.043 { oval(x, y, 2.1, 1.4, Self.edge) }
        }
      }
    }
    matrix(depth: depth, filled: false)
    osteocyte(76, 227, time: chapter == 0 ? t : nil); osteocyte(202, 260); osteocyte(282, 214)
    switch chapter {
    case 0:
      for i in 0..<3 {
        let dy = 24 * Motion.cycle(t * 1.35 + Double(i) * 0.23), x = Double(63 + 29 * i)
        line(x, 101 + dy, x, 127 + dy, Self.amber, 2.2)
        line(x, 127 + dy, x - 4, 121 + dy, Self.amber, 2.2); line(x, 127 + dy, x + 4, 121 + dy, Self.amber, 2.2)
      }
      label(92, 78, "bone_loading"); leader(99, 296, 76, 227, "bone_osteocyte", Self.purple)
    case 1:
      let y = Motion.boneY(170, depth: depth)
      osteoclast(depth)
      for i in 0...5 {
        let f = Motion.cycle(t * 1.8 + Double(i) / 6), x = Double(149 + i * 8)
        oval(x, Motion.boneY(x, depth: depth) - 1 - f * 5, 1.5, 1.5, Self.amber)
      }
      leader(170, 83, 170, y - 48, "bone_osteoclast", Self.scarlet)
    case 2:
      for i in 0...5 {
        let x = Double(112 + i * 19) + 5 * sin(t * 4 + Double(i))
        surfaceCell(x, Motion.boneY(x, depth: depth), 5, Self.purple)
      }
      leader(170, 100, 170, Motion.boneY(170, depth: depth) - 12, "bone_reversal_cells", Self.purple)
    case 3:
      for i in 0...6 {
        let x = 111 + Double(i) * 19.5
        surfaceCell(x, Motion.boneY(x, depth: depth), 8, Self.teal)
      }
      leader(170, 100, 170, Motion.boneY(170, depth: depth) - 16, "bone_osteoblast", Self.teal)
    case 4:
      osteocyte(166, 184 + 5 * t)
      leader(170, 100, 166, 184 + 5 * t, "bone_osteocyte", Self.purple)
    default: break
    }
    label(170, 317, chapter == 3 ? "bone_osteoid" : chapter == 4 ? "bone_new" : "bone_old")
  }
  private func surface(_ depth: Double) -> Path {
    let points = Motion.surfacePoints(depth)
    var path = Path(); path.move(to: points[0])
    for point in points.dropFirst() { path.addLine(to: point) }
    return path
  }
  private func matrix(depth: Double, filled: Bool) {
    var path = surface(depth)
    guard filled else { stroke(path, Self.edge, 1.4); return }
    path.addLine(to: CGPoint(x: 318, y: 291)); path.addLine(to: CGPoint(x: 22, y: 291)); path.closeSubpath()
    gradient(path, top: 145, bottom: 302, from: 0xF9E5C4, to: 0xD5B48E)
    var clipped = context; clipped.clip(to: path); let drawing = copy(clipped)
    for i in 0...5 {
      let y = Double(169 + i * 23)
      var lamella = Path(); lamella.move(to: CGPoint(x: 17, y: y))
      lamella.addCurve(to: CGPoint(x: 320, y: y - 1), control1: CGPoint(x: 109, y: y + 8), control2: CGPoint(x: 220, y: y + 17))
      drawing.stroke(lamella, 0xC59E77, 1.2)
    }
    for i in 0...31 {
      drawing.oval(Double(29 + i * 91 % 282), Double(155 + i * 43 % 128), 1.4, 0.9, 0xD0AB84)
    }
  }
  private func osteoclast(_ depth: Double) {
    let floor = Motion.boneY(170, depth: depth)
    func contact(_ x: Double) -> Double { Motion.boneY(x, depth: depth) - floor }
    var local = context; local.translateBy(x: 0, y: floor); let drawing = copy(local)
    var path = Path(); path.move(to: CGPoint(x: 121, y: contact(121)))
    path.addCurve(to: CGPoint(x: 155, y: -47), control1: CGPoint(x: 130, y: -41), control2: CGPoint(x: 138, y: -51))
    path.addCurve(to: CGPoint(x: 219, y: contact(219)), control1: CGPoint(x: 179, y: -55), control2: CGPoint(x: 210, y: -46))
    for i in stride(from: 8, through: 0, by: -1) {
      let x = 125 + Double(i) * 10.5
      path.addQuadCurve(to: CGPoint(x: x, y: contact(x)), control: CGPoint(x: x + 5, y: contact(x + 5) - 6))
    }
    path.closeSubpath()
    drawing.gradient(path, top: -48, bottom: 1, from: 0xF3C5CB, to: 0xBB7183); drawing.stroke(path, Self.scarlet, 1.4)
    for i in 0...3 {
      let x = Double(144 + i * 17), y = Double(-34 + i % 2 * 5)
      drawing.oval(x, y, 6.8, 4.9, 0xA791B2); drawing.oval(x + 0.7, y + 0.5, 5, 3.7, Self.purple)
      drawing.oval(x - 1.5, y - 0.6, 1.3, 1, 0xCCB1CC)
    }
  }
  private func osteocyte(_ x: Double, _ y: Double, time: Double? = nil) {
    for i in 0...6 {
      let a = Double(i) * 2 * .pi / 7
      line(x, y, x + cos(a) * 15, y + sin(a) * 11, Self.purple, 0.9)
    }
    oval(x, y, 7, 4.5, Self.purple); oval(x, y, 2.7, 2.2, Self.white)
    if let time {
      let radius = 12 + 16 * Motion.cycle(time * 1.2)
      stroke(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)), Self.amber, 1.6)
    }
  }
  private func surfaceCell(_ x: Double, _ y: Double, _ h: Double, _ value: UInt32) {
    oval(x, y - h, 8, h, value); oval(x, y - h - 0.5, 2.8, 2, Self.white)
  }
}
