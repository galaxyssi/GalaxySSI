import SwiftUI

private typealias AdrenalCirculation = GalaxySSIHealthAtlasAdrenalGeometry
private typealias AdrenalFlow = GalaxySSIHealthAtlasAdrenalMotion

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func adrenalCirculate(_ t: Double) {
    var local = context; local.translateBy(x: 70, y: 77); local.scaleBy(x: 0.38, y: 0.38); local.translateBy(x: -105, y: -134)
    let mini = copy(local); mini.adrenalCellTissue(AdrenalCirculation.receivingCell)
    mini.adrenalNucleus(183,199,rx: 25,ry: 19); mini.adrenalVesicle(248,222,size: 8)
    oval(217,89,303,165,top: 96,bottom: 260,from: 0xFFE7D3,to: 0xE9B4AA,border: AdrenalCirculation.cellInk)
    adrenalNucleus(264,122,rx: 14,ry: 10); adrenalVesicle(247,142,size: 4.5)
    oval(135,94,216,179,top: 96,bottom: 260,from: 0xFFE7D3,to: 0xE9B4AA,border: AdrenalCirculation.cellInk)
    adrenalNucleus(168,132,rx: 14,ry: 11)
    adrenalVesicle(188,151,size: 6); adrenalVesicle(175,166,size: 5); adrenalVesicle(193,136,size: 4)
    adrenalVessel(AdrenalCirculation.path(AdrenalCirculation.capillaryRoute),width: 42)
    adrenalBloodCells(AdrenalCirculation.capillaryRoute,phase: 0.74 * t)
    for i in 0...7 {
      guard let particle = AdrenalFlow.circulation(t,index: i) else { continue }
      at(AdrenalCirculation.entryTrackRoute,particle.phase) { x, y in
        adrenalHormone(x + Double(i % 3 - 1) * 4,y + (Double(i % 4) - 1.5) * 6 * particle.phase,size: 3.5,alpha: particle.alpha)
      }
    }
    adrenalLeader("adrenal_medulla_story_art_cell",152,66,147,161,105)
    adrenalLeader("adrenal_medulla_story_art_capillary",75,293,112,86,243)
    adrenalLeader("adrenal_medulla_story_art_catecholamines",252,293,158,235,226)
  }
  func adrenalSettle(_ t: Double) {
    adrenalVessel(AdrenalCirculation.path(AdrenalCirculation.restingVesselRoute),width: 42)
    adrenalBloodCells(AdrenalCirculation.restingVesselRoute,phase: 0.52 * t)
    for i in 0...9 {
      let particle = AdrenalFlow.resting(t,index: i)
      at(AdrenalCirculation.restingVesselRoute,particle.phase) { x, y in
        adrenalHormone(x,y + 11 * wave(Double(i) * 0.39),size: 3.4,alpha: particle.alpha)
      }
    }
    line(56,196,56,304,AdrenalCirculation.guide,1.1); arrow(56,304,323,304,AdrenalCirculation.guide)
    for x in stride(from: 60, through: 311, by: 11) { line(Double(x),282,Double(x + 6),282,AdrenalCirculation.guide,1) }
    let recovery = AdrenalCirculation.path(AdrenalCirculation.recoveryCurveRoute)
    stroke(recovery,0xBA9DBF,2)
    if t > 0 { stroke(recovery.trimmedPath(from: 0,to: CGFloat(t)),AdrenalCirculation.cargo,3) }
    at(AdrenalCirculation.recoveryCurveRoute,t) { disc($0,$1,4.1,AdrenalCirculation.cargo,border: Self.cream) }
    label("adrenal_medulla_story_art_blood",234,68,123); arrow(273,65,313,65,AdrenalCirculation.guide)
    label("adrenal_medulla_story_art_level",156,182,224)
    label("adrenal_medulla_story_art_baseline",110,331,116)
    line(110,317,110,305,AdrenalCirculation.guide,1); line(110,303,110,282,AdrenalCirculation.guide,1)
    label("adrenal_medulla_story_art_time",296,331,86)
  }
}
