import SwiftUI

private typealias ThymusFlow = GalaxySSIHealthAtlasThymusMotion
private typealias ThymusSelection = GalaxySSIHealthAtlasThymusShapes

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func thymusDynamics(step: Int, t: Double) {
    switch step {
    case 0:
      thymusTravel(ThymusFlow.enter,t: t,color: ThymusSelection.early,radius: 8)
      thymusCellLabel(180,color: ThymusSelection.early,key: "thymus_story_precursor",width: 115)
    case 1: thymusPositive(t)
    case 2:
      thymusTravel(ThymusFlow.migrate,t: t,color: ThymusSelection.selected,radius: 8)
      thymusCellLabel(180,color: ThymusSelection.selected,key: "thymus_story_selected_cell",width: 115)
    case 3: thymusNegative(t)
    default:
      thymusTravel(ThymusFlow.leave,t: t,color: ThymusSelection.selected,radius: 9.5)
      thymusCellLabel(180,color: ThymusSelection.selected,key: "thymus_story_naive_cell",width: 135)
    }
  }
  private func thymusPositive(_ t: Double) {
    thymusPresenter(180,117,edge: ThymusSelection.capsuleEdge,fill: 0xEDBDCB)
    let frame = ThymusFlow.positive(t)
    if frame.signal > 0 {
      let circle = Path(ellipseIn: CGRect(x: 158 - 4 - 8 * frame.signal, y: 117 - 4 - 8 * frame.signal,
        width: 2 * (4 + 8 * frame.signal), height: 2 * (4 + 8 * frame.signal)))
      thymusAlpha(Int(200 * (1 - frame.signal))).stroke(circle,0xF9F0C7,2)
    }
    rounded(155,114,162,120,2,Self.sienna)
    thymusCell(frame.x,frame.y,radius: 8.5,color: frame.selected ? ThymusSelection.selected : ThymusSelection.early)
    label("thymus_story_self_mhc",223,126,84); thymusLeader(208,111,184,96,160,113)
    label("thymus_story_cortical_epithelium",233,146,144); thymusLeader(196,134,188,129,183,123)
  }
  private func thymusNegative(_ t: Double) {
    thymusPresenter(221,197,edge: ThymusSelection.medullaEdge,fill: 0xF4BD9D)
    let frame = ThymusFlow.negative(t)
    if frame.removal < 1 {
      thymusCell(frame.x,frame.y,radius: frame.radius,color: ThymusSelection.reactive,alpha: frame.alpha)
      if frame.removal > 0 {
        let art = thymusAlpha(frame.debrisAlpha)
        art.disc(frame.x - 4 - 5 * frame.removal,frame.y - 4,1.65,ThymusSelection.reactive)
        art.disc(frame.x + 3,frame.y + 4 + 6 * frame.removal,1.25,ThymusSelection.reactive)
      }
    }
    thymusCell(166 + 44 * t,220 + 8 * wave(t * 0.5),radius: 8,color: ThymusSelection.selected)
    thymusCellLabel(82,color: ThymusSelection.reactive,key: "thymus_story_self_reactive_cell",width: 125)
    thymusCellLabel(255,color: ThymusSelection.selected,key: "thymus_story_maturing_cell",width: 137)
  }
}
