import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func uterocervicalScene(_ step: Int, _ t: Double) {
    rounded(12, 21, 140, 344, 7, 0x70FFFFFF); rounded(150, 21, 348, 344, 7, 0x80FFFFFF)
    label("uterocervical_locator", 76, 43, 110); label("uterocervical_magnification", 249, 43, 178)
    uterocervicalLocator(step, t)
    switch step {
    case 0: uterocervicalUterus(t)
    case 1: uterocervicalCervix(t)
    default: uterocervicalVagina(t)
    }
  }
  func uterocervicalSurface(_ path: Path, _ top: Double, _ bottom: Double, _ from: UInt32, _ to: UInt32, _ border: UInt32) {
    gradient(path, top, bottom, from, to); stroke(path, border, 1.25)
  }
  func uterocervicalTrace(_ track: GalaxySSIHealthAtlasRegionalTrack, _ progress: Double) {
    if progress > 0 { stroke(track.path.trimmedPath(from: 0, to: progress), 0x24776D, 2.15) }
    at(track.route, progress) { x, y in disc(x, y, 2.9, 0x24776D, border: 0xFFF5E7) }
  }
  func uterocervicalCallout(_ key: String, _ x: Double, _ baseline: Double, _ width: Double, _ leadX: Double, _ leadY: Double, _ anchorX: Double, _ anchorY: Double) {
    line(leadX, leadY, anchorX, anchorY, 0x526F70, 1); disc(anchorX, anchorY, 2.3, 0xFFF5E7, border: 0x526F70)
    label("uterocervical_" + key, x, baseline, width)
  }
}
