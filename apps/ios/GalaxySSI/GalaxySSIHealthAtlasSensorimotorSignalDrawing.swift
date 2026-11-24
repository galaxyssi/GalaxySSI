import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func sensorimotorInput(_ x: Double, _ y: Double, _ progress: Double) {
    sensorimotorSignal(GalaxySSIHealthAtlasSensorimotorRoutes.position(x, y), progress, 0x5A688E)
    sensorimotorCue(x, y, 0x5A688E)
  }
  func sensorimotorCue(_ x: Double, _ y: Double, _ color: UInt32) {
    let ring = Path(ellipseIn: CGRect(x: x - 5, y: y - 5, width: 10, height: 10))
    stroke(ring, Self.cream, 2.9)
    stroke(ring, color, 1.3)
  }
  func sensorimotorSignal(_ track: GalaxySSIHealthAtlasSensorimotorRoutes.Track, _ progress: Double, _ color: UInt32) {
    // These dashed tracks indicate information flow, not individual nerve anatomy.
    context.stroke(track.path, with: .color(Self.color(color)),
      style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round, dash: [3.5, 3.5], dashPhase: 0))
    if let length = track.length, length > 0 {
      at(track.route, max(0, 1 - 7 / length)) { x, y in
        at(track.route, 1) { endX, endY in arrow(x, y, endX, endY, color) }
      }
    }
    sensorimotorPulse(track, progress, color)
  }
  func sensorimotorPulse(_ track: GalaxySSIHealthAtlasSensorimotorRoutes.Track, _ progress: Double, _ color: UInt32) {
    guard progress.isFinite, progress > 0, progress < 1 else { return }
    let radius = 4.6 * min(1, min(progress * 9, (1 - progress) * 9))
    if radius >= 0.6 {
      at(track.route, progress) { x, y in disc(x, y, radius, color, border: Self.cream) }
    }
  }
}
