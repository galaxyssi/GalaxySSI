import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func placentalOrient(_ t: Double) {
    context.draw(Image("HealthAtlasRegionalPlacentaPlate"),in:CGRect(x:20,y:53,width:320,height:249))
    let r = 12+6*GalaxySSIHealthAtlasPlacentalMotion.emphasis(t)
    let ring = Path(ellipseIn:CGRect(x:210.2-r,y:202.4-r,width:2*r,height:2*r))
    stroke(ring,0xFDF4DA,3.4); stroke(ring,0x3E7582,1.4)
    placentalOrientLabels()
  }
  func placentalVillus() {
    let g = GalaxySSIHealthAtlasPlacentalGeometry.self
    gradient(g.field,92,263,0xF8E6DF,0xE9BFC0); stroke(g.field,0xB88C94,1.1)
    gradient(g.surface,92,257,0xD9A2A2,0xB77987); stroke(g.surface,0x8F615F,1.5)
    gradient(g.core,93,250,0xF0D8C0,0xE6B494); stroke(g.core,0xC18D7E,1)
    stroke(g.surfaceLight,0xF1CBC0,1.35); stroke(g.stromalFibers,0xC79580,1.15)
    for (x,y,angle) in g.nuclei {
      var c = context; c.translateBy(x:x,y:y); c.rotate(by:.degrees(angle))
      copy(c).oval(-3.6,-1.6,3.6,1.6,fill:0x93677C,border:0x82586E)
    }
    var c = context; c.clip(to:g.surface)
    let art = copy(c)
    art.stroke(g.fetalRoute,0x527681,18); art.stroke(g.fetalRoute,0xB2D2D2,14)
  }
}
