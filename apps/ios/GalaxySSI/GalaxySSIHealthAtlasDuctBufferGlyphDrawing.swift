import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func ductBufferTube(_ path: Path, _ outer: Double, _ inner: Double) {
    stroke(path, 0x547C7B, outer); stroke(path, 0xD8EEE8, inner)
  }
  func ductBufferBowel(_ path: Path, _ width: Double) {
    stroke(path, 0x975E64, width); stroke(path, 0xD49B95, width - 3)
    stroke(path, 0xEFBEB0, width - 10); stroke(path, 0xF9E5CB, width - 22)
  }
  func ductBufferFilled(_ path: Path, _ color: UInt32, _ edge: UInt32) {
    fill(path, color); stroke(path, edge, 1.2)
  }
  func ductBufferAcidMark(_ x: Double, _ y: Double, _ s: Double, muted: Bool = false) {
    let fill: UInt32 = muted ? 0xDDC59D : 0xE9B976, edge: UInt32 = muted ? 0xB08F67 : 0xA66539
    oval(x - 12 * s, y - 5 * s, x + 12 * s, y + 5 * s, fill: fill, border: edge)
    line(x - 4 * s, y, x + 3 * s, y + s, edge, 1)
  }
  func ductBufferFluidMark(_ x: Double, _ y: Double, scale s: Double = 1) {
    line(x - 5 * s, y + s, x + 2 * s, y - s, 0x236E71, 1.8)
    line(x, y + 3 * s, x + 5 * s, y + 1.5 * s, 0x236E71, 1.45)
  }
  func ductBufferCell(_ x: Double, _ y: Double, _ w: Double, _ h: Double, active: Bool) {
    rounded(x, y, x + w, y + h, 5, 0x85A39A)
    rounded(x + 1, y + 1, x + w - 1, y + h - 1, 4, active ? 0xB5D8C8 : 0xE4EBDC)
    let mid = x + w / 2
    oval(mid - 6, y + h * 0.36, mid + 6, y + h * 0.67, fill: 0xA5B8A9, border: 0x547C7B)
  }
}
