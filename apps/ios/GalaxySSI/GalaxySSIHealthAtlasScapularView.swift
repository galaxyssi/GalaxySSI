import SwiftUI

struct GalaxySSIHealthAtlasScapularView: View {
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let phase: Double
  let language: String
  var body: some View {
    Canvas { context, size in
      let scale = min(size.width,size.height)/360
      guard scale > 0 else { return }
      var local = context
      local.translateBy(x:(size.width-360*scale)/2,y:(size.height-360*scale)/2)
      local.scaleBy(x:scale,y:scale)
      let art = GalaxySSIHealthAtlasIllustratedDrawing(context:local,language:language)
      art.gradient(Path(roundedRect:CGRect(x:0,y:0,width:360,height:360),cornerRadius:8),0,360,0xE8F4F3,0xFBF0DF)
      let step = story.chapter(phase), t = GalaxySSIHealthAtlasScapularMotion.safe(story.fraction(phase))
      let frame = GalaxySSIHealthAtlasScapularPose(GalaxySSIHealthAtlasScapularMotion.pose(step,t))
      art.scapularFoundation(frame,step)
      art.scapularSerratus(frame,step == 0 ? t : 1)
      art.scapularBones(frame)
      art.scapularTrapezius(frame,step == 0 ? t : -1)
      if (1...3).contains(step) { art.scapularPulls(frame,step) }
      if step >= 3 { art.scapularSocket(frame,returning:step == 4) }
      art.scapularLabels(frame,step,t)
    }.aspectRatio(1,contentMode:.fit).clipped()
      .accessibilityElement(children:.ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption,language))
      .accessibilityIdentifier("atlas-function-scapular-rotation-art")
  }
}
