import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func pinealLabels(_ step: Int, _ t: Double) {
    let zoom = GalaxySSIHealthAtlasPinealMotion.zoom(t), size = 0.91+0.57*zoom
    let x = 242-32*zoom-249*size, y = 180-146*size
    let ventricleX = x+138*size, ventricleY = y+140*size, pinealX = x+249*size
    switch step {
    case 0:
      label("pineal_story_label_anterior", 65, 33, 91)
      label("pineal_story_label_posterior", 295, 33, 91)
      pinealLeader("pineal_plate_third_ventricle", 86, 328, 131, 299, ventricleX, ventricleY)
      pinealLeader("pineal_plate_body", 266, 328, 117, 299, pinealX, 180)
    case 1:
      pinealLeader("pineal_story_label_light", 42, 68, 64, 78, 41, 89, true)
      pinealLeader("pineal_story_label_retina", 97, 286, 106, 255, 117, 196)
      pinealLeader("pineal_story_label_scn", 249, 286, 130, 252, 221, 184)
    case 2:
      label("pineal_story_label_night", 295, 174, 100)
      pinealLeader("pineal_story_label_pvn", 84, 42, 149, 55, 152, 90, true)
      pinealLeader("pineal_story_label_scn", 61, 91, 104, 101, 147, 105, true)
      pinealLeader("pineal_plate_body", 282, 65, 118, 78, 197, 98, true)
      pinealLeader("pineal_story_label_scg", 81, 210, 142, 192, 145, 167)
      pinealLeader("pineal_story_label_spinal", 269, 309, 147, 286, 187, 232)
    case 3:
      pinealLeader("pineal_story_label_norepinephrine", 96, 67, 124, 91, 77, 144, true)
      pinealLeader("pineal_story_label_pinealocyte", 250, 77, 128, 99, 211, 132, true)
      label("pineal_story_label_aanat", 134, 188, 48)
      label("pineal_story_label_asmt", 184, 188, 48)
      pinealLeader("pineal_story_label_serotonin", 62, 315, 84, 289, 108, 211)
      pinealLeader("pineal_story_label_intermediate", 171, 315, 124, 289, 159, 211)
      pinealLeader("pineal_story_label_melatonin", 278, 315, 82, 291, 210, 211)
      pinealLeader("pineal_story_label_capillary", 317, 126, 80, 153, 320, 224, true)
    case 4:
      label("pineal_story_label_relative", 180, 40, 275)
      label("pineal_story_label_day", 76, 106, 76)
      label("pineal_story_label_night", 184, 106, 102)
      label("pineal_story_label_day", 288, 106, 67)
    default: break
    }
  }
  private func pinealLeader(_ key: String, _ x: Double, _ baseline: Double, _ width: Double,
    _ elbowY: Double, _ tx: Double, _ ty: Double, _ pointsDown: Bool = false) {
    line(x, baseline+(pointsDown ? 5 : -13), x, elbowY, 0x55727D, 1.1)
    line(x, elbowY, tx, ty, 0x55727D, 1.1)
    disc(tx, ty, 1.8, 0x55727D)
    label(key, x, baseline, width)
  }
}
