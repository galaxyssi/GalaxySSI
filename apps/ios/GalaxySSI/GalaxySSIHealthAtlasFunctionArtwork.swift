import SwiftUI

enum GalaxySSIHealthAtlasFunctionRendering {
  // Expand only when each source renderer has its own native implementation.
  static let implemented: Set<String> = ["GLUCOSE", "HEARTBEAT", "BREATHING", "HEARING", "NEPHRON", "DIGESTION", "COLON", "VISION", "LIGHT_ADAPTATION", "MUSCLE_MOTION", "BONE_REMODELING", "LYMPH_RETURN", "ANTIBODY_RESPONSE", "INSULIN_SECRETION", "GLUCAGON_RESPONSE", "SWEAT_COOLING", "SYNAPTIC_SIGNAL", "MYELIN_SIGNAL", "THYROID_FEEDBACK", "EPIDERMAL_BARRIER", "SPERM_TRANSPORT", "OVUM_TRANSPORT", "OLFACTION", "TASTE_SIGNAL", "TOUCH_SIGNAL", "VESTIBULAR_BALANCE", "RPE_VISUAL_CYCLE", "DIM_LIGHT_RELAY", "CORNEAL_SURFACE_RENEWAL", "AIRWAY_CLEARANCE", "ENDOTHELIAL_EXCHANGE", "PLATELET_HEMOSTASIS", "CARTILAGE_LOAD", "SMOOTH_MUSCLE_WAVE", "TENDON_FORCE_TRANSFER", "ALVEOLAR_SURFACTANT", "INTESTINAL_ABSORPTION", "KNEE_ARTICULATION", "CARDIAC_EXCITATION", "RED_CELL_OXYGEN", "SALIVA_SECRETION", "VENOUS_RETURN", "HAIR_FOLLICLE_CYCLE", "URINE_ROUTE", "PLEURAL_COUPLING", "PARATHYROID_FEEDBACK", "MAMMARY_MILK_FLOW", "CEREBELLAR_COORDINATION", "MELANIN_TRANSFER", "LARYNGEAL_VOICE", "ASTROCYTE_SUPPORT", "SPLENIC_FILTER", "THYMIC_SELECTION", "BRAINSTEM_RHYTHM", "FIBROBLAST_MATRIX", "ARTERIAL_PULSE", "CHONDROCYTE_MATRIX", "ADRENAL_MEDULLA_SIGNAL", "GASTRIC_ACID_SECRETION", "MARROW_HEMATOPOIESIS", "CORONARY_PERFUSION", "PODOCYTE_BARRIER", "ENDOMETRIUM_RENEWAL", "CRANIAL_REFLEX", "SEBUM_RELEASE", "CEREBRAL_SENSORIMOTOR", "AUTONOMIC_RELAY", "GASTRIC_CHIEF_SECRETION"]
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
    case "ALVEOLAR_SURFACTANT": GalaxySSIHealthAtlasSurfactantView(story: story, phase: phase, language: language)
    case "INTESTINAL_ABSORPTION": GalaxySSIHealthAtlasAbsorptionView(story: story, phase: phase, language: language)
    case "KNEE_ARTICULATION": GalaxySSIHealthAtlasKneeView(story: story, phase: phase, language: language)
    case "CARDIAC_EXCITATION": GalaxySSIHealthAtlasCardiacSignalView(story: story, phase: phase, language: language)
    case "RED_CELL_OXYGEN": GalaxySSIHealthAtlasRedCellView(story: story, phase: phase, language: language)
    case "SALIVA_SECRETION": GalaxySSIHealthAtlasSalivaView(story: story, phase: phase, language: language)
    case "VENOUS_RETURN": GalaxySSIHealthAtlasVenousView(story: story, phase: phase, language: language)
    case "HAIR_FOLLICLE_CYCLE": GalaxySSIHealthAtlasHairView(story: story, phase: phase, language: language)
    case "URINE_ROUTE": GalaxySSIHealthAtlasUrineView(story: story, phase: phase, language: language)
    case "PLEURAL_COUPLING": GalaxySSIHealthAtlasPleuraView(story: story, phase: phase, language: language)
    case "PARATHYROID_FEEDBACK": GalaxySSIHealthAtlasCalciumView(story: story, phase: phase, language: language)
    case "MAMMARY_MILK_FLOW": GalaxySSIHealthAtlasMammaryView(story: story, phase: phase, language: language)
    case "CEREBELLAR_COORDINATION": GalaxySSIHealthAtlasCerebellumView(story: story, phase: phase, language: language)
    case "MELANIN_TRANSFER": GalaxySSIHealthAtlasMelaninView(story: story, phase: phase, language: language)
    case "LARYNGEAL_VOICE": GalaxySSIHealthAtlasLarynxView(story: story, phase: phase, language: language)
    case "ASTROCYTE_SUPPORT": GalaxySSIHealthAtlasAstrocyteView(story: story, phase: phase, language: language)
    case "SPLENIC_FILTER": GalaxySSIHealthAtlasSplenicView(story: story, phase: phase, language: language)
    case "THYMIC_SELECTION": GalaxySSIHealthAtlasThymusView(story: story, phase: phase, language: language)
    case "BRAINSTEM_RHYTHM": GalaxySSIHealthAtlasBrainstemView(story: story, phase: phase, language: language)
    case "FIBROBLAST_MATRIX": GalaxySSIHealthAtlasFibroblastView(story: story, phase: phase, language: language)
    case "ARTERIAL_PULSE": GalaxySSIHealthAtlasArterialView(story: story, phase: phase, language: language)
    case "CHONDROCYTE_MATRIX": GalaxySSIHealthAtlasChondrocyteView(story: story, phase: phase, language: language)
    case "ADRENAL_MEDULLA_SIGNAL": GalaxySSIHealthAtlasAdrenalView(story: story, phase: phase, language: language)
    case "GASTRIC_ACID_SECRETION": GalaxySSIHealthAtlasGastricAcidView(story: story, phase: phase, language: language)
    case "MARROW_HEMATOPOIESIS": GalaxySSIHealthAtlasMarrowView(story: story, phase: phase, language: language)
    case "CORONARY_PERFUSION": GalaxySSIHealthAtlasCoronaryView(story: story, phase: phase, language: language)
    case "PODOCYTE_BARRIER": GalaxySSIHealthAtlasPodocyteStoryView(story: story, phase: phase, language: language)
    case "ENDOMETRIUM_RENEWAL": GalaxySSIHealthAtlasEndometriumView(story: story, phase: phase, language: language)
    case "CRANIAL_REFLEX": GalaxySSIHealthAtlasCranialView(story: story, phase: phase, language: language)
    case "SEBUM_RELEASE": GalaxySSIHealthAtlasSebaceousView(story: story, phase: phase, language: language)
    case "CEREBRAL_SENSORIMOTOR": GalaxySSIHealthAtlasSensorimotorView(story: story, phase: phase, language: language)
    case "AUTONOMIC_RELAY": GalaxySSIHealthAtlasAutonomicView(story: story, phase: phase, language: language)
    case "GASTRIC_CHIEF_SECRETION": GalaxySSIHealthAtlasGastricChiefView(story: story, phase: phase, language: language)
    default: EmptyView()
    }
  }
}
