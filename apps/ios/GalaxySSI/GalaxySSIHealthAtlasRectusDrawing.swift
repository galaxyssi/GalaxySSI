import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func rectusScene(_ motion: GalaxySSIHealthAtlasRectusMotion, _ step: Int, _ t: Double) {
    let d = GalaxySSIHealthAtlasRectusDeflection.self, g = GalaxySSIHealthAtlasRectusGeometry.self
    rectusTissue(d.wall.deflect(motion),69,281,0xE7F2EE,0xCCDEDB,0x91A7A5)
    rectusTissue(d.ribCage.deflect(motion),80,169,0xFCF8EB,0xDFD7C5,0x998A77)
    let ribs = d.ribLines.deflect(motion)
    stroke(ribs,0xC4B49F,3.6); stroke(ribs,0xFCF5E7,2.05)
    rectusTissue(d.cartilage.deflect(motion),80,169,0xFCF8EB,0xDFD7C5,0x998A77)
    rectusTissue(d.spine.deflect(motion),80,169,0xFCF8EB,0xDFD7C5,0x998A77)
    stroke(d.discs.deflect(motion),0xA0B6B6,2.4)
    rectusTissue(g.pelvis,239,306,0xF8F4E7,0xD7CBB5,0x998A77)
    stroke(g.pelvicDetail,0xB7A68F,1.65); line(105,308,226,308,0x91A7A5,1.25)
    let belly = d.rectus.deflect(motion)
    rectusTissue(belly,137,260,0xEDC4BD,0xC08788,0xA06269)
    var tint = context; tint.opacity = Double(Int(50*motion.tone))/255
    copy(tint).fill(belly,0xA25361)
    stroke(d.fascicles.deflect(motion),0xF6DCD1,1+0.6*motion.tone)
    stroke(d.intersections.deflect(motion),0xF2DFCF,2.5)
    if step != 4 || t < 0.92 { rectusDirection(step >= 3) }
    rectusLabels(motion)
  }
  private func rectusTissue(_ p: Path, _ top: Double, _ bottom: Double, _ from: UInt32, _ to: UInt32, _ border: UInt32) {
    gradient(p,top,bottom,from,to); stroke(p,border,1.4)
  }
  private func rectusDirection(_ returning: Bool) {
    let p = Path { p in
      p.move(to:CGPoint(x:233,y:46))
      p.addQuadCurve(to:CGPoint(x:297,y:68),control:CGPoint(x:269,y:38))
    }
    stroke(p,Self.blue,1.8)
    if returning { arrow(243,44,233,46,Self.blue) } else { arrow(290,61,297,68,Self.blue) }
  }
}
