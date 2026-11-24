import SwiftUI

private typealias MarrowRenewal = GalaxySSIHealthAtlasMarrowGeometry
private typealias MarrowRenewalTime = GalaxySSIHealthAtlasMarrowMotion

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func marrowNiche(_ t: Double) {
    marrowTissue(flow: t * 0.54,release: false)
    let focus = MarrowRenewalTime.progress(t,start: 0.06,end: 0.84)
    var wash = context; wash.opacity *= Double(Int(62 + 135 * focus)) / 255
    copy(wash).fill(Path(ellipseIn: CGRect(x: 145, y: 115, width: 86, height: 77)),0xF9EAF4)
    marrowStem(187,156,radius: 22)
    marrowCallout("marrow_story_label_bone",72,43,99,61,97)
    marrowCallout("marrow_story_label_stroma",173,43,85,119,145)
    marrowCallout("marrow_story_label_stem",280,43,117,201,139)
    marrowSinusoidLabel()
  }
  func marrowRenewal(_ t: Double) {
    let frame = MarrowRenewalTime.renewal(t)
    if frame.shared {
      var local = context; local.translateBy(x: 0, y: 170)
      let art = copy(local), membrane = MarrowRenewal.renewal(frame)
      art.gradient(membrane,-27,30,0xE4DEF0,0xB498C3); art.stroke(membrane,MarrowRenewal.stem,1.3)
      let splitting = MarrowRenewalTime.progress(t,start: 0.13,end: 0.52)
      marrowNucleus(108,170,radius: 19 - 5 * splitting)
      if splitting > 0 { marrowNucleus(frame.right,170,radius: frame.radius * 0.48 * splitting) }
    } else {
      marrowStem(108,170,radius: frame.radius); marrowStem(frame.right,170,radius: frame.radius)
    }
    marrowCallout("marrow_story_label_stem",108,105,132,108,146)
    line(79,231,79,239,MarrowRenewal.leader,1.15); line(79,239,272,239,MarrowRenewal.leader,1.15)
    line(272,239,272,231,MarrowRenewal.leader,1.15)
    marrowCallout("marrow_story_label_pool",175,267,155,175,239)
  }
}
