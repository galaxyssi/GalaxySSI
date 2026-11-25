import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func gutLymphoidLocateLabels() {
    label("gut_lymphoid_story_cecum",50,95,83)
    gutLymphoidLeader(50,102,55,132,109,155)
    label("gut_lymphoid_story_ileum",269,89,145)
    gutLymphoidLeader(269,96,274,116,261,147)
    label("gut_lymphoid_story_appendix",232,307,146)
    gutLymphoidLeader(232,294,205,270,151,267)
  }
  func gutLymphoidCompareLabels(_ left: Double, _ right: Double) {
    label("gut_lymphoid_story_appendix_wall",93,84,154)
    label("gut_lymphoid_story_ileal_wall",265,84,162)
    label("gut_lymphoid_story_appendix_lumen",92,111,145)
    gutLymphoidLeader(92,118,92,128,92,183 + (185 - 183) * left)
    label("gut_lymphoid_story_villi",293,111,114)
    gutLymphoidLeader(293,118,305,128,266 + (308 - 266) * right,183 + (154 - 183) * right)
    label("gut_lymphoid_story_follicles",91,295,152)
    gutLymphoidLeader(91,281,85,261,92 + (69 - 92) * left,183 + (217 - 183) * left)
    label("gut_lymphoid_story_peyer",265,295,159)
    gutLymphoidLeader(265,281,265,263,266 + (266 - 266) * right,183 + (206 - 183) * right)
  }
  func gutLymphoidSamplingLabels() {
    label("gut_lymphoid_story_food_protein",104,64,104)
    label("gut_lymphoid_story_dendritic",158,338,155)
    gutLymphoidLeader(158,324,157,281,161,233)
  }
  func gutLymphoidRecognitionLabels(_ tx: Double, _ ty: Double) {
    label("gut_lymphoid_story_dendritic",104,338,145)
    gutLymphoidLeader(104,324,104,284,154,236)
    label("gut_lymphoid_story_t_cell",262,338,114)
    gutLymphoidLeader(262,324,261,296,tx + 4,ty + 15)
  }
  func gutLymphoidDefenseLabels() {
    label("gut_lymphoid_story_secretory_iga",260,67,166)
    gutLymphoidLeader(260,75,274,87,282,102)
    label("gut_lymphoid_story_epithelial_transport",258,217,144)
    gutLymphoidLeader(258,203,246,184,214,150)
    label("gut_lymphoid_story_plasma_cell",112,336,155)
    gutLymphoidLeader(112,322,113,296,109,260)
  }
  func gutLymphoidMCellLabels() {
    label("gut_lymphoid_story_m_cell",259,91,113)
    gutLymphoidLeader(247,97,215,105,181,142)
  }
  private func gutLymphoidLeader(_ x: Double, _ y: Double, _ bx: Double, _ by: Double, _ tx: Double, _ ty: Double) {
    line(x,y,bx,by,0x526E75,1.05); line(bx,by,tx,ty,0x526E75,1.05)
    disc(tx,ty,1.8,0x526E75,border:Self.cream)
  }
}
