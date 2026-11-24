import SwiftUI

private typealias EndometriumGland = GalaxySSIHealthAtlasEndometriumGeometry
private typealias EndometriumSecretion = GalaxySSIHealthAtlasEndometriumMotion

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func endometriumGland(_ x: Double, top: Double, bend: Double, index: Int, t: Double, secreting: Bool, tissue: Path) {
    let route = EndometriumGland.channel(x: x,top: top,bend: bend,index: index)
    let path = GalaxySSIHealthAtlasSectionLessonView.path(route,width: 360,height: 360)
    var local = context; local.clip(to: tissue)
    let art = copy(local), width = 10 + 3.4 * bend
    art.stroke(path,EndometriumGland.lining,width + 2.4); art.stroke(path,0xEFB1B9,width); art.stroke(path,Self.cream,width - 5.3)
    if secreting {
      for j in 0...2 {
        guard let particle = EndometriumSecretion.secretion(t,gland: index,particle: j) else { continue }
        art.at(route,particle.fraction) { art.disc($0,$1,particle.radius,0xAD782F) }
      }
    }
  }
}
