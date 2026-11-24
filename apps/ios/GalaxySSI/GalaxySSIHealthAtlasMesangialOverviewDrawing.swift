import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func mesangialOverview(_ f: Double?) {
    typealias Geometry = GalaxySSIHealthAtlasMesangialGeometry
    line(86, 69, 49, 151, 0xAAB7AE, 1); line(112, 69, 139, 153, 0xAAB7AE, 1)
    fill(Geometry.capsule, 0xEDF1E5); stroke(Geometry.capsule, 0x879B92, 1.5)
    stroke(Geometry.tuftBranches, 0x995E66, 8.5); stroke(Geometry.tuftBranches, 0xE1A7A8, 5.8)
    stroke(Geometry.tuft, 0x995E66, 10.5); stroke(Geometry.tuft, 0xEFB9B0, 7.5)
    if let f {
      mesangialSweep(GalaxySSIHealthAtlasMesangialRoutes.tuft, 0.72 * f, 0.17 + 0.72 * f, 0xAE5360, 3.8)
      stroke(Path(ellipseIn: CGRect(x: 86 - 3 * f, y: 52 - 3 * f, width: 26 + 6 * f, height: 24 + 6 * f)), 0x936D42, 1.8)
    } else {
      stroke(Path(ellipseIn: CGRect(x: 85, y: 51, width: 28, height: 26)), 0x936D42, 1.2)
    }
  }
  func mesangialSweep(_ track: GalaxySSIHealthAtlasMesangialRoutes.Track, _ start: Double, _ end: Double, _ color: UInt32, _ weight: Double) {
    let from = max(0, start), to = min(1, end)
    guard to > from else { return }
    stroke(track.path.trimmedPath(from: from, to: to), color, weight)
  }
}
