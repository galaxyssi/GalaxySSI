import SwiftUI

private typealias AutonomicLabelAnchors = GalaxySSIHealthAtlasAutonomicRoutes

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func autonomicLabels(_ step: Int) {
    switch step {
    case 0:
      autonomicCallout("autonomic_relay_story_art_brainstem", 271, 69, 99, AutonomicLabelAnchors.medullaX, AutonomicLabelAnchors.medullaY)
      autonomicLeader("autonomic_relay_story_art_cord", 48, 116, 90, 88, 119, AutonomicLabelAnchors.spinalX, AutonomicLabelAnchors.spinalY)
      autonomicCallout("autonomic_relay_story_art_heart", 257, 326, 78, 232, 277)
    case 1:
      autonomicCallout("autonomic_relay_story_art_thoracic_ganglion", 75, 91, 141, AutonomicLabelAnchors.thoracicX, AutonomicLabelAnchors.thoracicY)
      autonomicCallout("autonomic_relay_story_art_cord", 278, 124, 106, AutonomicLabelAnchors.spinalX, AutonomicLabelAnchors.spinalY)
      autonomicCallout("autonomic_relay_story_art_cardiac_fiber", 87, 285, 146, 129, 214)
    case 2:
      autonomicCallout("autonomic_relay_story_art_thoracic_ganglion", 174, 25, 146, 83, 39)
      autonomicLeader("autonomic_relay_story_art_sa_node", 50, 171, 85, 82, 165, 139, 140)
      autonomicCallout("autonomic_relay_story_art_heart", 285, 148, 92, 245, 176)
    case 3:
      autonomicCallout("autonomic_relay_story_art_brainstem", 76, 97, 108, AutonomicLabelAnchors.medullaX, AutonomicLabelAnchors.medullaY)
      autonomicLeader("autonomic_relay_story_art_vagus", 295, 140, 116, 252, 135, 227, 135)
      autonomicCallout("autonomic_relay_story_art_cardiac_ganglion", 280, 171, 142, AutonomicLabelAnchors.cardiacX, AutonomicLabelAnchors.cardiacY)
      autonomicCallout("autonomic_relay_story_art_sa_node", 83, 267, 115, AutonomicLabelAnchors.saX, AutonomicLabelAnchors.saY)
    case 4:
      autonomicCallout("autonomic_relay_story_art_thoracic_ganglion", 106, 157, 174, 107, 112)
      autonomicCallout("autonomic_relay_story_art_cardiac_ganglion", 186, 196, 143, 216, 237)
      autonomicCallout("autonomic_relay_story_art_sa_node", 299, 100, 106, 271, 177)
    default: break
    }
  }
  private func autonomicCallout(_ key: String, _ x: Double, _ y: Double, _ width: Double, _ tx: Double, _ ty: Double) {
    autonomicLeader(key, x, y, width, x, ty > y ? y + 5 : y - 14, tx, ty)
  }
  private func autonomicLeader(_ key: String, _ x: Double, _ y: Double, _ width: Double,
    _ ax: Double, _ ay: Double, _ tx: Double, _ ty: Double) {
    line(ax, ay, tx, ty, 0x596F73, 1)
    disc(tx, ty, 1.65, 0x596F73, border: Self.cream)
    label(key, x, y, width)
  }
}
