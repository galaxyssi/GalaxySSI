import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func tonsilCompare(_ t: Double) {
    typealias Geometry = GalaxySSIHealthAtlasTonsilGeometry
    typealias Motion = GalaxySSIHealthAtlasTonsilMotion
    let scale = Motion.cryptScale(t)
    var local = context
    local.translateBy(x: 94, y: 134); local.scaleBy(x: scale, y: scale); local.translateBy(x: -94, y: -134)
    let art = copy(local)
    art.tonsilPane(Geometry.palatineCut)
    art.tonsilFollicle(65, 178, 15, 21)
    art.tonsilFollicle(129, 181, 17, 25)
    art.tonsilFollicle(99, 227, 23, 12)
    art.stroke(Geometry.smallCrypt, 0x8F4B66, 6); art.stroke(Geometry.smallCrypt, Self.cream, 3.5)
    art.stroke(Geometry.smallCrypt.trimmedPath(from: 0, to: Motion.cryptTrace(t)), 0x8F4B66, 2.4)
    tonsilPane(Geometry.adenoidCut, edge: 0x6C557E)
    tonsilFollicle(225, 179, 14, 18)
    tonsilFollicle(274, 181, 19, 23)
    tonsilFollicle(306, 217, 14, 13)
    tonsilFollicle(248, 221, 20, 13)
    stroke(Geometry.folds, 0x6C557E, 5); stroke(Geometry.folds, 0xEFB7A5, 2.7)
  }
  func tonsilEncounter(_ t: Double) {
    typealias Geometry = GalaxySSIHealthAtlasTonsilGeometry
    typealias Routes = GalaxySSIHealthAtlasTonsilRoutes
    typealias Motion = GalaxySSIHealthAtlasTonsilMotion
    tonsilPane(Geometry.cryptSection)
    tonsilFollicle(81, 170, 25, 34)
    tonsilFollicle(104, 246, 34, 32)
    tonsilFollicle(254, 234, 40, 39)
    tonsilFollicle(282, 155, 22, 25)
    tonsilEpithelium(Geometry.cryptSurface, points: Routes.surfacePoints)
    at(Routes.approachTrack, Motion.encounter(t, lag: 0.24) * 0.56) { x, y in
      tonsilAntigen(x + 18, y - 10, 2.5, edge: 0xBC9463)
    }
    at(Routes.approachTrack, Motion.encounter(t)) { x, y in tonsilAntigen(x, y, 5.2) }
    tonsilAntigenKey()
  }
}
