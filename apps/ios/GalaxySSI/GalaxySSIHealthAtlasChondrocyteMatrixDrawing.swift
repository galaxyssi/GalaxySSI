import SwiftUI

private typealias ChondrocyteMatrix = GalaxySSIHealthAtlasChondrocyteGeometry

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func chondrocyteMatrix(_ frame: GalaxySSIHealthAtlasChondrocyteMotion) {
    var shadow = context; shadow.translateBy(x: 0, y: 4); copy(shadow).fill(ChondrocyteMatrix.patch,0x1A386E65)
    gradient(ChondrocyteMatrix.patch,84,263,0xE5F2E8,0xBAD9D3); stroke(ChondrocyteMatrix.patch,ChondrocyteMatrix.tissueEdge,1.5)
    var clipped = context; clipped.clip(to: ChondrocyteMatrix.patch)
    let art = copy(clipped)
    art.gradient(ChondrocyteMatrix.territory,113,244,0xCDE8DE,0x9FC7BE); art.stroke(ChondrocyteMatrix.territory,0x93BDB1,1.2)
    let extent = 10 + 15 * frame.hydration, wash = art.chondrocyteAlpha(frame.washAlpha)
    wash.fill(Path(ellipseIn: CGRect(x: 77 - extent, y: 132, width: 16 + 2 * extent, height: 39)),0x79C8DA)
    wash.fill(Path(ellipseIn: CGRect(x: 245 - extent, y: 162, width: 50 + 2 * extent, height: 61)),0x79C8DA)
    for side in [-1.0,1] {
      for i in 0...4 {
        let water = frame.water(index: i,side: side)
        art.chondrocyteWaterMark(water.x,water.y,length: water.length,alpha: water.alpha)
      }
    }
    for (index, route) in ChondrocyteMatrix.fibrils.enumerated() {
      let path = ChondrocyteMatrix.path(route)
      art.stroke(path,0xB1F9F2E7,3.1); art.stroke(path,ChondrocyteMatrix.fibril,index % 3 == 0 ? 1.45 : 1)
    }
    art.chondrocyteBrush(77,151,angle: -32,scale: 0.72,color: 0x997F58)
    art.chondrocyteBrush(98,224,angle: 36,scale: 0.61,color: 0x997F58)
    art.chondrocyteBrush(267,144,angle: 48,scale: 0.75,color: 0x997F58)
    art.chondrocyteBrush(193,242,angle: -31,scale: 0.68,color: 0x997F58)
    for neighbor in ChondrocyteMatrix.neighbors {
      art.fill(neighbor.rim,0xB3D3C9); art.stroke(neighbor.rim,0x8DB1AA,1.05); art.fill(neighbor.cell,0xD6B8C9)
      art.oval(neighbor.x - 6,neighbor.y - 3,neighbor.x + 3,neighbor.y + 4,fill: 0x9B7D9A,border: 0x8F708C)
    }
    gradient(ChondrocyteMatrix.rim,131,225,0xAED6C9,0x81B5AC); stroke(ChondrocyteMatrix.rim,ChondrocyteMatrix.rimEdge,1.4)
    fill(ChondrocyteMatrix.lacuna,0xE7EEE3); stroke(ChondrocyteMatrix.lacuna,0x739C91,1.15)
  }
  func chondrocyteCell() {
    gradient(ChondrocyteMatrix.cell,141,208,0xFFEEE1,0xDCACC2); stroke(ChondrocyteMatrix.cell,ChondrocyteMatrix.cellEdge,1.65)
    oval(147,158,179,190,fill: 0xB08BAD,border: 0x825C85); oval(153,161,174,184,fill: 0xBD9AB8,border: 0xB08BAD)
    disc(166,175,4,0x8E668D); stroke(ChondrocyteMatrix.reticulum,0xFAF1EE,3.3)
    stroke(ChondrocyteMatrix.reticulum,0xBD8DA8,1.45); stroke(ChondrocyteMatrix.golgi,0xA16B83,1.8)
  }
}
