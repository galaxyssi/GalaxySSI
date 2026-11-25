import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func placentalOrientLabels() {
    placentalLeader("placental_exchange_story_cord",226, 42, 135, 226, 57, 202.2, 83.2, true)
    placentalLeader("placental_exchange_story_chorionic_plate",84, 111, 147, 84, 124, 109, 142, true)
    placentalLeader("placental_exchange_story_basal_plate",92, 318, 144, 92, 289, 161, 265)
    placentalLeader("placental_exchange_story_terminal_villus",272, 318, 148, 272, 284, 210.2, 202.4)
  }
  func placentalAnatomyLabels() {
    placentalLeader("placental_exchange_story_intervillous",84, 80, 146, 84, 103, 55, 119, true)
    placentalLeader("placental_exchange_story_capillary",281, 80, 140, 281, 103, 267, 139, true)
    placentalLeader("placental_exchange_story_syncytium",98, 305, 153, 98, 281, 150, 225)
    placentalLeader("placental_exchange_story_endothelium",254, 305, 164, 254, 281, 204, 241)
  }
  func placentalRouteKey() {
    for y in [326.0,346] { disc(19,y-4,2.5,0xA66070); disc(178,y-4,2.5,0x3E7582) }
    label("placental_exchange_story_maternal_in",97,326,135)
    label("placental_exchange_story_maternal_out",97,346,135)
    label("placental_exchange_story_fetal_in",265,326,155)
    label("placental_exchange_story_fetal_out",265,346,155)
  }
  private func placentalLeader(_ key: String, _ x: Double, _ baseline: Double, _ width: Double,
    _ elbowX: Double, _ elbowY: Double, _ tx: Double, _ ty: Double, _ below: Bool = false) {
    line(x,baseline+(below ? 5 : -15),elbowX,elbowY,0x506369,1.05)
    line(elbowX,elbowY,tx,ty,0x506369,1.05); disc(tx,ty,1.8,0x506369)
    label(key,x,baseline,width)
  }
}
