import SwiftUI

private typealias MarrowTissue = GalaxySSIHealthAtlasMarrowGeometry
private typealias MarrowVessel = GalaxySSIHealthAtlasMarrowMotion

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func marrowTissue(flow: Double, release: Bool) {
    var local = context; local.clip(to: MarrowTissue.field)
    let art = copy(local)
    art.gradient(MarrowTissue.field,74,287,0xFFF0E5,0xEBC8C3)
    for (index, point) in MarrowTissue.marrowCells.enumerated() {
      let radius = 5.5 + Double((index * 2) % 6)
      art.disc(point.x,point.y,radius,0xEAC1C7,border: 0xCD9DA9)
      art.disc(point.x - 1,point.y,radius * 0.44,0xB587A0)
    }
    art.gradient(MarrowTissue.trabecula,74,170,0xFFEDC9,0xDDB994); art.stroke(MarrowTissue.trabecula,MarrowTissue.boneEdge,1.3)
    for i in 0...5 {
      let x = 34 + Double(i) * 9, y = 124 - Double(i) * 7
      art.oval(x - 4,y - 1.8,x + 3,y + 1.8,fill: 0xCFA587,border: 0xC4987B)
    }
    art.fill(MarrowTissue.stroma,0xD3B8B3); art.stroke(MarrowTissue.stroma,0x9E7884,1)
    art.oval(104,149,120,155,fill: 0xA8839B,border: MarrowTissue.leader)
    art.gradient(MarrowTissue.lumen,190,271,0xF7DDD9,0xDCA0A5); art.stroke(MarrowTissue.lumen,MarrowTissue.wall,1.3)
    for x in stride(from: 40, through: 332, by: 29) {
      let fx = Double(x)
      art.marrowEndothelium(fx,MarrowVessel.vesselY(fx) - 25)
      art.marrowEndothelium(fx - 9,MarrowVessel.vesselY(fx - 9) + 25)
    }
    local.clip(to: MarrowTissue.lumen)
    let blood = copy(local)
    for i in 0...6 {
      let x = MarrowVessel.bloodX(flow: flow,index: i), y = MarrowVessel.vesselY(x) + (i % 2 == 0 ? 11 : -11)
      blood.marrowRedCell(x,y,radius: release ? 7 : 9,tilt: Double(i) * 13 - 35)
    }
    stroke(MarrowTissue.field,MarrowTissue.boneEdge,1)
  }
  private func marrowEndothelium(_ x: Double, _ y: Double) {
    oval(x - 7,y - 2.35,x + 7,y + 2.35,fill: 0xC18393,border: MarrowTissue.vesselNucleus)
  }
  func marrowCallout(_ key: String, _ x: Double, _ baseline: Double, _ width: Double, _ tx: Double, _ ty: Double) {
    let tail = baseline + (ty > baseline ? 6 : -15)
    line(x,tail,tx,ty,MarrowTissue.leader,1.05); disc(tx,ty,2,MarrowTissue.leader,border: Self.cream)
    label(key,x,baseline,width)
  }
  func marrowSinusoidLabel() {
    marrowCallout("marrow_story_label_sinusoid",238,320,148,239,MarrowVessel.vesselY(239) + 15)
  }
}
