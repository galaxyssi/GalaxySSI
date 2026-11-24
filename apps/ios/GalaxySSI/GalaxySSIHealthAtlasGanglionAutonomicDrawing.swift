import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func ganglionAutonomic(_ t: Double) {
    let g = GalaxySSIHealthAtlasGanglionGeometry.self, m = GalaxySSIHealthAtlasGanglionMotion.self, r = GalaxySSIHealthAtlasGanglionRoutes.self
    ganglionTissue(g.autonomicCapsule,90,257,0xFCF4E7,0xE8CFB6,0xC49A83)
    ganglionQuietSoma(138,123,10,12); ganglionQuietSoma(128,201,12,16)
    ganglionQuietSoma(191,238,14,11); ganglionQuietSoma(254,149,11,14)
    stroke(g.dendrites,0xA56A7D,3.7)
    ganglionFiber(g.receivingDendrite,0x91566D,5.6); ganglionFiber(g.output,0x91566D,4.2)
    oval(192,161,242,214,top:126,bottom:226,from:0xF4D5C9,to:0xCD929A,border:0x91566D)
    ganglionNucleus(215,185,9.5)
    ganglionFiber(g.input,0x96602C,4.2); ganglionTissue(g.terminal,90,257,0xFCF4E7,0xE8CFB6,0x96602C)
    disc(146,158,1.6,0x96602C); disc(149,164,1.5,0x96602C)
    let incoming = m.preganglionic(t), outgoing = m.postganglionic(t), contact = m.contact(t)
    if incoming > 0 && incoming < 1 { at(r.inputTrack.route,incoming) { x,y in disc(x,y,4.7,0x96602C,border:Self.cream) } }
    if contact > 0 {
      disc(158,159,1.55*contact,0x96602C); disc(161,164,1.45*contact,0x96602C)
    }
    if outgoing > 0 && outgoing < 1 { at(r.outputTrack.route,outgoing) { x,y in disc(x,y,4.7,0x91566D,border:Self.cream) } }
    arrow(37,172,65,169,0x96602C); arrow(299,207,327,210,0x91566D)
  }
}
