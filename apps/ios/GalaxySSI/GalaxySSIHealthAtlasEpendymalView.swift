import SwiftUI

struct GalaxySSIHealthAtlasEpendymalView: View {
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let phase: Double
  let language: String
  var body: some View {
    Canvas { context, size in
      let scale = min(size.width, size.height)/360
      guard scale > 0 else { return }
      var local = context
      local.translateBy(x: (size.width-360*scale)/2, y: (size.height-360*scale)/2)
      local.scaleBy(x: scale, y: scale)
      let field = GalaxySSIHealthAtlasEpendymalGeometry.field
      local.clip(to: field)
      let art = GalaxySSIHealthAtlasIllustratedDrawing(context: local, language: language)
      art.gradient(field, 0, 248, 0xEDF6FB, 0xC0E0EC)
      let step = story.chapter(phase), t = GalaxySSIHealthAtlasEpendymalMotion.phase(story.fraction(phase))
      if step != 0 { art.stroke(GalaxySSIHealthAtlasEpendymalGeometry.bulkGuide, 0x65F9FDFF, 2) }
      let close = step == 1, depth = close ? 94.0 : 62, top = close ? 193.0 : 202
      let count = close ? 5 : 7, left = close ? 24.0 : 19, width = (360-2*left)/Double(count)
      art.ependymalTissue(top,depth)
      for i in -1...count {
        let x = left+Double(i)*width
        art.ependymalWallCell(x,x+width,top,depth,i,close && i == 2)
      }
      for i in -1...count {
        let x = left+Double(i)*width, direction = step == 4 && i < 3 ? -1.0 : 1.0
        let phase = GalaxySSIHealthAtlasEpendymalMotion.beat(step,t,i)
        let length = GalaxySSIHealthAtlasEpendymalMotion.length(step,i)
        art.ependymalTuft(x+width/2,top,length,phase,direction,close && i == 2)
      }
      art.ependymalLabels(step,top,t)
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-ependymal-flow-art")
  }
}
