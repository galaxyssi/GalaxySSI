import SwiftUI

private typealias GastricTransport = GalaxySSIHealthAtlasGastricAcidGeometry
private typealias GastricTransportTime = GalaxySSIHealthAtlasGastricAcidMotion

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func gastricAcidSignal(_ t: Double) {
    let p = GastricTransportTime.histamine(t), q = GastricTransportTime.recruit(t)
    oval(55,148,75,179,fill: 0xDDC2D4,border: Self.violet); disc(64,163,4,Self.violet)
    rounded(93,159,103,177,4,Self.violet)
    if p < 0.99 {
      disc(75 + 22 * p,158 + 10 * p,3.6,GastricTransport.focus,border: Self.cream)
      disc(72 + 21 * p,169 + 3 * p,2.6,GastricTransport.focus,border: Self.cream)
    } else { disc(96,167,3.6,GastricTransport.focus,border: Self.cream) }
    gastricAcidVesicle(198 + 18 * q,103 + 47 * q,fraction: q); gastricAcidVesicle(245 - 5 * q,131 + 20 * q,fraction: q)
    gastricAcidCallout("gastric_acid_story_histamine",69,70,119,70,77,81,153)
    gastricAcidCallout("gastric_acid_story_pump",249,47,120,253,55,240,149)
  }
  private func gastricAcidVesicle(_ x: Double, _ y: Double, fraction: Double) {
    if fraction < 0.92 { disc(x,y,7 * (1 - fraction * 0.55),Self.cream,border: Self.violet) }
    gastricAcidPump(x,y)
  }
  private func gastricAcidPump(_ x: Double, _ y: Double) {
    rounded(x - 6,y - 3.8,x + 6,y + 3.8,3,Self.violet); line(x - 1.7,y,x + 1.7,y,Self.cream,1.2)
  }
  func gastricAcidExchange(_ t: Double) {
    let p = GastricTransportTime.exchange(t)
    rounded(202,145,231,155,4,0xE8D5E5); gastricAcidPump(216,150)
    arrow(207,117,207,172,GastricTransport.acid); arrow(226,172,226,117,GastricTransport.potassium)
    gastricAcidIon(207,117 + 55 * p,color: GastricTransport.acid); gastricAcidIon(226,172 - 55 * p,color: GastricTransport.potassium)
    gastricAcidCallout("gastric_acid_story_pump",278,47,124,260,55,218,145)
    gastricAcidKey("gastric_acid_story_proton",99,color: GastricTransport.acid)
    gastricAcidKey("gastric_acid_story_potassium",257,color: GastricTransport.potassium)
  }
  func gastricAcidSecrete(_ t: Double) {
    let p = GastricTransportTime.chloride(t)
    gastricAcidPump(216,150); rounded(201,177,214,185,2,GastricTransport.chloride)
    line(208,179,208,183,Self.cream,1.2); arrow(208,219,208,170,GastricTransport.chloride)
    gastricAcidIon(208,219 - 49 * p,color: GastricTransport.chloride); arrow(306,124,306,91,GastricTransport.lumenEdge)
    for i in 0...3 {
      guard let f = GastricTransportTime.flow(t,index: i) else { continue }
      at(GastricTransport.secretionTrack,f) { x, y in gastricAcidIon(x,y + (i % 2 == 0 ? -4 : 4),color: i % 2 == 0 ? GastricTransport.acid : GastricTransport.chloride) }
    }
    gastricAcidCallout("gastric_acid_story_to_stomach",272,47,145,288,55,304,87)
    gastricAcidKey("gastric_acid_story_proton",99,color: GastricTransport.acid)
    gastricAcidKey("gastric_acid_story_chloride",257,color: GastricTransport.chloride)
  }
  private func gastricAcidKey(_ key: String, _ x: Double, color: UInt32) {
    gastricAcidIon(x - 62,337,color: color); label(key,x,342,111)
  }
  private func gastricAcidIon(_ x: Double, _ y: Double, color: UInt32) {
    if color == GastricTransport.chloride {
      rounded(x - 3.6,y - 3.6,x + 3.6,y + 3.6,1,color); line(x - 1.5,y,x + 1.5,y,Self.cream,1.1)
    } else {
      disc(x,y,4,color,border: Self.cream)
      if color == GastricTransport.potassium { disc(x,y,1.25,Self.cream) }
    }
  }
  func gastricAcidCallout(_ key: String, _ x: Double, _ y: Double, _ width: Double, _ lx: Double, _ ly: Double, _ tx: Double, _ ty: Double) {
    line(lx,ly,tx,ty,GastricTransport.guide,1.1); disc(tx,ty,1.7,GastricTransport.guide); label(key,x,y,width)
  }
}
