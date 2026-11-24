import SwiftUI

private typealias GastricLocator = GalaxySSIHealthAtlasGastricAcidGeometry
private typealias GastricLocatorMotion = GalaxySSIHealthAtlasGastricAcidMotion

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func gastricAcidLocate(_ t: Double) {
    gastricAcidStomachPlate()
    for i in 0...5 {
      let x = 116 + 10 * Double(i)
      line(x,147 - 6 * Double(i),x + 4,144 - 6 * Double(i),GastricLocator.guide,1)
      line(x,156 + 16 * Double(i),x + 4,163 + 16 * Double(i),GastricLocator.guide,1)
    }
    gradient(GastricLocator.gland,106,288,0xF8DDD0,0xE0A9AA); stroke(GastricLocator.gland,GastricLocator.tissueEdge,1.5)
    for i in 0...4 {
      gastricAcidGlandCell(226 - Double(i) * 1.7,156 + 21 * Double(i),selected: false)
      gastricAcidGlandCell(268 + 1.6 * Double(i % 2),157 + 21 * Double(i),selected: i == 1)
    }
    gastricAcidGlandCell(232,261,selected: false); gastricAcidGlandCell(251,271,selected: false); gastricAcidGlandCell(271,255,selected: false)
    fill(GastricLocator.glandSpace,GastricLocator.lumenFill); stroke(GastricLocator.glandSpace,GastricLocator.lumenEdge,1.35)
    let p = GastricLocatorMotion.locate(t)
    gastricAcidFocus(109,151,radius: 9 + 3 * (1 - p),width: 1.4)
    at(GastricLocator.locatorTrack,p) { disc($0,$1,3.4,GastricLocator.focus,border: Self.cream) }
    gastricAcidFocus(270,178,radius: 15 + 3 * wave(p * 0.5),width: 1.6)
    gastricAcidCallout("gastric_acid_story_stomach",77,58,124,78,65,83,118)
    gastricAcidCallout("gastric_acid_story_gastric_gland",255,76,130,251,83,236,127)
    gastricAcidCallout("gastric_acid_story_parietal_cell",268,315,143,306,299,278,181)
  }
  private func gastricAcidGlandCell(_ x: Double, _ y: Double, selected: Bool) {
    oval(x - 11,y - 10,x + 11,y + 10,fill: selected ? 0xF1B59E : 0xEBC4C1,border: selected ? GastricLocator.tissueEdge : GastricLocator.rose)
    oval(x - 3,y - 4,x + 4,y + 3,fill: 0xBE89A9,border: Self.violet)
  }
  private func gastricAcidFocus(_ x: Double, _ y: Double, radius: Double, width: Double) {
    stroke(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),GastricLocator.focus,width)
  }
}
