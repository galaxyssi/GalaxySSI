import SwiftUI

private typealias BrainstemHead = GalaxySSIHealthAtlasBrainstemShapes
private typealias BrainstemNetwork = GalaxySSIHealthAtlasBrainstemMotion

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func brainstemHead() {
    oval(195,77,220,100,fill: 0xE4AFBD,border: 0xB47C93)
    for y in stride(from: 84, through: 96, by: 4) { line(202,Double(y),215,Double(y - 2),0xBA8197,1) }
    gradient(BrainstemHead.brain,41,99,0xF8CADB,0xE5AABF); stroke(BrainstemHead.brain,0xB47C93,1.3)
    stroke(BrainstemHead.folds,0xC187A1,1.2); fill(BrainstemHead.stem,0xCDB7DF); stroke(BrainstemHead.stem,BrainstemHead.neural,1.3)
    line(138,99,146,99,0xAF817C,1.1)
  }
  func brainstemPulse(_ t: Double) {
    let radius = 9 + 7 * t, circle = Path(ellipseIn: CGRect(x: 191 - radius, y: 101 - radius, width: 2 * radius, height: 2 * radius))
    var pulse = context; pulse.opacity *= Double(Int(220 * BrainstemNetwork.envelope(t))) / 255
    copy(pulse).stroke(circle,0x8B70A3,1.5)
  }
  func brainstemNetwork(_ burst: Double) {
    line(194,103,251,89,BrainstemHead.guide,1); disc(191,101,3.5,0xE9D8F1,border: BrainstemHead.neural)
    oval(250,52,323,114,fill: 0xEEE4F2,border: 0xB7A2C5)
    let network = BrainstemNetwork.network, connections = BrainstemNetwork.connections
    for i in stride(from: 0, to: connections.count, by: 2) {
      let a = connections[i] * 2, b = connections[i + 1] * 2
      line(network[a],network[a + 1],network[b],network[b + 1],BrainstemHead.quietNeural,1 + burst)
    }
    for i in stride(from: 0, to: network.count, by: 2) {
      disc(network[i],network[i + 1],3.4 + 2.8 * burst,0xD2BAE0,border: BrainstemHead.neural)
      if burst > 0.25 { disc(network[i],network[i + 1],1.7 + burst,BrainstemHead.neural) }
    }
  }
  func brainstemLabels(_ expansion: Double) {
    brainstemCallout("brainstem_story_stem",61,58,111,103,184,91)
    label("brainstem_story_network",286,41,130)
    brainstemCallout("brainstem_story_cord",282,143,141,220,196,128)
    brainstemCallout("brainstem_story_phrenic",61,199,111,111,145,196)
    brainstemCallout("brainstem_story_lungs",299,218,79,269,230,224)
    let dome = BrainstemNetwork.diaphragmCenter(expansion)
    line(181,315,181,dome + 4,BrainstemHead.guide,1); disc(181,dome + 4,1.6,BrainstemHead.guide)
    label("brainstem_story_diaphragm",181,332,133)
  }
  private func brainstemCallout(_ key: String, _ x: Double, _ y: Double, _ width: Double, _ railX: Double, _ targetX: Double, _ targetY: Double) {
    line(railX,y + 5,targetX,targetY,BrainstemHead.guide,1); disc(targetX,targetY,1.6,BrainstemHead.guide); label(key,x,y,width)
  }
}
