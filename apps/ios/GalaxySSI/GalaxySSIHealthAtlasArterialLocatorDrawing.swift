import SwiftUI

private typealias ArterialLocator = GalaxySSIHealthAtlasArterialMotion
private typealias ArterialLocatorInk = GalaxySSIHealthAtlasArterialShapes

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func arterialLocator(step: Int, t: Double) {
    label("arterial_aortic_arch",85,28,132)
    for route in ArterialLocator.branches {
      let path = GalaxySSIHealthAtlasSectionLessonView.path(route,width: 360,height: 360)
      stroke(path,ArterialLocatorInk.outline,10); stroke(path,0xDD8891,7)
    }
    let arch = GalaxySSIHealthAtlasSectionLessonView.path(ArterialLocator.arch,width: 360,height: 360)
    stroke(arch,ArterialLocatorInk.outline,20); stroke(arch,0xDD8891,17); stroke(arch,0xEDA9A3,8)
    at(ArterialLocator.arch,0.37) { x, y in
      line(x + 11,y + 2,166,105,ArterialLocatorInk.guide,1.1)
      disc(x,y,10,0x26FFF4E8,border: ArterialLocatorInk.guide)
    }
    label("arterial_from_heart",48,153,90)
    if step != 0 {
      at(ArterialLocator.arch,min(1,max(0,t * 0.62 + 0.1))) { x, y in
        disc(x,y,3.4,Self.cream,border: step == 2 ? ArterialLocatorInk.pulse : ArterialLocatorInk.blood)
      }
    }
  }
  func arterialSection(step: Int, t: Double, expansion: Double) {
    let x = 217.0, y = 93.0, r = 23 + 7 * expansion
    label("arterial_cross_section",x,28,174)
    disc(x,y,r + 16,0xE9BCA7,border: ArterialLocatorInk.outline)
    disc(x,y,r + 10,0xDA8991,border: ArterialLocatorInk.outline)
    disc(x,y,r + 2.5,0xF5BEA5); disc(x,y,r,0xFAE0CC,border: ArterialLocatorInk.outline)
    for offset in [5.0,8] {
      let radius = r + offset, circle = Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius))
      stroke(circle,0xF4BAAB,1.25)
    }
    arterialSectionLabel("arterial_outer_wall",322,62,x + (r + 13) * 0.66,y - (r + 13) * 0.75)
    arterialSectionLabel("arterial_elastic_media",322,96,x + r + 7,y)
    arterialSectionLabel("arterial_intima",316,131,x + (r + 1) * 0.71,y + (r + 1) * 0.71)
    if step == 0 {
      let focus = r + 7
      stroke(ArterialLocatorInk.arc(x - focus,y - focus,x + focus,y + focus,start: -138,sweep: 48 + 288 * t),ArterialLocatorInk.pulse,2.4)
    } else { label("arterial_lumen",x,y + 4,(r - 3) * 2) }
  }
  private func arterialSectionLabel(_ key: String, _ x: Double, _ baseline: Double, _ targetX: Double, _ targetY: Double) {
    line(targetX,targetY,x - 32,baseline - 4,ArterialLocatorInk.guide,0.95)
    disc(targetX,targetY,1.65,ArterialLocatorInk.guide,border: Self.cream); label(key,x,baseline,62)
  }
}
