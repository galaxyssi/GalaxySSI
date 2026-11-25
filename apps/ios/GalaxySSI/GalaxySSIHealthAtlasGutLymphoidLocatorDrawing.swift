import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func gutLymphoidLocate(_ t: Double) {
    let m = GalaxySSIHealthAtlasGutLymphoidMotion.self
    context.draw(Image("HealthAtlasFunctionGutLymphoidLocator"),in:CGRect(x:0,y:40,width:360,height:280))
    gutLymphoidLocatorFocus(142,248,27,32,0x895D84,m.appendixFocus(t))
    gutLymphoidLocatorFocus(251,165,36,26,Self.teal,m.ileumFocus(t))
    gutLymphoidLocateLabels()
  }
  func gutLymphoidCompare(_ t: Double) {
    let m = GalaxySSIHealthAtlasGutLymphoidMotion.self, left = m.appendixScale(t), right = m.ileumScale(t)
    gutLymphoidZoom(0,175,92,183,left); gutLymphoidZoom(175,360,266,183,right)
    gutLymphoidCompareLabels(left,right)
  }
  private func gutLymphoidLocatorFocus(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double, _ color: UInt32, _ t: Double) {
    var c = context; c.opacity = Double(Int(199-65*t))/255
    let scale = 1.18-0.18*t
    let p = Path { p in
      p.addArc(center:.zero,radius:1,startAngle:.degrees(-100),endAngle:.degrees(-100+52+296*t),clockwise:false)
    }.applying(CGAffineTransform(a:rx*scale,b:0,c:0,d:ry*scale,tx:x,ty:y))
    copy(c).stroke(p,color,2)
  }
  private func gutLymphoidZoom(_ left: Double, _ right: Double, _ x: Double, _ y: Double, _ amount: Double) {
    var c = context; c.clip(to:Path(CGRect(x:left,y:119,width:right-left,height:149)))
    c.translateBy(x:x,y:y); c.scaleBy(x:amount,y:amount); c.translateBy(x:-x,y:-y)
    c.draw(Image("HealthAtlasFunctionGutLymphoidComparison"),in:CGRect(x:0,y:40,width:360,height:280))
  }
}
