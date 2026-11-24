import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func sinusArea(_ path: Path, _ fill: UInt32, _ border: UInt32) {
    self.fill(path, fill); stroke(path, border, 1.2)
  }
  func sinusShaded(_ path: Path, _ top: Double, _ bottom: Double, _ from: UInt32, _ to: UInt32, border: UInt32 = 0x886762) {
    gradient(path, top, bottom, from, to); stroke(path, border, 1.45)
  }
  func sinusEmphasis(_ path: Path, _ fill: UInt32, _ border: UInt32, _ emphasis: Double) {
    self.fill(path, fill); stroke(path, border, 1.25 + emphasis * 2.5)
  }
  func sinusFilm(_ track: GalaxySSIHealthAtlasSinusRoutes.Track, _ from: Double, _ to: Double, _ color: UInt32, _ width: Double) {
    let start = max(0, from)
    guard to > start else { return }
    stroke(track.path.trimmedPath(from: start, to: to), color, width)
  }
}
