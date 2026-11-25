import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func ganglionSensory(_ t: Double) {
    let g = GalaxySSIHealthAtlasGanglionGeometry.self
    ganglionTissue(g.sensoryCapsule,90,257,0xFCF4E7,0xE8CFB6,0xC49A83)
    stroke(g.sensoryFibers,0xC49A83,1.5)
    ganglionQuietSoma(129,139,12,14); ganglionQuietSoma(222,137,13,16)
    ganglionQuietSoma(152,220,15,11); ganglionQuietSoma(204,227,14,13)
    ganglionTissue(g.cord,116,229,0xF6DFCD,0xD5AAAD,0x996A64); fill(g.dorsalHorn,0xBC929F)
    ganglionFiber(g.sensoryStem,0x326C78,4.5); ganglionFiber(g.sensoryAxon,0x326C78,4.5)
    arrow(324,205,296,205,0x326C78); arrow(111,200,83,196,0x326C78)
    oval(147,98,201,151,fill:0xB6D5C5,border:0x4F8178)
    oval(151,102,197,147,top:91,bottom:214,from:0xFFECD6,to:0xDFA295,border:0x996A64)
    ganglionNucleus(173,123,9)
    let f = GalaxySSIHealthAtlasGanglionMotion.sensory(t)
    if f > 0 && f < 1 {
      at(GalaxySSIHealthAtlasGanglionRoutes.sensoryTrack.route,f) { x,y in disc(x,y,4.7,0x326C78,border:Self.cream) }
    }
  }
}
