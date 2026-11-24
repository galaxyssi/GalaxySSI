import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func sensorimotorStageLabels(_ step: Int) {
    switch step {
    case 1:
      sensorimotorLeader("cerebral_sensorimotor_story_touch", 255, 246, 53, 255, 252, 222, 271)
      sensorimotorLeader("cerebral_sensorimotor_story_position", 63, 246, 94, 97, 249, 116, 258)
    case 2: sensorimotorLeader("cerebral_sensorimotor_story_reach_plan", 244, 246, 88, 244, 250, 246, 254)
    case 3: sensorimotorLeader("cerebral_sensorimotor_story_motor_output", 70, 246, 104, 115, 250, 123, 238)
    case 4: sensorimotorLeader("cerebral_sensorimotor_story_sensory_feedback", 253, 246, 112, 194, 251, 170, 226)
    default: break
    }
  }
  func sensorimotorAnatomyLabels() {
    sensorimotorLeader("cerebral_sensorimotor_story_central_sulcus", 175, 20, 142, 175, 26, 176, 57)
    sensorimotorLeader("cerebral_sensorimotor_story_motor_cortex", 83, 43, 148, 114, 48, 150, 90)
    sensorimotorLeader("cerebral_sensorimotor_story_sensory_cortex", 274, 43, 152, 220, 48, 183, 92)
    sensorimotorLeader("cerebral_sensorimotor_story_premotor", 71, 219, 128, 66, 151, 113, 101)
    sensorimotorLeader("cerebral_sensorimotor_story_parietal", 282, 219, 145, 285, 179, 232, 108)
  }
  func sensorimotorLeader(_ key: String, _ x: Double, _ y: Double, _ width: Double,
    _ kneeX: Double, _ kneeY: Double, _ endX: Double, _ endY: Double) {
    line(x, y + (kneeY >= y ? 4 : -14), kneeX, kneeY, 0x65747B, 0.9)
    line(kneeX, kneeY, endX, endY, 0x65747B, 0.9)
    disc(endX, endY, 1.65, 0x65747B, border: Self.cream)
    label(key, x, y, width)
  }
}
