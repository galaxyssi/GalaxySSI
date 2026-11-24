import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func ganglionSatellite(_ t: Double) {
    let g = GalaxySSIHealthAtlasGanglionGeometry.self
    stroke(g.matrix,0xB5A995,1.3)
    oval(246,151,317,214,top:94,bottom:245,from:0xD7EADD,to:0x91BEB0,border:0x4F8178)
    oval(252,156,311,208,top:126,bottom:226,from:0xF4D5C9,to:0xCD929A,border:0x996A64)
    ganglionNucleus(284,182,8.5)
    ganglionTissue(g.sheathContour,94,245,0xD7EADD,0x91BEB0,0x4F8178)
    stroke(g.gliaBorders,0x4F8178,1.1)
    let contrast = UInt32(Int(215-32*GalaxySSIHealthAtlasGanglionMotion.satellite(t)))
    let space: UInt32 = 0xFFFFE700 | contrast
    oval(106,105,223,230,fill:space,border:0x4F8178)
    oval(112,111,217,224,top:111,bottom:228,from:0xFFEDDA,to:0xE2AC9D,border:0x996A64)
    ganglionNucleus(161,162,18.5)
    oval(162,94,178,102,fill:0x4F8178,border:0x577A72)
    oval(224,153,233,168,fill:0x4F8178,border:0x577A72)
    oval(148,232,166,241,fill:0x4F8178,border:0x577A72)
    oval(95,176,103,189,fill:0x4F8178,border:0x577A72)
  }
}
