import SwiftUI

enum GalaxySSIHealthAtlasFunctionRendering {
  // Expand only when each source renderer has its own native implementation.
  static let implemented: Set<String> = ["GLUCOSE", "HEARTBEAT", "BREATHING", "HEARING", "NEPHRON", "DIGESTION", "COLON", "VISION", "LIGHT_ADAPTATION", "MUSCLE_MOTION", "BONE_REMODELING", "LYMPH_RETURN", "ANTIBODY_RESPONSE", "INSULIN_SECRETION", "GLUCAGON_RESPONSE", "SWEAT_COOLING", "SYNAPTIC_SIGNAL", "MYELIN_SIGNAL", "THYROID_FEEDBACK", "EPIDERMAL_BARRIER", "SPERM_TRANSPORT", "OVUM_TRANSPORT", "OLFACTION", "TASTE_SIGNAL", "TOUCH_SIGNAL", "VESTIBULAR_BALANCE", "RPE_VISUAL_CYCLE", "DIM_LIGHT_RELAY", "CORNEAL_SURFACE_RENEWAL", "AIRWAY_CLEARANCE", "ENDOTHELIAL_EXCHANGE", "PLATELET_HEMOSTASIS", "CARTILAGE_LOAD", "SMOOTH_MUSCLE_WAVE", "TENDON_FORCE_TRANSFER"]
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
    case "INSULIN_SECRETION": GalaxySSIHealthAtlasInsulinView(story: story, phase: phase, language: language)
    case "GLUCAGON_RESPONSE", "SWEAT_COOLING": GalaxySSIHealthAtlasHomeostasisView(story: story, phase: phase, language: language)
    case "SYNAPTIC_SIGNAL", "MYELIN_SIGNAL", "THYROID_FEEDBACK": GalaxySSIHealthAtlasSignalView(story: story, phase: phase, language: language)
    case "EPIDERMAL_BARRIER": GalaxySSIHealthAtlasBarrierView(story: story, phase: phase, language: language)
    case "SPERM_TRANSPORT", "OVUM_TRANSPORT": GalaxySSIHealthAtlasGameteView(story: story, phase: phase, language: language)
    case "OLFACTION", "TASTE_SIGNAL": GalaxySSIHealthAtlasChemicalSenseView(story: story, phase: phase, language: language)
    case "TOUCH_SIGNAL", "VESTIBULAR_BALANCE": GalaxySSIHealthAtlasMotionSenseView(story: story, phase: phase, language: language)
    case "RPE_VISUAL_CYCLE", "DIM_LIGHT_RELAY", "CORNEAL_SURFACE_RENEWAL": GalaxySSIHealthAtlasOcularView(story: story, phase: phase, language: language)
    case "AIRWAY_CLEARANCE": GalaxySSIHealthAtlasAirwayView(story: story, phase: phase, language: language)
    case "ENDOTHELIAL_EXCHANGE": GalaxySSIHealthAtlasEndothelialView(story: story, phase: phase, language: language)
    case "PLATELET_HEMOSTASIS": GalaxySSIHealthAtlasPlateletView(story: story, phase: phase, language: language)
    case "CARTILAGE_LOAD": GalaxySSIHealthAtlasCartilageView(story: story, phase: phase, language: language)
    case "SMOOTH_MUSCLE_WAVE": GalaxySSIHealthAtlasSmoothMuscleView(story: story, phase: phase, language: language)
    case "TENDON_FORCE_TRANSFER": GalaxySSIHealthAtlasTendonView(story: story, phase: phase, language: language)
    default: EmptyView()
    }
  }
}
