import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func cranialEye(_ x: Double, direction: Double, frame: GalaxySSIHealthAtlasCranialMotion.Frame) {
    typealias Geometry = GalaxySSIHealthAtlasCranialGeometry
    var local = context
    local.translateBy(x: x, y: 0); local.scaleBy(x: direction, y: 1)
    let art = copy(local)
    art.fill(Geometry.globeSection, 0xF5E9DF); art.stroke(Geometry.globeSection, 0xC8A6A0, 1.1)
    art.stroke(Geometry.retina, 0xC48177, 3.6); art.stroke(Geometry.retina, 0xEBAD91, 1.6)
    art.gradient(Geometry.eye, 55, 96, 0xFFFBF3, 0xEDD9CF)
    art.stroke(Geometry.eye, 0x936964, 1.25)
    var clipped = local; clipped.clip(to: Geometry.eye)
    let inner = copy(clipped)
    inner.oval(-22, 52, 22, 97, top: 51, bottom: 94, from: 0xB1B99A, to: 0x688E83, border: 0x4B7169)
    var spokes = Path()
    for i in 0..<40 {
      let phase = Double(i) * 2 * .pi / 40, cosA = cos(phase), sinA = sin(phase)
      let start = frame.radius + (i % 3 == 0 ? 3.2 : 2)
      let outer = i % 2 == 0 ? 20.1 : 18.3
      spokes.move(to: CGPoint(x: cosA * start, y: 75 + sinA * start))
      spokes.addQuadCurve(to: CGPoint(x: cosA * outer, y: 75 + sinA * outer),
        control: CGPoint(x: cosA * 17 - sinA, y: 75 + sinA * 17 + cosA))
    }
    inner.stroke(spokes, 0x507B70, 0.75)
    let rim = Path(ellipseIn: CGRect(x: -frame.radius - 1.2, y: 75 - frame.radius - 1.2,
      width: 2 * (frame.radius + 1.2), height: 2 * (frame.radius + 1.2)))
    inner.stroke(rim, 0x718675, 1.6)
    if frame.narrowing > 0 {
      var tint = clipped; tint.opacity = Double(Int(235 * frame.narrowing)) / 255
      copy(tint).stroke(rim, 0xA25264, 1.6)
    }
    inner.disc(0, 75, frame.radius, 0x243B42)
    inner.disc(-3.5, 71, 1.6, 0xF4F2E6)
    art.stroke(Geometry.lid, 0x936964, 1.4)
    art.oval(37, 74, 46, 81, fill: 0xDCA7A0, border: 0xB68883)
  }
  func cranialMidbrain() {
    typealias Geometry = GalaxySSIHealthAtlasCranialGeometry
    gradient(Geometry.midbrain, 222, 313, 0xF3D9DF, 0xE3BCC9)
    stroke(Geometry.midbrain, 0xAC7D8B, 1.4)
    stroke(Geometry.midbrainFolds, 0xC595A7, 1.3)
    oval(137, 283, 170, 308, fill: 0xE6B4C4, border: 0xCB9AAA)
    oval(190, 283, 223, 308, fill: 0xE6B4C4, border: 0xCB9AAA)
    disc(180, 290, 6.4, 0xD6A5B8)
    disc(180, 290, 2.7, Self.cream, border: 0xAC7D8B)
  }
}
