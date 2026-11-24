import SwiftUI

struct GalaxySSIHealthAtlasPlacentalView: View {
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let phase: Double
  let language: String
  var body: some View {
    Canvas { context,size in
      let scale = min(size.width,size.height)/360
      guard scale > 0 else { return }
      var local = context
      local.translateBy(x:(size.width-360*scale)/2,y:(size.height-360*scale)/2)
      local.scaleBy(x:scale,y:scale)
      let art = GalaxySSIHealthAtlasIllustratedDrawing(context:local,language:language)
      art.gradient(Path(roundedRect:CGRect(x:0,y:0,width:360,height:360),cornerRadius:8),0,360,0xE8F4F3,0xFBF0DF)
      let step = story.chapter(phase), t = GalaxySSIHealthAtlasPlacentalMotion.phase(story.fraction(phase))
      if step == 0 { art.placentalOrient(t) }
      else {
        art.placentalVillus(); art.placentalFlows(t,step == 1)
        switch step {
        case 1: art.placentalRouteKey()
        case 2: art.placentalInterface(t)
        case 3: art.placentalGases(t)
        case 4: art.placentalGlucose(t)
        default: break
        }
        art.placentalAnatomyLabels()
      }
    }.aspectRatio(1,contentMode:.fit).clipped()
      .accessibilityElement(children:.ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption,language))
      .accessibilityIdentifier("atlas-function-placental-exchange-art")
  }
}
