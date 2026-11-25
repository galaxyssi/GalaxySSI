import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func erectorPosterior(_ motion: GalaxySSIHealthAtlasErectorMotion) {
    context.draw(Image("HealthAtlasRegionalErectorSpinaePlate"),in:CGRect(x:0,y:42,width:360,height:280))
    label("erector_support_story_posterior",180,35,178)
    var c = context; c.opacity = Double(Int(70+110*motion.posteriorEmphasis))/255
    let art = copy(c)
    for side in [-1.0,1.0] {
      let x = 180+side*25
      art.stroke(Path(ellipseIn:CGRect(x:x-8,y:147,width:16,height:37)),0xA3667C,1.25)
    }
    erectorPosteriorLabels()
  }
}
