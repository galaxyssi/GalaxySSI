import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func clubLabels(_ step: Int) {
    switch step {
    case 0:
      clubLeader("club_cell_story_lumen", 70, 66, 111, 91, 122, 166, belowText: true)
      clubLeader("club_cell_story_bronchiole", 260, 34, 153, 57, 264, 77, belowText: true)
      clubLeader("club_cell_story_club", 130, 323, 99, 289, 150, 236)
      clubLeader("club_cell_story_muscle", 275, 299, 133, 276, 230, 223)
    case 1:
      clubLeader("club_cell_story_dome", 176, 75, 121, 104, 176, 149, belowText: true)
      clubLeader("club_cell_story_cilia", 64, 130, 86, 155, 77, 178, belowText: true)
      clubLeader("club_cell_story_granule", 277, 111, 135, 138, 199, 184, belowText: true)
      clubLeader("club_cell_story_club", 176, 317, 117, 287, 176, 222)
      clubLeader("club_cell_story_ciliated", 277, 317, 113, 287, 279, 219)
    case 2:
      clubLeader("club_cell_story_surface", 86, 90, 151, 117, 154, 159, belowText: true)
      clubLeader("club_cell_story_fluid", 266, 90, 131, 119, 226, 168, belowText: true)
      clubLeader("club_cell_story_club", 176, 317, 117, 287, 176, 222)
    case 3:
      clubLeader("club_cell_story_protein", 153, 72, 163, 103, 176, 141, belowText: true)
      clubLeader("club_cell_story_fluid", 276, 126, 123, 151, 282, 176, belowText: true)
      clubLeader("club_cell_story_epithelium", 177, 317, 159, 295, 213, 237)
    case 4:
      label("club_cell_story_mouse", 180, 93, 206)
      clubLeader("club_cell_story_club", 107, 317, 113, 287, 125, 211)
      clubLeader("club_cell_story_new_ciliated", 252, 317, 170, 287, 203, 224)
    default: break
    }
  }
  private func clubLeader(_ key: String, _ x: Double, _ baseline: Double, _ width: Double,
    _ elbowY: Double, _ targetX: Double, _ targetY: Double, belowText: Bool = false) {
    let startY = baseline + (belowText ? 5 : -11)
    line(x, startY, x, elbowY, 0x506469, 1.05)
    line(x, elbowY, targetX, targetY, 0x506469, 1.05)
    disc(targetX, targetY, 2, 0x506469)
    label(key, x, baseline, width)
  }
}
