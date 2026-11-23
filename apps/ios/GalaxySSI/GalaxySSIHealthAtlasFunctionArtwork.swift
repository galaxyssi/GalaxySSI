import SwiftUI

enum GalaxySSIHealthAtlasFunctionRendering {
  // Expand only when each source renderer has its own native implementation.
  static let implemented: Set<String> = ["GLUCOSE", "HEARTBEAT", "BREATHING", "HEARING", "NEPHRON", "DIGESTION", "COLON", "VISION", "LIGHT_ADAPTATION", "MUSCLE_MOTION", "BONE_REMODELING", "LYMPH_RETURN", "ANTIBODY_RESPONSE"]
}

struct GalaxySSIHealthAtlasFunctionArtwork: View {
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let phase: Double
  let language: String
  @ViewBuilder var body: some View {
    switch story.id {
    case "GLUCOSE": GalaxySSIHealthAtlasUptakeView(story: story, phase: phase, language: language)
    case "HEARTBEAT": GalaxySSIHealthAtlasHeartbeatView(story: story, phase: phase, language: language)
    case "BREATHING": GalaxySSIHealthAtlasBreathingView(story: story, phase: phase, language: language)
    case "HEARING": GalaxySSIHealthAtlasHearingView(story: story, phase: phase, language: language)
    case "NEPHRON": GalaxySSIHealthAtlasNephronView(story: story, phase: phase, language: language)
    case "DIGESTION", "COLON": GalaxySSIHealthAtlasDigestionView(story: story, phase: phase, language: language)
    case "VISION", "LIGHT_ADAPTATION": GalaxySSIHealthAtlasVisionView(story: story, phase: phase, language: language)
    case "MUSCLE_MOTION", "BONE_REMODELING": GalaxySSIHealthAtlasMovementView(story: story, phase: phase, language: language)
    case "LYMPH_RETURN", "ANTIBODY_RESPONSE": GalaxySSIHealthAtlasLymphImmuneView(story: story, phase: phase, language: language)
    default: EmptyView()
    }
  }
}
