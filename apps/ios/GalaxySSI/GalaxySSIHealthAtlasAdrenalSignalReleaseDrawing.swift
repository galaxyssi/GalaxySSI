import SwiftUI

private typealias AdrenalSignal = GalaxySSIHealthAtlasAdrenalGeometry
private typealias AdrenalSignalMotion = GalaxySSIHealthAtlasAdrenalMotion

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func adrenalSignal(_ t: Double) {
    adrenalCellTissue(AdrenalSignal.receivingCell); adrenalNucleus(213,199,rx: 29,ry: 21)
    for i in 0...6 { adrenalVesicle(131 + Double(i) * 22,220 + 18 * wave(Double(i) * 0.09),size: 5.5) }
    let branch = AdrenalSignal.path(AdrenalSignal.nerveBranchRoute), nerve = AdrenalSignal.path(AdrenalSignal.nerveRoute)
    stroke(branch,AdrenalSignal.nerveInk,8); stroke(branch,Self.sand,5)
    stroke(nerve,AdrenalSignal.nerveInk,10); stroke(nerve,Self.sand,7)
    oval(132,108,152,123,fill: Self.sand,border: AdrenalSignal.nerveInk); oval(167,105,190,121,fill: Self.sand,border: AdrenalSignal.nerveInk)
    for i in 0...2 {
      let x = 166 + 10 * Double(i), y = 133 - Double(i) * 0.7
      line(x,y - 2,x,y + 3,Self.teal,2.6)
    }
    for i in 0...1 {
      if let pulse = AdrenalSignalMotion.pulse(t,index: i) { at(AdrenalSignal.nerveRoute,pulse) { disc($0,$1,3.5,0x805626,border: 0xFFEDD0) } }
      if let crossing = AdrenalSignalMotion.crossing(t,index: i) {
        for j in 0...3 {
          let x = 173 + 4 * Double(j) + 3 * crossing * wave(Double(j) * 0.4)
          disc(x,120 + 10 * crossing - Double(j % 2) * 2,1.8,Self.teal)
        }
      }
    }
    adrenalLeader("adrenal_medulla_story_art_nerve",94,60,150,86,92)
    adrenalLeader("adrenal_medulla_story_art_transmitter",262,104,144,191,125)
    adrenalLeader("adrenal_medulla_story_art_cell",246,300,155,249,251)
  }
  func adrenalRelease(_ t: Double) {
    let approach = AdrenalSignalMotion.approach(t), pore = AdrenalSignalMotion.pore(t)
    adrenalCellTissue(AdrenalSignal.secretingCell(pore: pore)); adrenalNucleus(241,151,rx: 31,ry: 22)
    let stored: [(Double, Double, Double)] = [(113,141,10),(92,172,7),(136,189,8),(151,127,6),(266,192,7)]
    for (x, y, size) in stored { adrenalVesicle(x,y,size: size) }
    if pore == 0 { adrenalVesicle(184 - 15 * (1 - approach),155 + 51 * approach,size: 11) }
    else {
      for i in 0...5 {
        let particle = AdrenalSignalMotion.released(t,index: i)
        adrenalHormone(particle.x,particle.y,size: 3.4,alpha: particle.alpha)
      }
    }
    adrenalLeader("adrenal_medulla_story_art_vesicle",91,66,147,105,136)
    adrenalLeader("adrenal_medulla_story_art_fusion",263,250,126,197,221)
    adrenalLeader("adrenal_medulla_story_art_catecholamines",147,311,174,173,271)
  }
}
