import SwiftUI

private typealias PodocyteLabels = GalaxySSIHealthAtlasPodocyteGeometry
private typealias PodocyteLabelAnchor = GalaxySSIHealthAtlasPodocyteMotion

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func podocyteLabels() {
    label("podocyte_story_label_blood",300,113,105); podocyteLeader(250,120,230,120)
    label("podocyte_story_label_fenestrated",300,140,105); label("podocyte_story_label_endothelium",300,154,105)
    podocyteLeader(250,151,238,PodocyteLabelAnchor.wallY(238) - 7)
    label("podocyte_story_label_basement",300,173,105); label("podocyte_story_label_membrane",300,187,105)
    podocyteLeader(250,175,238,PodocyteLabelAnchor.wallY(238) + 7)
    label("podocyte_story_label_feet",300,209,105)
    podocyteLeader(250,205,PodocyteLabelAnchor.feet[7],PodocyteLabelAnchor.footY(PodocyteLabelAnchor.feet[7]) + 5)
    label("podocyte_story_label_slit",300,232,105); line(250,228,238,218,PodocyteLabels.leader,1)
    podocyteLeader(238,218,PodocyteLabelAnchor.slits[6],PodocyteLabelAnchor.footY(PodocyteLabelAnchor.slits[6]) + 3.5)
    label("podocyte_story_label_urinary",300,281,105); podocyteLeader(250,277,240,277)
    line(22,306,338,306,0xB8C9C4,1)
    podocyteWater(35,322); label("podocyte_story_label_water",98,327,106)
    podocyteSolute(198,322); label("podocyte_story_label_solutes",274,327,126)
    podocyteRedCell(35,344,tilt: -13); label("podocyte_story_label_cells",98,349,106)
    podocyteProtein(198,344); label("podocyte_story_label_proteins",274,349,126)
  }
  private func podocyteLeader(_ fromX: Double, _ fromY: Double, _ x: Double, _ y: Double) {
    line(fromX,fromY,x,y,PodocyteLabels.leader,1); disc(x,y,1.8,PodocyteLabels.leader,border: Self.cream)
  }
}
