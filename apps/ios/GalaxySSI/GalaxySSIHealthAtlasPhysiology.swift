import Foundation

/// Android #4388 synthetic load examples, never patient measurements or predictions.
enum GalaxySSIHealthAtlasLoadTransfer {
  static let pelvicSource = URL(string: "https://openstax.org/books/anatomy-and-physiology-2e/pages/8-3-the-pelvic-girdle-and-pelvis")!
  static let subcutaneousSource = URL(string: "https://openstax.org/books/anatomy-and-physiology-2e/pages/5-1-layers-of-the-skin")!
  static let stabilitySource = URL(string: "https://openstax.org/books/college-physics-2e/pages/9-3-stability")!
  static let pressureSource = URL(string: "https://openstax.org/books/college-physics-2e/pages/11-3-pressure")!

  struct PelvicSupport: Equatable, Sendable {
    let loadNewtons: Double
    let positionPercent: Double
    init?(loadNewtons: Double, positionPercent: Double) {
      guard loadNewtons.isFinite, (0...800).contains(loadNewtons),
        positionPercent.isFinite, (-100...100).contains(positionPercent) else { return nil }
      self.loadNewtons = loadNewtons; self.positionPercent = positionPercent
    }
    var rightNewtons: Double { loadNewtons * (100 + positionPercent) / 200 }
    var leftNewtons: Double { loadNewtons * (100 - positionPercent) / 200 }
    static let initial = Self(loadNewtons: 400, positionPercent: 0)!
  }

  struct CushionContact: Equatable, Sendable {
    let loadNewtons: Double
    let areaSquareCentimetres: Double
    init?(loadNewtons: Double, areaSquareCentimetres: Double) {
      guard loadNewtons.isFinite, (0...80).contains(loadNewtons),
        areaSquareCentimetres.isFinite, (10...90).contains(areaSquareCentimetres) else { return nil }
      self.loadNewtons = loadNewtons; self.areaSquareCentimetres = areaSquareCentimetres
    }
    // One N/cm^2 equals ten kPa; the reference keeps the example area at 40 cm^2.
    var pressureKilopascals: Double { 10 * loadNewtons / areaSquareCentimetres }
    var referenceKilopascals: Double { 10 * loadNewtons / 40 }
    static let initial = Self(loadNewtons: 40, areaSquareCentimetres: 40)!
  }
}

/// Steady-state solute transfers only, not urine volume or a patient clearance estimate.
struct GalaxySSIHealthAtlasRenalAmounts: Equatable, Sendable {
  let filtered: Double
  let reabsorbed: Double
  let secreted: Double
  var excreted: Double { filtered - reabsorbed + secreted }
  init?(filtered: Double, reabsorbedPercent: Double, secreted: Double) {
    guard filtered.isFinite, filtered >= 0, reabsorbedPercent.isFinite, (0...100).contains(reabsorbedPercent),
      secreted.isFinite, secreted >= 0 else { return nil }
    let recovered = filtered * (reabsorbedPercent / 100)
    guard (filtered - recovered + secreted).isFinite else { return nil }
    self.filtered = filtered; self.reabsorbed = recovered; self.secreted = secreted
  }
  var transfers: [Double] { [filtered, reabsorbed, secreted, excreted] }
}

/// Synthetic teaching inputs only. This model has no archive, observation, file or transport dependency.
struct GalaxySSIHealthAtlasPhysiology: Equatable, Sendable {
  struct Input: Equatable, Sendable {
    let key: String
    let range: ClosedRange<Int>
    let initial: Int
    var scale: Double = 1
    let unit: String
  }
  enum Kind: String, CaseIterable, Sendable {
    case ventilation, renal, potassium, elbow, vessel, eye
    case middleEar
    case nerveTransit
    case lymphValve
    case alveolarDiffusion, cartilageCompression, boneBending, calfPump
    case villusArea
    case pelvicSupport, cushionContactPressure
    case capillaryExchange, valveFlux, glomerularFiltration, skinWaterBarrier, salivaryDelivery
    case tendonElongation, airwaySplit, peristalticTravel, cochlearFrequency
    case diaphragmDisplacement, cardiacPhaseTime, visualAngle, serialAbsorption, hormoneSignal
    case immuneComposition, ductTransit, oviductCiliaryCycles, kneeMoment
    case arterialContinuity, glialCapacitance, colonicWaterBalance, lymphParticleTransport, endocrineDilution
    case boneSection, retinalConvergence, muscleShortening, keratinGrowth
    case bladderExpansion, vestibularTilt, airwayCiliaryClearance, gastricLiquidEmptying, bileStorage
    case thoracicCrossSection, plateletFragmentCount, boneRemodelingBalance, cutaneousSebum
    case ureterDelivery, cornealRefraction, externalEarResonance, neuralRelayDelays, biliaryFlowTally
    case parathyroidSignalOccupancy, follicleSurface, jointArticularArc, sweatDuctBalance
    case vocalCycles, vertebralSeries, oralMarkerDilution, olfactorySurfaceRetention, circadianLightWindow
    case adiposeVolumeShare, thymicBranching, gastricPrecursorBalance, melaninDistribution
    case placentalMarker, renalTubuleRetention, merkelContact, toothEnamelSection, mucosalSampling
    case mammaryDuctDelivery, rectalReservoir, stromalMatrix, mucusFilmThickness
    case sweatEvaporation
    case photonCapture
    case thyroidFeedback
    case alveolarSurface
    case bicarbonateMix
    case ejection
    #if GALAXYSSI_ATLAS_OXYGEN
    case oxygen
    #endif
    var teaching: GalaxySSIHealthAtlasTeachingModel? { .init(rawValue: rawValue) }
    var inputs: [Input] {
      switch self {
      case .capillaryExchange, .valveFlux, .glomerularFiltration, .skinWaterBarrier, .salivaryDelivery,
           .tendonElongation, .airwaySplit, .peristalticTravel, .cochlearFrequency,
           .diaphragmDisplacement, .cardiacPhaseTime, .visualAngle, .serialAbsorption, .hormoneSignal,
           .immuneComposition, .ductTransit, .oviductCiliaryCycles, .kneeMoment,
           .arterialContinuity, .glialCapacitance, .colonicWaterBalance, .lymphParticleTransport, .endocrineDilution,
           .boneSection, .retinalConvergence, .muscleShortening, .keratinGrowth,
           .bladderExpansion, .vestibularTilt, .airwayCiliaryClearance, .gastricLiquidEmptying, .bileStorage,
           .thoracicCrossSection, .plateletFragmentCount, .boneRemodelingBalance, .cutaneousSebum,
           .ureterDelivery, .cornealRefraction, .externalEarResonance, .neuralRelayDelays, .biliaryFlowTally,
           .parathyroidSignalOccupancy, .follicleSurface, .jointArticularArc, .sweatDuctBalance,
           .vocalCycles, .vertebralSeries, .oralMarkerDilution, .olfactorySurfaceRetention, .circadianLightWindow,
           .adiposeVolumeShare, .thymicBranching, .gastricPrecursorBalance, .melaninDistribution,
           .placentalMarker, .renalTubuleRetention, .merkelContact, .toothEnamelSection, .mucosalSampling,
           .mammaryDuctDelivery, .rectalReservoir, .stromalMatrix, .mucusFilmThickness:
        return teaching!.inputs
      case .pelvicSupport:
        return [.init(key: "pelvis_model_load", range: 0...800, initial: 400, unit: "N"),
          .init(key: "pelvis_model_position", range: -100...100, initial: 0, unit: "%")]
      case .cushionContactPressure:
        return [.init(key: "cushion_model_load", range: 0...80, initial: 40, unit: "N"),
          .init(key: "cushion_model_area", range: 10...90, initial: 40, unit: "cm\u{00b2}")]
      case .calfPump:
        return [.init(key: "calf_pump_stroke", range: 0...25, initial: 12, unit: "mL"),
          .init(key: "calf_pump_rate", range: 0...30, initial: 12, unit: "/min"),
          .init(key: "calf_pump_return", range: 0...100, initial: 0, unit: "%")]
      case .alveolarDiffusion:
        return [.init(key: "diffusion_gradient", range: 0...200, initial: 100, scale: 100, unit: "\u{00d7}"),
          .init(key: "diffusion_area", range: 50...200, initial: 100, scale: 100, unit: "\u{00d7}"),
          .init(key: "diffusion_thickness", range: 50...200, initial: 100, scale: 100, unit: "\u{00d7}")]
      case .cartilageCompression:
        return [.init(key: "compression_stress", range: 0...64, initial: 32, unit: "kPa"),
          .init(key: "compression_modulus", range: 80...240, initial: 160, scale: 100, unit: "MPa")]
      case .boneBending:
        return [.init(key: "bone_bending_moment", range: 0...12, initial: 6, unit: "N\u{00b7}m"),
          .init(key: "bone_bending_diameter", range: 20...40, initial: 30, unit: "mm"),
          .init(key: "bone_bending_cavity", range: 30...80, initial: 60, scale: 100, unit: "")]
      case .villusArea:
        return [.init(key: "gut_section_area_density", range: 0...24, initial: 12, unit: "/mm\u{00b2}"),
          .init(key: "gut_section_area_radius", range: 25...70, initial: 45, scale: 1000, unit: "mm"),
          .init(key: "gut_section_area_height", range: 20...120, initial: 60, scale: 100, unit: "mm")]
      case .lymphValve:
        return [.init(key: "lymph_valve_pressure", range: -40...40, initial: 20, scale: 10, unit: "mmHg"),
          .init(key: "lymph_valve_resistance", range: 20...200, initial: 40, scale: 10, unit: "mmHg\u{00b7}min/mL")]
      case .sweatEvaporation:
        return [.init(key: "context_evap_rate", range: 0...200, initial: 60, scale: 10, unit: "g/min"),
          .init(key: "context_evap_fraction", range: 0...100, initial: 50, unit: "%")]
      case .photonCapture:
        return [.init(key: "sensory_photon_mean", range: 0...500, initial: 100, scale: 100, unit: "")]
      case .thyroidFeedback:
        return [.init(key: "endocrine_feedback_drive", range: 20...100, initial: 80, unit: "%"),
          .init(key: "endocrine_feedback_gain", range: 0...300, initial: 100, scale: 100, unit: "\u{00d7}")]
      case .alveolarSurface:
        return [.init(key: "alveolar_tension", range: 5...35, initial: 15, unit: "mN/m"),
          .init(key: "alveolar_radius", range: 50...200, initial: 100, unit: "\u{03bc}m")]
      case .bicarbonateMix:
        return [.init(key: "digestive_bicarb_flow", range: 0...40, initial: 10, scale: 10, unit: "mL/min"),
          .init(key: "digestive_bicarb_concentration", range: 20...120, initial: 80, unit: "mmol/L")]
      case .nerveTransit:
        return [.init(key: "nerve_transit_distance", range: 10...150, initial: 60, unit: "cm"),
          .init(key: "nerve_transit_speed", range: 1...120, initial: 50, unit: "m/s")]
      case .ejection:
        return [.init(key: "ejection_stroke_volume", range: 0...180, initial: 70, unit: "mL"),
          .init(key: "ejection_residual_volume", range: 5...180, initial: 60, unit: "mL")]
      case .eye:
        return [.init(key: "eye_object_distance", range: 25...600, initial: 100, scale: 100, unit: "m"),
          .init(key: "eye_power", range: 5500...6500, initial: 5982, scale: 100, unit: "D")]
      case .vessel:
        return [.init(key: "vessel_pressure", range: 0...20, initial: 10, unit: "mmHg"),
          .init(key: "vessel_radius", range: 50...200, initial: 100, scale: 1000, unit: "mm"),
          .init(key: "vessel_length", range: 20...100, initial: 50, unit: "mm"),
          .init(key: "vessel_viscosity", range: 20...60, initial: 35, scale: 10, unit: "mPa s")]
      case .elbow:
        return [.init(key: "elbow_load", range: 0...100, initial: 40, scale: 10, unit: "kg"),
          .init(key: "elbow_load_arm", range: 20...50, initial: 38, unit: "cm"),
          .init(key: "elbow_muscle_arm", range: 20...60, initial: 40, unit: "mm")]
      case .ventilation:
        return [.init(key: "rate", range: 6...30, initial: 12, unit: "/min"),
          .init(key: "tidal", range: 200...900, initial: 500, unit: "mL"),
          .init(key: "model_dead_space", range: 0...200, initial: 150, unit: "mL")]
      case .renal:
        return [.init(key: "model_filtered", range: 0...200, initial: 100, unit: "mg/min"),
          .init(key: "model_reabsorbed", range: 0...100, initial: 90, unit: "%"),
          .init(key: "model_secreted", range: 0...100, initial: 10, unit: "mg/min")]
      case .middleEar:
        return [.init(key: "middle_ear_input_area", range: 35...75, initial: 55, unit: "mm\u{00b2}"),
          .init(key: "middle_ear_output_area", range: 20...50, initial: 32, scale: 10, unit: "mm\u{00b2}"),
          .init(key: "middle_ear_lever_ratio", range: 100...160, initial: 130, scale: 100, unit: "\u{00d7}")]
      case .potassium:
        return [.init(key: "model_outside", range: 10...200, initial: 40, scale: 10, unit: "mmol/L"),
          .init(key: "model_inside", range: 50...200, initial: 140, unit: "mmol/L")]
      #if GALAXYSSI_ATLAS_OXYGEN
      case .oxygen:
        return [.init(key: "model_oxygen_pressure", range: 0...150, initial: 100, unit: "mmHg"),
          .init(key: "model_p50", range: 150...400, initial: 268, scale: 10, unit: "mmHg"),
          .init(key: "model_hemoglobin", range: 50...200, initial: 150, unit: "g/L")]
      #endif
      }
    }
    var hasMaterialResponse: Bool { [.alveolarDiffusion, .cartilageCompression, .boneBending, .calfPump, .pelvicSupport, .cushionContactPressure, .diaphragmDisplacement, .arterialContinuity, .airwayCiliaryClearance, .cornealRefraction, .circadianLightWindow, .adiposeVolumeShare, .toothEnamelSection, .renalTubuleRetention].contains(self) }
    var axis: Int {
      if let teaching { return teaching.axis }
      if self == .calfPump { return 1 }
      if self == .pelvicSupport || self == .cushionContactPressure { return 1 }
      if hasMaterialResponse { return 0 }
      if self == .villusArea { return 0 }
      if self == .lymphValve { return 0 }
      if self == .sweatEvaporation { return 0 }
      if self == .photonCapture { return 0 }
      if self == .thyroidFeedback { return 0 }
      if self == .alveolarSurface { return 0 }
      if self == .elbow { return 0 }
      if self == .middleEar { return 0 }
      if self == .nerveTransit { return 0 }
      if self == .ejection { return 0 }
      #if GALAXYSSI_ATLAS_OXYGEN
      if self == .oxygen { return 0 }
      #endif
      return self == .potassium ? 0 : 1
    }
    var unit: String {
      if let teaching { return teaching.unit }
      if self == .pelvicSupport { return "N" }
      if self == .cushionContactPressure { return "kPa" }
      if self == .calfPump { return "mL/min" }
      if self == .alveolarDiffusion { return "\u{00d7}" }
      if self == .cartilageCompression { return "%" }
      if self == .boneBending { return "MPa" }
      if self == .villusArea { return "\u{00d7}" }
      if self == .lymphValve { return "mL/min" }
      if self == .sweatEvaporation { return "W" }
      if self == .photonCapture { return "%" }
      if self == .thyroidFeedback { return "%" }
      if self == .alveolarSurface { return "Pa" }
      if self == .bicarbonateMix { return "mmol/L" }
      if self == .eye { return "mm" }
      if self == .vessel { return "mL/min" }
      if self == .elbow { return "N" }
      if self == .middleEar { return "\u{00d7}" }
      if self == .nerveTransit { return "ms" }
      if self == .ejection { return "%" }
      #if GALAXYSSI_ATLAS_OXYGEN
      if self == .oxygen { return "%" }
      #endif
      return self == .ventilation ? "L/min" : self == .renal ? "mg/min" : "mV"
    }
    var bounds: ClosedRange<Double> {
      if let teaching { return teaching.bounds }
      if self == .pelvicSupport { return 0...800 }
      if self == .cushionContactPressure { return 0...80 }
      if self == .calfPump { return 0...750 }
      if self == .alveolarDiffusion || self == .cartilageCompression { return 0...8 }
      if self == .boneBending { return 0...26 }
      if self == .villusArea { return 1...14 }
      if self == .lymphValve { return 0...2 }
      if self == .sweatEvaporation { return 0...900 }
      if self == .photonCapture { return 0...100 }
      if self == .thyroidFeedback { return 0...100 }
      if self == .alveolarSurface { return 0...1400 }
      if self == .bicarbonateMix { return 0...100 }
      if self == .eye { return -3...3 }
      if self == .vessel { return 0...3 }
      if self == .elbow { return 0...2700 }
      if self == .middleEar { return 0...60 }
      if self == .nerveTransit { return 0...1500 }
      if self == .ejection { return 0...100 }
      #if GALAXYSSI_ATLAS_OXYGEN
      if self == .oxygen { return 0...100 }
      #endif
      return self == .ventilation ? 0...27 : self == .renal ? 0...300 : -150...0
    }
    var source: URL {
      switch self {
      case .capillaryExchange, .valveFlux, .glomerularFiltration, .skinWaterBarrier, .salivaryDelivery,
           .tendonElongation, .airwaySplit, .peristalticTravel, .cochlearFrequency,
           .diaphragmDisplacement, .cardiacPhaseTime, .visualAngle, .serialAbsorption, .hormoneSignal,
           .immuneComposition, .ductTransit, .oviductCiliaryCycles, .kneeMoment,
           .arterialContinuity, .glialCapacitance, .colonicWaterBalance, .lymphParticleTransport, .endocrineDilution,
           .boneSection, .retinalConvergence, .muscleShortening, .keratinGrowth,
           .bladderExpansion, .vestibularTilt, .airwayCiliaryClearance, .gastricLiquidEmptying, .bileStorage,
           .thoracicCrossSection, .plateletFragmentCount, .boneRemodelingBalance, .cutaneousSebum,
           .ureterDelivery, .cornealRefraction, .externalEarResonance, .neuralRelayDelays, .biliaryFlowTally,
           .parathyroidSignalOccupancy, .follicleSurface, .jointArticularArc, .sweatDuctBalance,
           .vocalCycles, .vertebralSeries, .oralMarkerDilution, .olfactorySurfaceRetention, .circadianLightWindow,
           .adiposeVolumeShare, .thymicBranching, .gastricPrecursorBalance, .melaninDistribution,
           .placentalMarker, .renalTubuleRetention, .merkelContact, .toothEnamelSection, .mucosalSampling,
           .mammaryDuctDelivery, .rectalReservoir, .stromalMatrix, .mucusFilmThickness:
        return teaching!.sources[0]
      case .pelvicSupport: return GalaxySSIHealthAtlasLoadTransfer.stabilitySource
      case .cushionContactPressure: return GalaxySSIHealthAtlasLoadTransfer.pressureSource
      case .calfPump: return URL(string: "https://pubmed.ncbi.nlm.nih.gov/24415543/")!
      case .alveolarDiffusion: return URL(string: "https://pubmed.ncbi.nlm.nih.gov/8210754/")!
      case .cartilageCompression: return URL(string: "https://pubmed.ncbi.nlm.nih.gov/7054208/")!
      case .boneBending: return URL(string: "https://pmc.ncbi.nlm.nih.gov/articles/PMC8933494/")!
      case .villusArea: return URL(string: "https://pubmed.ncbi.nlm.nih.gov/24694282/")!
      case .lymphValve: return URL(string: "https://pmc.ncbi.nlm.nih.gov/articles/PMC4500195/")!
      case .sweatEvaporation: return URL(string: "https://pubmed.ncbi.nlm.nih.gov/23459754/")!
      case .photonCapture: return URL(string: "https://www.itl.nist.gov/div898/handbook/eda/section3/eda366j.htm")!
      case .thyroidFeedback: return URL(string: "https://openstax.org/books/anatomy-and-physiology-2e/pages/17-4-the-thyroid-gland")!
      case .alveolarSurface: return URL(string: "https://pubmed.ncbi.nlm.nih.gov/20724566/")!
      case .bicarbonateMix: return URL(string: "https://openstax.org/books/anatomy-and-physiology-2e/pages/23-6-accessory-organs-in-digestion-the-liver-pancreas-and-gallbladder")!
      case .nerveTransit: return URL(string: "https://www.ncbi.nlm.nih.gov/books/NBK10921/")!
      case .ejection: return GalaxySSIHealthAtlasHeartSection.ejectionSource
      case .eye: return GalaxySSIHealthAtlasEyeOptics.source
      case .vessel: return GalaxySSIHealthAtlasVesselFlow.sources[0]
      case .elbow: return GalaxySSIHealthAtlasElbow.source
      case .ventilation: return URL(string: "https://openstax.org/books/anatomy-and-physiology-2e/pages/22-3-the-process-of-breathing")!
      case .renal: return URL(string: "https://openstax.org/books/anatomy-and-physiology-2e/pages/25-6-tubular-reabsorption")!
      case .middleEar: return GalaxySSIHealthAtlasMiddleEar.source
      case .potassium: return URL(string: "https://neurotext.library.stonybrook.edu/C2/C2_4/C2_4.html")!
      #if GALAXYSSI_ATLAS_OXYGEN
      case .oxygen: return GalaxySSIHealthAtlasOxygen.bindingSource
      #endif
      }
    }
    var sources: [URL] {
      if let teaching { return teaching.sources }
      if self == .pelvicSupport { return [source, GalaxySSIHealthAtlasLoadTransfer.pelvicSource] }
      if self == .cushionContactPressure { return [source, GalaxySSIHealthAtlasLoadTransfer.subcutaneousSource] }
      if self == .calfPump { return [source, URL(string: "https://pubmed.ncbi.nlm.nih.gov/8445740/")!] }
      if self == .alveolarDiffusion { return [source, URL(string: "https://pmc.ncbi.nlm.nih.gov/articles/PMC2106384/")!] }
      if self == .cartilageCompression { return [source, URL(string: "https://pubmed.ncbi.nlm.nih.gov/7382457/")!] }
      if self == .photonCapture { return [source, URL(string: "https://pubmed.ncbi.nlm.nih.gov/112243/")!] }
      if self == .middleEar { return [GalaxySSIHealthAtlasMiddleEar.source, GalaxySSIHealthAtlasMiddleEar.measurementSource] }
      if self == .vessel { return GalaxySSIHealthAtlasVesselFlow.sources }
      #if GALAXYSSI_ATLAS_OXYGEN
      if self == .oxygen { return GalaxySSIHealthAtlasOxygen.sources }
      #endif
      return [source]
    }
    static func forEntry(_ id: String) -> Self? {
      switch id {
      case "pelvis": return .pelvicSupport
      case "subcutaneous-tissue": return .cushionContactPressure
      case "soleus", "gastrocnemius": return .calfPump
      case "respiratory-membrane", "pulmonary-capillaries", "tissue-alveolar-epithelium",
           "cell-type-i-pneumocyte": return .alveolarDiffusion
      case "cartilage", "tissue-hyaline-cartilage", "cell-chondrocyte": return .cartilageCompression
      case "limb-bones", "femur", "tibia", "fibula": return .boneBending
      case "small-intestine", "jejunum": return .villusArea
      case "lymphatic-vessels": return .lymphValve
      case "sweat-glands": return .sweatEvaporation
      case "cell-rod-photoreceptor": return .photonCapture
      case "thyroid-gland": return .thyroidFeedback
      case "cell-type-ii-pneumocyte": return .alveolarSurface
      case "pancreas", "pancreatic-duct", "cell-pancreatic-ductal-cell": return .bicarbonateMix
      case "cranial-nerves", "spinal-nerves", "peripheral-nerves": return .nerveTransit
      case "ventricles", "left-ventricle", "right-ventricle": return .ejection
      case "eye", "lens": return .eye
      case "blood-vessels", "arteries", "veins", "coronary-vessels": return .vessel
      case "skeletal", "muscle", "biceps-brachii", "humerus", "radius", "ulna": return .elbow
      case "respiratory", "lungs", "alveoli": return .ventilation
      case "urinary", "kidneys", "nephron", "renal-tubules", "collecting-ducts", "proximal-tubule", "nephron-loop",
           "distal-tubule", "cell-proximal-tubular-cell",
           "cell-distal-tubular-cell", "cell-collecting-duct-principal-cell", "cell-collecting-duct-intercalated-cell": return .renal
      case "nervous", "brain", "spinal-cord", "cell-neuron", "cell-olfactory-receptor-neuron": return .potassium
      case "ear", "middle-ear": return .middleEar
      #if GALAXYSSI_ATLAS_OXYGEN
      case "blood", "cell-erythrocyte": return .oxygen
      #endif
      default: return GalaxySSIHealthAtlasTeachingModel.forEntry(id).flatMap { Self(rawValue: $0.rawValue) }
      }
    }
  }
  struct Point: Identifiable {
    let id: Int
    let x: Double
    let y: Double
  }
  let kind: Kind
  let inputs: [Int]

  init(kind: Kind) { self.kind = kind; inputs = kind.inputs.map(\.initial) }
  init?(kind: Kind, inputs: [Int]) {
    guard inputs.count == kind.inputs.count, inputs.indices.allSatisfy({ kind.inputs[$0].range.contains(inputs[$0]) }) else { return nil }
    self.kind = kind; self.inputs = inputs
  }
  func input(_ index: Int) -> Double { Double(inputs[index]) / kind.inputs[index].scale }
  func changing(_ index: Int, to value: Int) -> Self? {
    guard inputs.indices.contains(index) else { return nil }
    var changed = inputs; changed[index] = value
    return Self(kind: kind, inputs: changed)
  }
  var result: Double { evaluate(inputs.indices.map(input)) }
  var companionValue: Double {
    switch kind {
    case .capillaryExchange, .valveFlux, .glomerularFiltration, .skinWaterBarrier, .salivaryDelivery,
         .tendonElongation, .airwaySplit, .peristalticTravel, .cochlearFrequency,
         .diaphragmDisplacement, .cardiacPhaseTime, .visualAngle, .serialAbsorption, .hormoneSignal,
         .immuneComposition, .ductTransit, .oviductCiliaryCycles, .kneeMoment,
         .arterialContinuity, .glialCapacitance, .colonicWaterBalance, .lymphParticleTransport, .endocrineDilution,
         .boneSection, .retinalConvergence, .muscleShortening, .keratinGrowth,
         .bladderExpansion, .vestibularTilt, .airwayCiliaryClearance, .gastricLiquidEmptying, .bileStorage,
         .thoracicCrossSection, .plateletFragmentCount, .boneRemodelingBalance, .cutaneousSebum,
         .ureterDelivery, .cornealRefraction, .externalEarResonance, .neuralRelayDelays, .biliaryFlowTally,
         .parathyroidSignalOccupancy, .follicleSurface, .jointArticularArc, .sweatDuctBalance,
         .vocalCycles, .vertebralSeries, .oralMarkerDilution, .olfactorySurfaceRetention, .circadianLightWindow,
         .adiposeVolumeShare, .thymicBranching, .gastricPrecursorBalance, .melaninDistribution,
         .placentalMarker, .renalTubuleRetention, .merkelContact, .toothEnamelSection, .mucosalSampling,
         .mammaryDuctDelivery, .rectalReservoir, .stromalMatrix, .mucusFilmThickness:
      return kind.teaching!.companion(inputs.indices.map(input))!
    case .pelvicSupport:
      return GalaxySSIHealthAtlasLoadTransfer.PelvicSupport(loadNewtons: input(0), positionPercent: input(1))!.leftNewtons
    case .cushionContactPressure:
      return GalaxySSIHealthAtlasLoadTransfer.CushionContact(loadNewtons: input(0), areaSquareCentimetres: input(1))!.referenceKilopascals
    case .calfPump: return Self.netStroke(ejected: input(0), returnPercent: input(2))
    case .alveolarDiffusion: return input(1) / input(2)
    case .cartilageCompression: return 100 - result
    case .boneBending: return Self.circularSectionMoment(diameter: input(1), innerRatio: input(2))
    case .villusArea: return result - 1
    case .lymphValve: return input(0) / input(1)
    case .sweatEvaporation: return input(0) * input(1) / 100
    case .photonCapture: return 100 * exp(-input(0))
    case .thyroidFeedback: return input(0) - result
    case .alveolarSurface: return result / 2
    case .bicarbonateMix: return 20 + input(0) * input(1)
    case .nerveTransit: return 100 / input(1)
    case .ejection: return input(0) + input(1)
    case .eye: return eyeOptics!.targetPowerDiopters
    case .vessel: return vesselFlow!.resistanceMmHgMinutesPerMl
    case .elbow: return elbowForces!.jointDown
    case .ventilation: return input(0) * input(1) / 1000
    case .renal: return renalAmounts!.reabsorbed
    case .potassium: return input(0) / input(1)
    case .middleEar: return middleEar!.pressureGainDb
    #if GALAXYSSI_ATLAS_OXYGEN
    case .oxygen: return oxygenAmounts!.total
    #endif
    }
  }
  var renalAmounts: GalaxySSIHealthAtlasRenalAmounts? {
    kind == .renal ? GalaxySSIHealthAtlasRenalAmounts(filtered: input(0), reabsorbedPercent: input(1), secreted: input(2)) : nil
  }
  var elbowForces: GalaxySSIHealthAtlasElbow.Forces? {
    kind == .elbow ? GalaxySSIHealthAtlasElbow.forces(loadKg: input(0), loadArmCm: input(1), muscleArmMm: input(2)) : nil
  }
  var middleEar: GalaxySSIHealthAtlasMiddleEar? {
    kind == .middleEar ? GalaxySSIHealthAtlasMiddleEar(membraneAreaMm2: input(0), footplateAreaMm2: input(1), leverRatio: input(2)) : nil
  }
  var vesselFlow: GalaxySSIHealthAtlasVesselFlow? {
    kind == .vessel ? GalaxySSIHealthAtlasVesselFlow(pressureMmHg: input(0), radiusMm: input(1),
      lengthMm: input(2), viscosityMilliPascalSeconds: input(3)) : nil
  }
  var eyeOptics: GalaxySSIHealthAtlasEyeOptics? {
    kind == .eye ? GalaxySSIHealthAtlasEyeOptics(distanceMetres: input(0), powerDiopters: input(1)) : nil
  }
  var plotMaximum: Double {
    if kind == .alveolarSurface { return ceil(resultAt(axisRange.upperBound)! / 100) * 100 }
    if kind == .nerveTransit { return ceil(resultAt(axisRange.upperBound)! / 10) * 10 }
    if kind == .elbow { return ceil(resultAt(axisRange.upperBound)! / 100) * 100 }
    if kind == .vessel {
      let peak = resultAt(axisRange.upperBound)!
      guard peak > 0 else { return 0.01 }
      let scale = pow(10, floor(log10(peak)))
      return ceil(peak / scale) * scale
    }
    return kind.bounds.upperBound
  }
  #if GALAXYSSI_ATLAS_OXYGEN
  var oxygenAmounts: GalaxySSIHealthAtlasOxygen.Amounts? {
    kind == .oxygen ? GalaxySSIHealthAtlasOxygen.amounts(pressure: input(0), p50: input(1), hemoglobinGramsPerLiter: input(2)) : nil
  }
  #endif
  var axisRange: ClosedRange<Double> {
    let spec = kind.inputs[kind.axis]
    return Double(spec.range.lowerBound) / spec.scale...Double(spec.range.upperBound) / spec.scale
  }
  func resultAt(_ x: Double) -> Double? {
    guard x.isFinite, axisRange.contains(x) else { return nil }
    return evaluate(inputs.indices.map { $0 == kind.axis ? x : input($0) })
  }
  var response: [Point] {
    (0...120).map { step in
      let x = axisRange.lowerBound + (axisRange.upperBound - axisRange.lowerBound) * Double(step) / 120
      return Point(id: step, x: x, y: resultAt(x)!)
    }
  }
  private func evaluate(_ values: [Double]) -> Double {
    switch kind {
    case .capillaryExchange, .valveFlux, .glomerularFiltration, .skinWaterBarrier, .salivaryDelivery,
         .tendonElongation, .airwaySplit, .peristalticTravel, .cochlearFrequency,
         .diaphragmDisplacement, .cardiacPhaseTime, .visualAngle, .serialAbsorption, .hormoneSignal,
         .immuneComposition, .ductTransit, .oviductCiliaryCycles, .kneeMoment,
         .arterialContinuity, .glialCapacitance, .colonicWaterBalance, .lymphParticleTransport, .endocrineDilution,
         .boneSection, .retinalConvergence, .muscleShortening, .keratinGrowth,
         .bladderExpansion, .vestibularTilt, .airwayCiliaryClearance, .gastricLiquidEmptying, .bileStorage,
         .thoracicCrossSection, .plateletFragmentCount, .boneRemodelingBalance, .cutaneousSebum,
         .ureterDelivery, .cornealRefraction, .externalEarResonance, .neuralRelayDelays, .biliaryFlowTally,
         .parathyroidSignalOccupancy, .follicleSurface, .jointArticularArc, .sweatDuctBalance,
         .vocalCycles, .vertebralSeries, .oralMarkerDilution, .olfactorySurfaceRetention, .circadianLightWindow,
         .adiposeVolumeShare, .thymicBranching, .gastricPrecursorBalance, .melaninDistribution,
         .placentalMarker, .renalTubuleRetention, .merkelContact, .toothEnamelSection, .mucosalSampling,
         .mammaryDuctDelivery, .rectalReservoir, .stromalMatrix, .mucusFilmThickness:
      return kind.teaching!.evaluate(values)!
    case .pelvicSupport:
      return GalaxySSIHealthAtlasLoadTransfer.PelvicSupport(loadNewtons: values[0], positionPercent: values[1])!.rightNewtons
    case .cushionContactPressure:
      return GalaxySSIHealthAtlasLoadTransfer.CushionContact(loadNewtons: values[0], areaSquareCentimetres: values[1])!.pressureKilopascals
    case .calfPump: return values[1] * Self.netStroke(ejected: values[0], returnPercent: values[2])
    case .alveolarDiffusion: return values[0] * values[1] / values[2]
    // Stress kPa / modulus MPa, converted from strain fraction to percent.
    case .cartilageCompression: return values[0] / (10 * values[1])
    // Outer-fiber flexure; 1000 converts the applied N m into N mm.
    case .boneBending:
      return 500 * values[0] * values[1] / Self.circularSectionMoment(diameter: values[1], innerRatio: values[2])
    case .villusArea: return 1 + values[0] * 2 * .pi * values[1] * values[2]
    case .lymphValve: return max(values[0], 0) / values[1]
    // Evaporated g/min times the example latent heat near 30 C, converted to watts.
    case .sweatEvaporation: return values[0] * values[1] / 100 * 2426 / 60
    case .photonCapture: return -100 * expm1(-values[0])
    // Static dimensionless feedback: output = drive - gain * output.
    case .thyroidFeedback: return values[0] / (1 + values[1])
    // Young-Laplace for a single spherical interface: mN/m and micrometres converted to SI.
    case .alveolarSurface: return 2000 * values[0] / values[1]
    case .bicarbonateMix: return (20 + values[0] * values[1]) / (1 + values[0])
    case .nerveTransit: return 10 * values[0] / values[1]
    case .ejection: return 100 * values[0] / (values[0] + values[1])
    case .eye: return GalaxySSIHealthAtlasEyeOptics(distanceMetres: values[0], powerDiopters: values[1])!.offsetMm
    case .vessel: return GalaxySSIHealthAtlasVesselFlow(pressureMmHg: values[0], radiusMm: values[1],
      lengthMm: values[2], viscosityMilliPascalSeconds: values[3])!.flowMlPerMinute
    case .elbow: return GalaxySSIHealthAtlasElbow.forces(loadKg: values[0], loadArmCm: values[1], muscleArmMm: values[2])!.muscle
    case .ventilation: return values[0] * (values[1] - values[2]) / 1000
    case .renal: return GalaxySSIHealthAtlasRenalAmounts(filtered: values[0], reabsorbedPercent: values[1], secreted: values[2])!.excreted
    case .potassium: return Self.potassiumPotential(outside: values[0], inside: values[1])!
    case .middleEar: return GalaxySSIHealthAtlasMiddleEar(membraneAreaMm2: values[0], footplateAreaMm2: values[1], leverRatio: values[2])!.pressureRatio
    #if GALAXYSSI_ATLAS_OXYGEN
    case .oxygen: return 100 * GalaxySSIHealthAtlasOxygen.saturation(pressure: values[0], p50: values[1])!
    #endif
    }
  }
  nonisolated static func circularSectionMoment(diameter: Double, innerRatio: Double) -> Double {
    .pi * pow(diameter, 4) * (1 - pow(innerRatio, 4)) / 64
  }
  nonisolated static func netStroke(ejected: Double, returnPercent: Double) -> Double {
    ejected * (100 - returnPercent) / 100
  }
  static func potassiumPotential(outside: Double, inside: Double) -> Double? {
    guard outside.isFinite, inside.isFinite, outside > 0, inside > 0 else { return nil }
    // Nernst for z = +1 at 310.15 K, volts converted to millivolts. Log difference avoids ratio underflow.
    return 8.31446261815324 * 310.15 / 96485.33212 * 1000 * (log(outside) - log(inside))
  }
  static func restore(_ id: String, inputs: [Int]?) -> Self? {
    guard let kind = Kind.forEntry(id), let inputs else { return nil }
    return Self(kind: kind, inputs: inputs)
  }
  static func resolved(_ id: String, inputs: [Int]?, legacyVentilation: [Double]? = nil) -> Self? {
    guard let kind = Kind.forEntry(id) else { return nil }
    if let restored = restore(id, inputs: inputs) { return restored }
    if kind == .ventilation, ["lungs", "respiratory"].contains(id), let values = legacyVentilation, values.count == 2,
       values.enumerated().allSatisfy({ index, value in
         value.isFinite && value.rounded() == value && value >= Double(kind.inputs[index].range.lowerBound) &&
           value <= Double(kind.inputs[index].range.upperBound)
       }), let migrated = Self(kind: kind, inputs: values.map(Int.init) + [150]) { return migrated }
    return Self(kind: kind)
  }
}
