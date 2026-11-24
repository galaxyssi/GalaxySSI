import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func clubDome(_ t: Double) {
    clubHumanWall(GalaxySSIHealthAtlasClubMotion.cilia(t))
    clubGranule(176, 176, 5.1)
  }
  func clubRelease(_ t: Double) {
    typealias Motion = GalaxySSIHealthAtlasClubMotion
    clubHumanWall(0.3)
    let dock = Motion.dock(t), exported = Motion.release(t, 0)
    if dock < 0.98 { clubGranule(182 - 6 * dock, 193 - 35 * dock, 6.5) }
    if dock >= 0.98 && exported < 0.94 {
      let pore = GalaxySSIHealthAtlasClubGeometry.releasePore
      fill(pore, 0xC4E4E5); line(171, 151, 181, 151, 0xC4E4E5, 2.5); stroke(pore, 0x815B35, 1.1)
    }
    for (i, path) in GalaxySSIHealthAtlasClubRoutes.releaseTracks.enumerated() {
      let progress = Motion.release(t, i)
      if progress > 0 { at(path, progress) { x, y in clubProtein(x, y) } }
    }
  }
  func clubSpread(_ t: Double) {
    typealias Routes = GalaxySSIHealthAtlasClubRoutes
    clubHumanWall(0.44)
    clubProtein(176, 141)
    for i in 0...5 {
      let travel = GalaxySSIHealthAtlasClubMotion.spread(t, i), path = i % 2 == 0 ? Routes.spreadLeft : Routes.spreadRight
      let fraction = 0.04 + 0.10 * Double(i / 2) + (0.45 + 0.06 * Double(i)) * travel
      at(path, fraction) { x, y in clubProtein(x, y + Double(i / 2 - 1) * 3) }
    }
  }
}
