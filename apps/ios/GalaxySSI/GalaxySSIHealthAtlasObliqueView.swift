import SwiftUI

struct GalaxySSIHealthAtlasObliqueView: View {
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
      let step = story.chapter(phase), fraction = story.fraction(phase)
      let t = fraction.isFinite ? min(1,max(0,fraction)) : 0
      let motion = GalaxySSIHealthAtlasObliqueMotion(step,t)
      art.obliqueAnatomy(motion); art.obliqueBands(motion)
      art.disc(180,177,4,0xDDE9E3,border:0x68878D)
      art.line(177,177,183,177,0x68878D,1); art.line(180,174,180,180,0x68878D,1)
      if step != 4 || t < 0.92 { art.obliqueDirection(motion) }
      art.obliqueLabels(motion)
    }.aspectRatio(1,contentMode:.fit).clipped()
      .accessibilityElement(children:.ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption,language))
      .accessibilityIdentifier("atlas-function-oblique-rotation-art")
  }
}
