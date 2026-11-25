import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func ganglionTissue(_ p: Path, _ top: Double, _ bottom: Double, _ from: UInt32, _ to: UInt32, _ edge: UInt32) {
    gradient(p,top,bottom,from,to); stroke(p,edge,1.45)
  }
  func ganglionFiber(_ p: Path, _ color: UInt32, _ width: Double) {
    stroke(p,Self.cream,width+3.1); stroke(p,color,width)
  }
  func ganglionQuietSoma(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double) {
    oval(x-rx,y-ry,x+rx,y+ry,fill:0xEFD4BD,border:0xBF9B85)
    disc(x-1,y-1,ry*0.27,0xC299A0)
  }
  func ganglionNucleus(_ x: Double, _ y: Double, _ radius: Double) {
    disc(x,y,radius,0xCF9EAD,border:0x956277)
    disc(x-radius*0.2,y-radius*0.2,radius*0.27,0x956277)
  }
}
