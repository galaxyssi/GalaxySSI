import SwiftUI

private typealias MarrowCells = GalaxySSIHealthAtlasMarrowGeometry

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func marrowStem(_ x: Double, _ y: Double, radius: Double) {
    var local = context; local.translateBy(x: x, y: y)
    let art = copy(local), r = radius
    art.oval(-r,-r,r,r,top: -27,bottom: 30,from: 0xE4DEF0,to: 0xB498C3,border: MarrowCells.stem)
    art.marrowNucleus(-r * 0.08,0,radius: r * 0.52)
    art.disc(r * 0.68,-r * 0.32,r * 0.09,0xA287B6); art.disc(r * 0.05,r * 0.77,r * 0.065,0xA287B6)
  }
  func marrowNucleus(_ x: Double, _ y: Double, radius: Double) {
    let r = radius
    oval(x - r,y - r * 1.02,x + r,y + r * 1.02,fill: 0x956B9B,border: 0x744D7D)
    disc(x - r * 0.23,y - r * 0.19,r * 0.23,0xC9ACD2)
  }
  func marrowErythroblast(_ x: Double, _ y: Double, radius: Double, nucleus: Double) {
    var local = context; local.translateBy(x: x, y: y)
    let art = copy(local), r = radius
    art.oval(-r,-r,r,r,top: -31,bottom: 30,from: 0xF5D1DF,to: 0xCD8EA5,border: MarrowCells.red)
    art.marrowNucleus(-3,0,radius: nucleus)
  }
  func marrowMegakaryocyte(_ x: Double, _ y: Double) {
    var local = context; local.translateBy(x: x, y: y)
    let art = copy(local)
    art.oval(-34,-31,34,31,top: -30,bottom: 33,from: 0xE7DEED,to: 0xBD99B6,border: MarrowCells.stem)
    art.fill(MarrowCells.megakaryocyteNucleus,0x93688F); art.stroke(MarrowCells.megakaryocyteNucleus,MarrowCells.stem,1.15)
    for i in 0...8 {
      let angle = Double(i) / 9
      art.disc(25 * wave(angle + 0.25),24 * wave(angle),1.6,0xAB81A0)
    }
  }
  func marrowRedCell(_ x: Double, _ y: Double, radius: Double, tilt: Double) {
    var local = context; local.translateBy(x: x, y: y); local.rotate(by: .degrees(tilt))
    let art = copy(local), r = radius
    art.oval(-r,-0.65 * r,r,0.65 * r,fill: 0xD28185,border: MarrowCells.red)
    art.oval(-0.49 * r,-0.23 * r,0.49 * r,0.23 * r,fill: 0xEDB1AC,border: 0xD38588)
  }
  func marrowReticulocyte(_ x: Double, _ y: Double, radius: Double) {
    let r = radius
    oval(x - r,y - 0.8 * r,x + r,y + 0.8 * r,fill: 0xE49AA5,border: MarrowCells.red)
    for i in 0...4 {
      let dx = Double(i - 2) * r * 0.24
      disc(x + dx,y + 0.36 * r * wave(Double(i) * 0.29 + 0.08),r * 0.074,MarrowCells.stem)
    }
  }
}
