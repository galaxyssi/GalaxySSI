import SwiftUI

enum GalaxySSIHealthAtlasFunctionRendering {
  // Expand only when each source renderer has its own native implementation.
  static let baseline: Set<String> = ["GLUCOSE", "HEARTBEAT", "BREATHING", "HEARING", "NEPHRON", "DIGESTION", "COLON", "VISION", "LIGHT_ADAPTATION", "MUSCLE_MOTION", "BONE_REMODELING", "LYMPH_RETURN", "ANTIBODY_RESPONSE", "INSULIN_SECRETION", "GLUCAGON_RESPONSE", "SWEAT_COOLING", "SYNAPTIC_SIGNAL", "MYELIN_SIGNAL", "THYROID_FEEDBACK", "EPIDERMAL_BARRIER", "SPERM_TRANSPORT", "OVUM_TRANSPORT", "OLFACTION", "TASTE_SIGNAL", "TOUCH_SIGNAL", "VESTIBULAR_BALANCE", "RPE_VISUAL_CYCLE", "DIM_LIGHT_RELAY", "CORNEAL_SURFACE_RENEWAL", "AIRWAY_CLEARANCE", "ENDOTHELIAL_EXCHANGE", "PLATELET_HEMOSTASIS", "CARTILAGE_LOAD", "SMOOTH_MUSCLE_WAVE", "TENDON_FORCE_TRANSFER", "ALVEOLAR_SURFACTANT", "INTESTINAL_ABSORPTION", "KNEE_ARTICULATION", "CARDIAC_EXCITATION", "RED_CELL_OXYGEN", "SALIVA_SECRETION", "VENOUS_RETURN", "HAIR_FOLLICLE_CYCLE", "URINE_ROUTE", "PLEURAL_COUPLING", "PARATHYROID_FEEDBACK", "MAMMARY_MILK_FLOW", "CEREBELLAR_COORDINATION", "MELANIN_TRANSFER", "LARYNGEAL_VOICE", "ASTROCYTE_SUPPORT", "SPLENIC_FILTER", "THYMIC_SELECTION", "BRAINSTEM_RHYTHM", "FIBROBLAST_MATRIX", "ARTERIAL_PULSE", "CHONDROCYTE_MATRIX", "ADRENAL_MEDULLA_SIGNAL", "GASTRIC_ACID_SECRETION", "MARROW_HEMATOPOIESIS", "CORONARY_PERFUSION", "PODOCYTE_BARRIER", "ENDOMETRIUM_RENEWAL", "CRANIAL_REFLEX", "SEBUM_RELEASE", "CEREBRAL_SENSORIMOTOR", "AUTONOMIC_RELAY", "GASTRIC_CHIEF_SECRETION", "TONSILLAR_SAMPLING", "ACINAR_ENZYME_SECRETION", "NAIL_MATRIX_GROWTH", "SINUS_DRAINAGE", "TOOTH_MASTICATION", "MESANGIAL_SUPPORT", "INTERCALATED_BALANCE", "CLUB_CELL_AIRWAY", "PANCREATIC_DUCT_BUFFER", "CHOLANGIOCYTE_BILE", "PINEAL_DARK_SIGNAL", "THORACIC_FRAME", "MICROGLIA_SURVEILLANCE", "EPENDYMAL_FLOW", "DELTOID_LIFT", "SCAPULAR_ROTATION", "GANGLION_RELAY", "LIGAMENT_GUIDANCE", "PLACENTAL_EXCHANGE", "RECTUS_TRUNK_FLEXION", "OBLIQUE_ROTATION", "ERECTOR_SUPPORT", "GLUTEAL_EXTENSION", "GUT_LYMPHOID_SAMPLING", "NEUTROPHIL_DEFENSE", "EOSINOPHIL_RESPONSE", "BASOPHIL_SIGNALING", "MONOCYTE_RECRUITMENT", "DENDRITIC_PRESENTATION", "T_CELL_RESPONSE", "NK_SURVEILLANCE", "PLATELET_FORMATION", "MACROPHAGE_CLEARANCE"]
  static let regional: Set<String> = ["ANKLE_MORTISE", "VULVAR_PROTECTIVE_FOLDS", "ACCESSORY_GLAND_ROUTING",
    "UTEROCERVICAL_CONTINUITY", "PENILE_URINARY_ROUTE", "SCROTAL_HEAT_EXCHANGE", "SKULL_PROTECTION", "VERTEBRAL_MOTION",
    "CLITORAL_SENSORY_PATH", "VESTIBULAR_GLAND_SECRETION", "TENOCYTE_TENDON_MATRIX",
    "PECTORAL_HORIZONTAL_ADDUCTION", "LATISSIMUS_EXTENSION_ADDUCTION"]
  static let loadTransfer: Set<String> = ["PELVIC_LOAD_TRANSFER", "SUBCUTANEOUS_CUSHION"]
  static let crypt: Set<String> = ["PANETH_CRYPT_BARRIER", "ENTEROENDOCRINE_LUMEN_SIGNAL", "INTESTINAL_STEM_RENEWAL"]
  static let renalCells: Set<String> = ["DISTAL_TUBULAR_EXCHANGE", "UROTHELIAL_BARRIER_GEOMETRY"]
  static let isletCells: Set<String> = ["PANCREATIC_DELTA_MODULATION", "PANCREATIC_PP_SIGNAL"]
  static let endocrineZones: Set<String> = ["THYROID_CALCITONIN", "ADRENAL_CORTEX_OUTPUT"]
  static let implemented = baseline.union(regional).union(loadTransfer).union(crypt).union(renalCells).union(isletCells).union(endocrineZones)
}

struct GalaxySSIHealthAtlasFunctionArtwork: View {
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let phase: Double
  let language: String
  @ViewBuilder var body: some View {
    switch story.id {
    case "THYROID_CALCITONIN": GalaxySSIHealthAtlasEndocrineZoneView(story: story, phase: phase, language: language, kind: .calcitonin)
    case "ADRENAL_CORTEX_OUTPUT": GalaxySSIHealthAtlasEndocrineZoneView(story: story, phase: phase, language: language, kind: .cortex)
    case "PANCREATIC_DELTA_MODULATION": GalaxySSIHealthAtlasIsletLessonView(story: story, phase: phase, language: language, kind: .delta)
    case "PANCREATIC_PP_SIGNAL": GalaxySSIHealthAtlasIsletLessonView(story: story, phase: phase, language: language, kind: .pp)
    case "DISTAL_TUBULAR_EXCHANGE": GalaxySSIHealthAtlasRenalCellLessonView(story: story, phase: phase, language: language, kind: .distal)
    case "UROTHELIAL_BARRIER_GEOMETRY": GalaxySSIHealthAtlasRenalCellLessonView(story: story, phase: phase, language: language, kind: .urothelial)
    case "ENTEROENDOCRINE_LUMEN_SIGNAL": GalaxySSIHealthAtlasCryptLessonView(story: story, phase: phase, language: language, kind: .endocrine)
    case "INTESTINAL_STEM_RENEWAL": GalaxySSIHealthAtlasCryptLessonView(story: story, phase: phase, language: language, kind: .stem)
    case "PANETH_CRYPT_BARRIER": GalaxySSIHealthAtlasPanethBarrierView(story: story, phase: phase, language: language)
    case "PELVIC_LOAD_TRANSFER": GalaxySSIHealthAtlasLoadTransferStoryView(story: story, phase: phase, language: language, pelvic: true)
    case "SUBCUTANEOUS_CUSHION": GalaxySSIHealthAtlasLoadTransferStoryView(story: story, phase: phase, language: language, pelvic: false)
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
    case "TONSILLAR_SAMPLING": GalaxySSIHealthAtlasTonsilView(story: story, phase: phase, language: language)
    case "ACINAR_ENZYME_SECRETION": GalaxySSIHealthAtlasAcinarView(story: story, phase: phase, language: language)
    case "NAIL_MATRIX_GROWTH": GalaxySSIHealthAtlasNailView(story: story, phase: phase, language: language)
    case "SINUS_DRAINAGE": GalaxySSIHealthAtlasSinusView(story: story, phase: phase, language: language)
    case "TOOTH_MASTICATION": GalaxySSIHealthAtlasToothView(story: story, phase: phase, language: language)
    case "MESANGIAL_SUPPORT": GalaxySSIHealthAtlasMesangialView(story: story, phase: phase, language: language)
    case "INTERCALATED_BALANCE": GalaxySSIHealthAtlasIntercalatedView(story: story, phase: phase, language: language)
    case "CLUB_CELL_AIRWAY": GalaxySSIHealthAtlasClubView(story: story, phase: phase, language: language)
    case "PANCREATIC_DUCT_BUFFER": GalaxySSIHealthAtlasDuctBufferView(story: story, phase: phase, language: language)
    case "CHOLANGIOCYTE_BILE": GalaxySSIHealthAtlasCholangiocyteView(story: story, phase: phase, language: language)
    case "PINEAL_DARK_SIGNAL": GalaxySSIHealthAtlasPinealView(story: story, phase: phase, language: language)
    case "THORACIC_FRAME": GalaxySSIHealthAtlasThoracicView(story: story, phase: phase, language: language)
    case "MICROGLIA_SURVEILLANCE": GalaxySSIHealthAtlasMicrogliaView(story: story, phase: phase, language: language)
    case "EPENDYMAL_FLOW": GalaxySSIHealthAtlasEpendymalView(story: story, phase: phase, language: language)
    case "DELTOID_LIFT": GalaxySSIHealthAtlasDeltoidView(story: story, phase: phase, language: language)
    case "SCAPULAR_ROTATION": GalaxySSIHealthAtlasScapularView(story: story, phase: phase, language: language)
    case "GANGLION_RELAY": GalaxySSIHealthAtlasGanglionView(story: story, phase: phase, language: language)
    case "LIGAMENT_GUIDANCE": GalaxySSIHealthAtlasLigamentView(story: story, phase: phase, language: language)
    case "PLACENTAL_EXCHANGE": GalaxySSIHealthAtlasPlacentalView(story: story, phase: phase, language: language)
    case "RECTUS_TRUNK_FLEXION": GalaxySSIHealthAtlasRectusView(story: story, phase: phase, language: language)
    case "OBLIQUE_ROTATION": GalaxySSIHealthAtlasObliqueView(story: story, phase: phase, language: language)
    case "ERECTOR_SUPPORT": GalaxySSIHealthAtlasErectorView(story: story, phase: phase, language: language)
    case "GLUTEAL_EXTENSION": GalaxySSIHealthAtlasGlutealView(story: story, phase: phase, language: language)
    case "GUT_LYMPHOID_SAMPLING": GalaxySSIHealthAtlasGutLymphoidView(story: story, phase: phase, language: language)
    case "NEUTROPHIL_DEFENSE", "EOSINOPHIL_RESPONSE", "BASOPHIL_SIGNALING", "MONOCYTE_RECRUITMENT", "DENDRITIC_PRESENTATION", "T_CELL_RESPONSE", "NK_SURVEILLANCE", "PLATELET_FORMATION", "MACROPHAGE_CLEARANCE":
      GalaxySSIHealthAtlasCellFunctionView(story: story, phase: phase, language: language)
    case "ANKLE_MORTISE": GalaxySSIHealthAtlasAnkleView(story: story, phase: phase, language: language)
    case "VULVAR_PROTECTIVE_FOLDS": GalaxySSIHealthAtlasVulvarView(story: story, phase: phase, language: language)
    case "ACCESSORY_GLAND_ROUTING": GalaxySSIHealthAtlasAccessoryGlandView(story: story, phase: phase, language: language)
    case "UTEROCERVICAL_CONTINUITY": GalaxySSIHealthAtlasUterocervicalView(story: story, phase: phase, language: language)
    case "PENILE_URINARY_ROUTE": GalaxySSIHealthAtlasPenileUrinaryView(story: story, phase: phase, language: language)
    case "SCROTAL_HEAT_EXCHANGE": GalaxySSIHealthAtlasScrotalHeatView(story: story, phase: phase, language: language)
    case "SKULL_PROTECTION": GalaxySSIHealthAtlasSkullView(story: story, phase: phase, language: language)
    case "VERTEBRAL_MOTION": GalaxySSIHealthAtlasVertebralView(story: story, phase: phase, language: language)
    case "CLITORAL_SENSORY_PATH": GalaxySSIHealthAtlasClitoralSensoryView(story: story, phase: phase, language: language)
    case "VESTIBULAR_GLAND_SECRETION": GalaxySSIHealthAtlasVestibularGlandView(story: story, phase: phase, language: language)
    case "TENOCYTE_TENDON_MATRIX": GalaxySSIHealthAtlasTenocyteTendonView(story: story, phase: phase, language: language)
    case "PECTORAL_HORIZONTAL_ADDUCTION": GalaxySSIHealthAtlasPectoralView(story: story, phase: phase, language: language)
    case "LATISSIMUS_EXTENSION_ADDUCTION": GalaxySSIHealthAtlasLatissimusView(story: story, phase: phase, language: language)
    default: EmptyView()
    }
  }
}
