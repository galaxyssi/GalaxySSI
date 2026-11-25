import SwiftUI

private typealias ChondrocyteLabels = GalaxySSIHealthAtlasChondrocyteGeometry
private typealias ChondrocyteAnchor = GalaxySSIHealthAtlasChondrocyteMotion

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func chondrocyteLabels(_ scaleY: Double) {
    chondrocyteCallout("chondrocyte_story_label_lacuna",74,58,112,99,104,146,ChondrocyteAnchor.mappedY(148,scale: scaleY),down: true)
    chondrocyteCallout("chondrocyte_story_label_chondrocyte",276,58,132,256,96,198,ChondrocyteAnchor.mappedY(158,scale: scaleY),down: true)
    chondrocyteCallout("chondrocyte_story_label_interterritorial",180,29,159,180,82,172,ChondrocyteAnchor.mappedY(108,scale: scaleY),down: true)
    chondrocyteCallout("chondrocyte_story_label_pericellular",89,306,151,105,267,133,ChondrocyteAnchor.mappedY(201,scale: scaleY),down: false)
    chondrocyteCallout("chondrocyte_story_label_territorial",268,306,151,249,269,224,ChondrocyteAnchor.mappedY(215,scale: scaleY),down: false)
    line(22,321,338,321,0xADC4BA,1); line(19,339,32,336,ChondrocyteLabels.collagen,2.5)
    label("chondrocyte_story_label_collagen",84,344,98)
    chondrocyteBrush(142,344,angle: 16,scale: 0.54,color: ChondrocyteLabels.aggrecan); label("chondrocyte_story_label_aggrecan",197,344,80)
    chondrocyteWaterMark(268,340,length: 16,alpha: 255); label("chondrocyte_story_label_water",306,344,51)
  }
  private func chondrocyteCallout(_ key: String, _ x: Double, _ baseline: Double, _ width: Double, _ elbowX: Double, _ elbowY: Double, _ anchorX: Double, _ anchorY: Double, down: Bool) {
    label(key,x,baseline,width)
    let start = baseline + (down ? 6 : -16)
    line(x,start,elbowX,elbowY,ChondrocyteLabels.leader,1.05); line(elbowX,elbowY,anchorX,anchorY,ChondrocyteLabels.leader,1.05)
    disc(anchorX,anchorY,2.2,ChondrocyteLabels.leader,border: Self.cream)
  }
}
