import SwiftUI

struct GalaxySSIHealthAtlasErectorView: View {
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
      let step = story.chapter(phase), motion = GalaxySSIHealthAtlasErectorMotion(step,story.fraction(phase))
      if step == 0 { art.erectorPosterior(motion) }
      else {
        // Supported and loaded chapters intentionally retain the same neutral geometry.
        if step == 2 { art.erectorSupport() }
        if step == 3 { art.erectorLoad() }
        art.erectorTrunk(motion.flexion); art.erectorBands(motion)
        if step == 1 { art.erectorExtension(motion.ease) }
        art.erectorSideLabels(step,motion)
      }
    }.aspectRatio(1,contentMode:.fit).clipped()
      .accessibilityElement(children:.ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption,language))
      .accessibilityIdentifier("atlas-function-erector-support-art")
  }
}
