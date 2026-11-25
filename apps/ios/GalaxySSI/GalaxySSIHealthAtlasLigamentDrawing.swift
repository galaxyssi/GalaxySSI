import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func ligamentScene(_ step: Int, _ t: Double) {
    let plate = GalaxySSIHealthAtlasLigamentPlate.self
    context.draw(Image("HealthAtlasFunctionLigaments"),in:CGRect(x:0,y:plate.top,width:plate.width,height:plate.height))
    ligamentCallout("ligament_guidance_story_femur",55,55,86,60,CGPoint(x:143,y:54),0x886E59)
    ligamentCallout("ligament_guidance_story_tibia",306,212,281,217,plate.display(plate.tibia),0x886E59)
    ligamentCallout("ligament_guidance_story_acl",47,104,67,109,plate.display(plate.aclFemur),0x30756C)
    ligamentCallout("ligament_guidance_story_pcl",313,104,293,109,plate.display(plate.pclFemur),0x77587A)
    let emphasis = plate.emphasis(t)
    let acl: Double? = (1...2).contains(step) || step == 4 ? emphasis : nil
    let pcl: Double? = step == 1 || (3...4).contains(step) ? emphasis : nil
    ligamentFootprint(plate.aclFemur,0x30756C,acl); ligamentFootprint(plate.aclTibia,0x30756C,acl)
    ligamentFootprint(plate.pclFemur,0x77587A,pcl); ligamentFootprint(plate.pclTibia,0x77587A,pcl)
    if step >= 2 {
      line(31,283,329,283,0xADC1BA,1)
      label("ligament_guidance_story_direction_key",180,302,306)
      if step >= 3 { ligamentRestraint(159,83,0x77587A,emphasis,"ligament_guidance_story_backward_slide") }
      if step == 2 || step == 4 { ligamentRestraint(201,277,0x30756C,emphasis,"ligament_guidance_story_forward_slide") }
    }
  }
  private func ligamentCallout(_ key: String, _ x: Double, _ y: Double, _ lx: Double, _ ly: Double, _ target: CGPoint, _ color: UInt32) {
    line(lx,ly,target.x,target.y,color,1.05); disc(target.x,target.y,2.35,color,border:Self.cream)
    label(key,x,y,77)
  }
  private func ligamentFootprint(_ marker: CGPoint, _ color: UInt32, _ focus: Double?) {
    let p = GalaxySSIHealthAtlasLigamentPlate.display(marker)
    disc(p.x,p.y,2.55,color,border:Self.cream)
    guard let focus else { return }
    var c = context; c.opacity = Double(Int(196-76*focus))/255
    let r = 4.5+4.5*focus
    copy(c).stroke(Path(ellipseIn:CGRect(x:p.x-r,y:p.y-r,width:2*r,height:2*r)),color,1.55)
  }
  private func ligamentRestraint(_ from: Double, _ stop: Double, _ color: UInt32, _ focus: Double, _ key: String) {
    // Fixed arrows show the checked direction, not force or tibial displacement.
    let direction = stop > from ? 1.0 : -1.0, tip = stop-direction*8
    arrow(from,319,tip,319,color); line(stop,313,stop,325,color,1.55+1.45*focus)
    label(key,(from+stop)/2,341,136)
  }
}
