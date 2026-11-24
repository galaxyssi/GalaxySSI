import Foundation

/// Synthetic teaching examples, never patient measurements or estimates.
enum GalaxySSIHealthAtlasTeachingModel: String, CaseIterable, Sendable {
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

  struct Control: Sendable {
    let input: GalaxySSIHealthAtlasPhysiology.Input
    let label: String
    var digits: Int = 2
  }
  var inputs: [GalaxySSIHealthAtlasPhysiology.Input] { controls.map(\.input) }
  var axis: Int {
    switch self {
    case .valveFlux, .skinWaterBarrier, .airwaySplit, .peristalticTravel,
         .cardiacPhaseTime, .visualAngle, .serialAbsorption, .hormoneSignal,
         .immuneComposition, .oviductCiliaryCycles, .colonicWaterBalance,
         .endocrineDilution, .retinalConvergence, .muscleShortening,
         .bladderExpansion, .gastricLiquidEmptying, .bileStorage, .cutaneousSebum,
         .neuralRelayDelays, .sweatDuctBalance, .vertebralSeries, .oralMarkerDilution,
         .olfactorySurfaceRetention, .circadianLightWindow, .thymicBranching, .gastricPrecursorBalance,
         .placentalMarker, .renalTubuleRetention, .mammaryDuctDelivery, .rectalReservoir, .mucusFilmThickness: return 1
    default: return 0
    }
  }
  var unit: String {
    switch self {
    case .capillaryExchange: return "%"
    case .valveFlux: return "mL/s"
    case .glomerularFiltration: return "nL/min"
    case .skinWaterBarrier: return "\u{00d7}"
    case .salivaryDelivery: return "DU/min"
    case .tendonElongation: return "mm"
    case .airwaySplit: return "L/s"
    case .peristalticTravel: return "cm"
    case .cochlearFrequency: return "Hz"
    case .diaphragmDisplacement: return "mL"
    case .cardiacPhaseTime: return "ms"
    case .visualAngle: return "\u{00b0}"
    case .serialAbsorption, .hormoneSignal: return "%"
    case .immuneComposition: return "cells"
    case .ductTransit: return "TU"
    case .oviductCiliaryCycles: return "cycles"
    case .kneeMoment: return "N\u{00b7}m"
    case .arterialContinuity: return "cm/s"
    case .glialCapacitance: return "\u{00d7}"
    case .colonicWaterBalance: return "mL"
    case .lymphParticleTransport: return "\u{00b5}g/min"
    case .endocrineDilution: return "TU/VU"
    case .boneSection: return "MPa"
    case .retinalConvergence: return ""
    case .muscleShortening, .keratinGrowth: return "mm"
    case .bladderExpansion, .gastricLiquidEmptying: return "%"
    case .vestibularTilt: return "\u{00b0}"
    case .airwayCiliaryClearance: return "u"
    case .bileStorage: return "TU/VU"
    case .thoracicCrossSection: return "cm\u{00b2}"
    case .plateletFragmentCount: return ""
    case .boneRemodelingBalance: return "a.u."
    case .cutaneousSebum: return "\u{00b5}g/cm\u{00b2}"
    case .ureterDelivery: return "mL"
    case .cornealRefraction: return "\u{00b0}"
    case .externalEarResonance: return "Hz"
    case .neuralRelayDelays: return "ms"
    case .biliaryFlowTally: return "VU/min"
    case .parathyroidSignalOccupancy: return "%"
    case .follicleSurface: return "mm\u{00b2}"
    case .jointArticularArc: return "mm"
    case .sweatDuctBalance: return "nmol"
    case .vocalCycles: return "cycles"
    case .vertebralSeries: return "mm"
    case .oralMarkerDilution: return "TU/VU"
    case .olfactorySurfaceRetention: return "a.u."
    case .circadianLightWindow: return "\u{00b0}"
    case .adiposeVolumeShare: return "%"
    case .thymicBranching: return "tiles"
    case .gastricPrecursorBalance: return "MU"
    case .melaninDistribution: return "PPU/cell"
    case .placentalMarker, .renalTubuleRetention: return "a.u."
    case .merkelContact: return "kPa"
    case .toothEnamelSection, .mucosalSampling: return "%"
    case .mammaryDuctDelivery: return "VU"
    case .rectalReservoir: return "mL"
    case .stromalMatrix: return "MU/AU"
    case .mucusFilmThickness: return "u"
    }
  }
  var bounds: ClosedRange<Double> {
    switch self {
    case .capillaryExchange: return 0...100
    case .valveFlux: return 0...500
    case .glomerularFiltration: return 0...200
    case .skinWaterBarrier: return 0...4.5
    case .salivaryDelivery: return 0...15
    case .tendonElongation: return 0...0.65
    case .airwaySplit: return 0...0.5
    case .peristalticTravel: return 0...10
    case .cochlearFrequency: return 0...21_000
    case .diaphragmDisplacement: return 0...750
    case .cardiacPhaseTime: return 0...1200
    case .visualAngle, .ductTransit: return 0...25
    case .serialAbsorption, .hormoneSignal: return 0...100
    case .immuneComposition: return 0...500
    case .oviductCiliaryCycles: return 0...20
    case .kneeMoment: return 0...1.25
    case .arterialContinuity: return 0...200
    case .glialCapacitance: return 0...4
    case .colonicWaterBalance: return 0...1000
    case .lymphParticleTransport: return 0...30
    case .endocrineDilution: return 0...6
    case .boneSection: return 0...5
    case .retinalConvergence, .keratinGrowth: return 0...16
    case .muscleShortening: return 0...1
    case .bladderExpansion: return 0...270
    case .vestibularTilt: return 0...65
    case .airwayCiliaryClearance: return 0...60
    case .gastricLiquidEmptying: return 0...100
    case .bileStorage: return 0...3
    case .thoracicCrossSection: return 200...700
    case .plateletFragmentCount: return 0...48
    case .boneRemodelingBalance: return -20...20
    case .cutaneousSebum: return 0...20
    case .ureterDelivery: return 0...18
    case .cornealRefraction: return 0...50
    case .externalEarResonance: return 150...950
    case .neuralRelayDelays: return 0...20
    case .biliaryFlowTally: return 0...48
    case .parathyroidSignalOccupancy: return 0...100
    case .follicleSurface: return 0...850
    case .jointArticularArc: return 0...65
    case .sweatDuctBalance: return 0...160
    case .vocalCycles: return 0...7.2
    case .vertebralSeries: return 0...8
    case .oralMarkerDilution: return 0...4
    case .olfactorySurfaceRetention, .adiposeVolumeShare: return 0...100
    case .circadianLightWindow: return 0...1440
    case .thymicBranching: return 0...200
    case .gastricPrecursorBalance: return 0...20
    case .melaninDistribution: return 0...12
    case .placentalMarker: return 0...60
    case .renalTubuleRetention, .toothEnamelSection, .mucosalSampling: return 0...100
    case .merkelContact: return 0...(80 / .pi)
    case .mammaryDuctDelivery, .mucusFilmThickness: return 0...12
    case .rectalReservoir: return 0...200
    case .stromalMatrix: return 0...30
    }
  }
  var digits: Int {
    switch self {
    case .glomerularFiltration, .cardiacPhaseTime, .airwayCiliaryClearance, .neuralRelayDelays: return 1
    case .tendonElongation, .muscleShortening: return 3
    case .immuneComposition, .plateletFragmentCount, .boneRemodelingBalance, .thymicBranching: return 0
    default: return 2
    }
  }
  var resourcePrefix: String {
    switch self {
    case .capillaryExchange: return "health_atlas_capillary_exchange"
    case .valveFlux: return "health_atlas_valve_flux"
    case .glomerularFiltration: return "health_atlas_glomerular_filtration"
    case .skinWaterBarrier: return "health_atlas_skin_water_barrier"
    case .salivaryDelivery: return "health_atlas_salivary_delivery"
    case .tendonElongation: return "health_atlas_tendon_elongation"
    case .airwaySplit: return "health_atlas_airway_split"
    case .peristalticTravel: return "health_atlas_peristaltic_travel"
    case .cochlearFrequency: return "health_atlas_model_cochlear_frequency"
    case .diaphragmDisplacement: return "health_atlas_diaphragm_demo"
    case .cardiacPhaseTime: return "health_atlas_cardiac_phase_time"
    case .visualAngle: return "health_atlas_model_visual_angle"
    case .serialAbsorption: return "health_atlas_serial_absorption"
    case .hormoneSignal: return "health_atlas_hormone_signal"
    case .immuneComposition: return "health_atlas_immune_composition"
    case .ductTransit: return "health_atlas_duct_transit"
    case .oviductCiliaryCycles: return "health_atlas_oviduct_ciliary_cycles"
    case .kneeMoment: return "health_atlas_knee_moment"
    case .arterialContinuity: return "health_atlas_arterial_continuity"
    case .glialCapacitance: return "health_atlas_glial_capacitance"
    case .colonicWaterBalance: return "health_atlas_colonic_water_balance"
    case .lymphParticleTransport: return "health_atlas_lymph_particle_transport"
    case .endocrineDilution: return "health_atlas_endocrine_dilution"
    case .boneSection: return "health_atlas_bone_section"
    case .retinalConvergence: return "health_atlas_retinal_convergence"
    case .muscleShortening: return "health_atlas_muscle_shortening"
    case .keratinGrowth: return "health_atlas_keratin_growth"
    case .bladderExpansion: return "health_atlas_bladder_expansion"
    case .vestibularTilt: return "health_atlas_vestibular_tilt"
    case .airwayCiliaryClearance: return "health_atlas_airway_ciliary_clearance"
    case .gastricLiquidEmptying: return "health_atlas_gastric_liquid_emptying"
    case .bileStorage: return "health_atlas_bile_storage"
    case .thoracicCrossSection: return "health_atlas_thoracic_cross_section"
    case .plateletFragmentCount: return "health_atlas_platelet_fragment_count"
    case .boneRemodelingBalance: return "health_atlas_bone_remodeling_balance"
    case .cutaneousSebum: return "health_atlas_cutaneous_sebum"
    case .ureterDelivery: return "health_atlas_ureter_delivery"
    case .cornealRefraction: return "health_atlas_model_corneal_refraction"
    case .externalEarResonance: return "health_atlas_model_external_ear_resonance"
    case .neuralRelayDelays: return "health_atlas_neural_relay_delays"
    case .biliaryFlowTally: return "health_atlas_biliary_flow_tally"
    case .parathyroidSignalOccupancy: return "health_atlas_parathyroid_occupancy"
    case .follicleSurface: return "health_atlas_follicle_surface"
    case .jointArticularArc: return "health_atlas_joint_articular_arc"
    case .sweatDuctBalance: return "health_atlas_sweat_duct_balance"
    case .vocalCycles: return "health_atlas_vocal_cycles"
    case .vertebralSeries: return "health_atlas_vertebral_series"
    case .oralMarkerDilution: return "health_atlas_oral_marker_dilution"
    case .olfactorySurfaceRetention: return "health_atlas_olfactory_surface_retention"
    case .circadianLightWindow: return "health_atlas_circadian_light_window"
    case .adiposeVolumeShare: return "health_atlas_adipose_volume_share"
    case .thymicBranching: return "health_atlas_thymic_branching"
    case .gastricPrecursorBalance: return "health_atlas_gastric_precursor_balance"
    case .melaninDistribution: return "health_atlas_melanin_distribution"
    case .placentalMarker: return "health_atlas_placental_marker"
    case .renalTubuleRetention: return "health_atlas_renal_tubule_retention"
    case .merkelContact: return "health_atlas_merkel_contact"
    case .toothEnamelSection: return "health_atlas_tooth_enamel_section"
    case .mucosalSampling: return "health_atlas_mucosal_sampling"
    case .mammaryDuctDelivery: return "health_atlas_mammary_duct_delivery"
    case .rectalReservoir: return "health_atlas_rectal_reservoir"
    case .stromalMatrix: return "health_atlas_stromal_matrix"
    case .mucusFilmThickness: return "health_atlas_mucus_film_thickness"
    }
  }
  var title: String { resourcePrefix + "_title" }
  var scope: String { resourcePrefix + "_scope" }
  var formula: String { resourcePrefix + "_formula" }
  var companionTitle: String {
    let suffix: String
    switch self {
    case .capillaryExchange: suffix = "remaining"
    case .glomerularFiltration: suffix = "net_pressure"
    case .skinWaterBarrier: suffix = "conductance"
    case .tendonElongation: suffix = "strain"
    case .peristalticTravel: suffix = "progress"
    case .cochlearFrequency: suffix = "from_base"
    case .diaphragmDisplacement: suffix = "per_mm"
    case .visualAngle: suffix = "half"
    case .hormoneSignal: suffix = "removed"
    case .kneeMoment: suffix = "arm_meters"
    case .arterialContinuity, .boneSection, .bladderExpansion: suffix = "area"
    case .glialCapacitance: suffix = "per_area"
    case .muscleShortening: suffix = "remaining_length"
    case .vestibularTilt: suffix = "magnitude"
    case .airwayCiliaryClearance: suffix = "progress"
    case .ureterDelivery: suffix = "remaining"
    case .externalEarResonance: suffix = "wavelength"
    case .parathyroidSignalOccupancy: suffix = "unoccupied"
    case .follicleSurface: suffix = "shell_volume"
    case .vocalCycles: suffix = "period"
    case .vertebralSeries: suffix = "remaining_pad_thickness"
    case .placentalMarker: suffix = "remaining"
    default: suffix = "companion"
    }
    return resourcePrefix + "_" + suffix
  }
  var entryIDs: Set<String> {
    switch self {
    case .capillaryExchange: return ["capillaries", "tissue-vascular-endothelium", "cell-vascular-endothelial-cell"]
    case .valveFlux: return ["heart-valves", "tricuspid-valve", "mitral-valve", "pulmonary-valve", "aortic-valve"]
    case .glomerularFiltration: return ["glomerulus", "bowmans-capsule", "cell-podocyte"]
    case .skinWaterBarrier: return ["skin", "skin-organ", "epidermis", "tissue-epidermal", "cell-keratinocyte"]
    case .salivaryDelivery: return ["salivary-glands", "parotid-glands", "submandibular-glands", "sublingual-glands", "cell-salivary-acinar-cell"]
    case .tendonElongation: return ["tendons", "ligaments", "tissue-dense-regular-connective", "cell-tenocyte"]
    case .airwaySplit: return ["trachea", "bronchi", "bronchioles"]
    case .peristalticTravel: return ["esophagus", "tissue-smooth-muscle", "cell-smooth-muscle-cell"]
    case .cochlearFrequency: return ["cochlea", "inner-ear", "cell-inner-ear-hair-cell"]
    case .diaphragmDisplacement: return ["diaphragm"]
    case .cardiacPhaseTime: return ["cardio", "heart", "atria", "left-atrium", "right-atrium", "tissue-cardiac-muscle", "cell-cardiomyocyte"]
    case .visualAngle: return ["sensory", "retina"]
    case .serialAbsorption: return ["gut", "digestive", "duodenum", "ileum", "cell-enterocyte"]
    case .hormoneSignal: return ["endocrine", "pituitary-gland", "cell-thyrotroph"]
    case .immuneComposition: return ["immune", "cell-neutrophil", "cell-eosinophil", "cell-basophil", "cell-monocyte", "cell-t-cell", "cell-b-cell", "cell-natural-killer-cell"]
    case .ductTransit: return ["male", "epididymis", "vas-deferens", "ejaculatory-ducts"]
    case .oviductCiliaryCycles: return ["female", "uterine-tubes", "cell-ciliated-oviduct-cell"]
    case .kneeMoment: return ["patella", "quadriceps-femoris"]
    case .arterialContinuity: return ["aorta", "pulmonary-trunk"]
    case .glialCapacitance: return ["cell-schwann-cell", "cell-oligodendrocyte"]
    case .colonicWaterBalance: return ["large-intestine", "colon"]
    case .lymphParticleTransport: return ["lymph-nodes", "thoracic-duct", "cell-lymphatic-endothelial-cell"]
    case .endocrineDilution: return ["adrenal-glands", "cell-adrenocortical-cell", "cell-chromaffin-cell", "cell-somatotroph", "cell-lactotroph", "cell-corticotroph", "cell-gonadotroph", "pancreatic-islets", "cell-pancreatic-beta-cell", "cell-pancreatic-alpha-cell", "cell-pancreatic-delta-cell", "cell-pancreatic-pp-cell"]
    case .boneSection: return ["tissue-compact-bone", "clavicle", "hand-bones", "foot-bones"]
    case .retinalConvergence: return ["cell-retinal-ganglion-cell", "cell-retinal-bipolar-cell"]
    case .muscleShortening: return ["cell-skeletal-myocyte", "tissue-skeletal-muscle", "pectoralis-major", "deltoid", "triceps-brachii", "rectus-abdominis", "oblique-abdominal-muscles", "trapezius", "latissimus-dorsi", "erector-spinae", "gluteus-maximus", "hamstrings"]
    case .keratinGrowth: return ["hair", "hair-follicles", "cell-hair-matrix-cell"]
    case .bladderExpansion: return ["bladder", "cell-urothelial-cell"]
    case .vestibularTilt: return ["vestibular-apparatus"]
    case .airwayCiliaryClearance: return ["nose", "nasal-cavity", "paranasal-sinuses", "tissue-respiratory-epithelium", "cell-ciliated-airway-cell"]
    case .gastricLiquidEmptying: return ["stomach"]
    case .bileStorage: return ["gallbladder"]
    case .thoracicCrossSection: return ["ribs", "sternum"]
    case .plateletFragmentCount: return ["fragment-platelet", "cell-megakaryocyte"]
    case .boneRemodelingBalance: return ["cell-osteoblast", "cell-osteoclast", "cell-osteocyte"]
    case .cutaneousSebum: return ["sebaceous-glands", "cell-sebocyte"]
    case .ureterDelivery: return ["renal-pelvis", "ureters"]
    case .cornealRefraction: return ["cornea", "cell-corneal-epithelial-cell"]
    case .externalEarResonance: return ["external-ear"]
    case .neuralRelayDelays: return ["cerebrum", "cerebellum", "brainstem", "ganglia", "autonomic-nerves", "tissue-central-nervous"]
    case .biliaryFlowTally: return ["liver", "biliary-tract", "cell-hepatocyte", "cell-cholangiocyte"]
    case .parathyroidSignalOccupancy: return ["parathyroid-glands", "cell-parathyroid-chief-cell"]
    case .follicleSurface: return ["ovaries", "cell-granulosa-cell", "cell-theca-cell"]
    case .jointArticularArc: return ["joints", "scapula"]
    case .sweatDuctBalance: return ["cell-sweat-gland-secretory-cell", "dermis"]
    case .vocalCycles: return ["larynx"]
    case .vertebralSeries: return ["vertebrae"]
    case .oralMarkerDilution: return ["oral-cavity", "tongue", "taste-buds", "cell-taste-receptor-cell"]
    case .olfactorySurfaceRetention: return ["olfactory-mucosa"]
    case .circadianLightWindow: return ["hypothalamus", "pineal-gland", "cell-pinealocyte"]
    case .adiposeVolumeShare: return ["tissue-white-adipose", "cell-adipocyte"]
    case .thymicBranching: return ["thymus", "cell-helper-t-cell", "cell-cytotoxic-t-cell", "cell-regulatory-t-cell"]
    case .gastricPrecursorBalance: return ["cell-gastric-chief-cell", "cell-gastric-parietal-cell"]
    case .melaninDistribution: return ["cell-melanocyte"]
    case .placentalMarker: return ["placenta", "cell-trophoblast"]
    case .renalTubuleRetention: return ["tissue-renal-tubular-epithelium", "renal-cortex", "renal-medulla"]
    case .merkelContact: return ["cell-merkel-cell"]
    case .toothEnamelSection: return ["teeth"]
    case .mucosalSampling: return ["tonsils", "adenoids", "appendix", "gut-associated-lymphoid-tissue"]
    case .mammaryDuctDelivery: return ["mammary-glands", "cell-mammary-luminal-cell", "cell-myoepithelial-cell"]
    case .rectalReservoir: return ["rectum", "anal-canal"]
    case .stromalMatrix: return ["cell-fibroblast", "cell-endometrial-stromal-cell", "endometrium"]
    case .mucusFilmThickness: return ["cell-goblet-cell", "pharynx", "tissue-intestinal-epithelium"]
    }
  }
  var sources: [URL] {
    let values: [String]
    switch self {
    case .capillaryExchange: values = ["https://pubmed.ncbi.nlm.nih.gov/14078649/"]
    case .valveFlux: values = ["https://openstax.org/books/college-physics-ap-courses-2e/pages/12-1-flow-rate-and-its-relation-to-velocity",
      "https://www.nist.gov/pml/owm/si-units-volume"]
    case .glomerularFiltration: values = ["https://journals.physiology.org/doi/10.1152/advan.00120.2024"]
    case .skinWaterBarrier: values = ["https://pubmed.ncbi.nlm.nih.gov/9740228/",
      "https://openstax.org/books/anatomy-and-physiology-2e/pages/5-1-layers-of-the-skin"]
    case .salivaryDelivery: values = ["https://www.nidcr.nih.gov/health-info/saliva-salivary-gland-disorders",
      "https://pubmed.ncbi.nlm.nih.gov/25680367/"]
    case .tendonElongation: values = ["https://mechref.engr.illinois.edu/sol/axial.html", "https://pubmed.ncbi.nlm.nih.gov/11985759/"]
    case .airwaySplit: values = ["https://openstax.org/books/anatomy-and-physiology-2e/pages/22-3-the-process-of-breathing",
      "https://openstax.org/books/university-physics-volume-2/pages/10-2-resistors-in-series-and-parallel"]
    case .peristalticTravel: values = ["https://www.niddk.nih.gov/health-information/digestive-diseases/digestive-system-how-it-works"]
    case .cochlearFrequency: values = ["https://pubmed.ncbi.nlm.nih.gov/2373794/",
      "https://www.nidcd.nih.gov/research/labs/section-sensory-cell-biology"]
    case .diaphragmDisplacement: values = ["https://openstax.org/books/anatomy-and-physiology-2e/pages/22-3-the-process-of-breathing", "https://pubmed.ncbi.nlm.nih.gov/19521009/"]
    case .cardiacPhaseTime: values = ["https://openstax.org/books/anatomy-and-physiology-2e/pages/19-3-cardiac-cycle", "https://pubmed.ncbi.nlm.nih.gov/15217800/"]
    case .visualAngle: values = ["https://pmc.ncbi.nlm.nih.gov/articles/PMC3878374/", "https://www.nei.nih.gov/eye-health-information/healthy-vision/how-eyes-work"]
    case .serialAbsorption: values = ["https://www.niddk.nih.gov/health-information/digestive-diseases/digestive-system-how-it-works", "https://pmc.ncbi.nlm.nih.gov/articles/PMC1413011/"]
    case .hormoneSignal: values = ["https://openstax.org/books/anatomy-and-physiology-2e/pages/17-2-hormones", "https://pubmed.ncbi.nlm.nih.gov/2823271/"]
    case .immuneComposition: values = ["https://openstax.org/books/anatomy-and-physiology-2e/pages/18-4-leukocytes-and-platelets"]
    case .ductTransit: values = ["https://www.ncbi.nlm.nih.gov/books/NBK538429/", "https://pubmed.ncbi.nlm.nih.gov/31033221/"]
    case .oviductCiliaryCycles: values = ["https://pubmed.ncbi.nlm.nih.gov/11870107/", "https://www.nature.com/articles/s41467-024-55440-2"]
    case .kneeMoment: values = ["https://pubmed.ncbi.nlm.nih.gov/26520912/"]
    case .arterialContinuity: values = ["https://openstax.org/books/university-physics-volume-1/pages/14-5-fluid-dynamics", "https://openstax.org/books/anatomy-and-physiology-2e/pages/20-5-circulatory-pathways"]
    case .glialCapacitance: values = ["https://openstax.org/books/university-physics-volume-2/pages/8-1-capacitors-and-capacitance", "https://openstax.org/books/anatomy-and-physiology-2e/pages/12-2-nervous-tissue"]
    case .colonicWaterBalance: values = ["https://openstax.org/books/anatomy-and-physiology-2e/pages/23-7-chemical-digestion-and-absorption-a-closer-look"]
    case .lymphParticleTransport: values = ["https://openstax.org/books/anatomy-and-physiology-2e/pages/21-1-anatomy-of-the-lymphatic-and-immune-systems"]
    case .endocrineDilution: values = ["https://openstax.org/books/anatomy-and-physiology-2e/pages/17-1-an-overview-of-the-endocrine-system", "https://openstax.org/books/chemistry-2e/pages/3-3-molarity"]
    case .boneSection: values = ["https://openstax.org/books/university-physics-volume-1/pages/12-3-stress-strain-and-elastic-modulus", "https://openstax.org/books/anatomy-and-physiology-2e/pages/6-3-bone-structure"]
    case .retinalConvergence: values = ["https://www.webvision.pitt.edu/book/part-viii-psychophysics-of-vision/visual-acuity/", "https://elifesciences.org/articles/05241"]
    case .muscleShortening: values = ["https://openstax.org/books/anatomy-and-physiology-2e/pages/10-3-muscle-fiber-contraction-and-relaxation"]
    case .keratinGrowth: values = ["https://openstax.org/books/anatomy-and-physiology-2e/pages/5-2-accessory-structures-of-the-skin"]
    case .bladderExpansion: values = ["https://openstax.org/books/anatomy-and-physiology-2e/pages/25-2-gross-anatomy-of-urine-transport", "https://openstax.org/books/prealgebra-2e/pages/c-geometric-formulas"]
    case .vestibularTilt: values = ["https://www.nature.com/articles/19303", "https://www.ncbi.nlm.nih.gov/books/NBK10792/"]
    case .airwayCiliaryClearance: values = ["https://openstax.org/books/anatomy-and-physiology-2e/pages/22-1-organs-and-structures-of-the-respiratory-system", "https://iowaprotocols.medicine.uiowa.edu/protocols/endoscopic-sinus-surgery"]
    case .gastricLiquidEmptying: values = ["https://openstax.org/books/anatomy-and-physiology-2e/pages/23-4-the-stomach", "https://pmc.ncbi.nlm.nih.gov/articles/PMC1159224/"]
    case .bileStorage: values = ["https://openstax.org/books/anatomy-and-physiology-2e/pages/23-6-accessory-organs-in-digestion-the-liver-pancreas-and-gallbladder", "https://www.niddk.nih.gov/health-information/digestive-diseases/digestive-system-how-it-works"]
    case .thoracicCrossSection: values = ["https://sta.uwi.edu/fms/MDSC1001/Thorax_Thoracic_wall.pdf", "https://openstax.org/books/calculus-volume-3/pages/6-4-greens-theorem"]
    case .plateletFragmentCount: values = ["https://openstax.org/books/anatomy-and-physiology-2e/pages/18-4-leukocytes-and-platelets", "https://training.seer.cancer.gov/hematopoietic1/intro-to-blood.html"]
    case .boneRemodelingBalance: values = ["https://openstax.org/books/anatomy-and-physiology-2e/pages/6-3-bone-structure", "https://www.ncbi.nlm.nih.gov/sites/books/NBK279149/"]
    case .cutaneousSebum: values = ["https://openstax.org/books/anatomy-and-physiology-2e/pages/5-2-accessory-structures-of-the-skin", "https://histologyguide.com/EM-view/EM-373-sebaceous-gland/12-photo-1.html"]
    case .ureterDelivery: values = ["https://openstax.org/books/anatomy-and-physiology-2e/pages/25-2-gross-anatomy-of-urine-transport"]
    case .cornealRefraction: values = ["https://openstax.org/books/college-physics-2e/pages/25-3-the-law-of-refraction", "https://pubmed.ncbi.nlm.nih.gov/22488267/"]
    case .externalEarResonance: values = ["https://openstax.org/books/university-physics-volume-1/pages/17-4-normal-modes-of-a-standing-sound-wave", "https://pubmed.ncbi.nlm.nih.gov/2745873/"]
    case .neuralRelayDelays: values = ["https://openstax.org/books/biology-2e/pages/35-2-how-neurons-communicate", "https://openstax.org/books/anatomy-and-physiology-2e/pages/15-1-divisions-of-the-autonomic-nervous-system"]
    case .biliaryFlowTally: values = ["https://openstax.org/books/anatomy-and-physiology-2e/pages/23-6-accessory-organs-in-digestion-the-liver-pancreas-and-gallbladder", "https://pubmed.ncbi.nlm.nih.gov/9096607/"]
    case .parathyroidSignalOccupancy: values = ["https://openstax.org/books/anatomy-and-physiology-2e/pages/17-5-the-parathyroid-glands", "https://pmc.ncbi.nlm.nih.gov/articles/PMC6580154/"]
    case .follicleSurface: values = ["https://openstax.org/books/anatomy-and-physiology-2e/pages/27-2-anatomy-and-physiology-of-the-ovarian-reproductive-system", "https://openstax.org/books/prealgebra-2e/pages/c-geometric-formulas"]
    case .jointArticularArc: values = ["https://openstax.org/books/anatomy-and-physiology-2e/pages/9-6-anatomy-of-selected-synovial-joints", "https://openstax.org/books/precalculus-2e/pages/5-1-angles"]
    case .sweatDuctBalance: values = ["https://pubmed.ncbi.nlm.nih.gov/18653750/", "https://pubmed.ncbi.nlm.nih.gov/7943277/"]
    case .vocalCycles: values = ["https://www.nidcd.nih.gov/news/multimedia/how-does-human-body-produce-voice-and-speech-text-version"]
    case .vertebralSeries: values = ["https://openstax.org/books/anatomy-and-physiology-2e/pages/7-3-the-vertebral-column"]
    case .oralMarkerDilution: values = ["https://openstax.org/books/biology-2e/pages/36-3-taste-and-smell", "https://www.nidcd.nih.gov/health/taste-disorders"]
    case .olfactorySurfaceRetention: values = ["https://pmc.ncbi.nlm.nih.gov/articles/PMC5515430/", "https://www.nidcd.nih.gov/health/smell-disorders"]
    case .circadianLightWindow: values = ["https://nigms.nih.gov/education/fact-sheets/Pages/circadian-rhythms", "https://pmc.ncbi.nlm.nih.gov/articles/PMC2658055/"]
    case .adiposeVolumeShare: values = ["https://histologylab.ctl.columbia.edu/lab03/adipose-connective-tissue/", "https://histology.leeds.ac.uk/home/tissue_types/connective/connective_adipocyte/"]
    case .thymicBranching: values = ["https://www.ncbi.nlm.nih.gov/sites/books/NBK27089/", "https://pmc.ncbi.nlm.nih.gov/articles/PMC3620359/"]
    case .gastricPrecursorBalance: values = ["https://openstax.org/books/anatomy-and-physiology-2e/pages/23-4-the-stomach"]
    case .melaninDistribution: values = ["https://openstax.org/books/anatomy-and-physiology-2e/pages/5-1-layers-of-the-skin", "https://www.cancer.gov/types/skin/hp/skin-genetics-pdq"]
    case .placentalMarker: values = ["https://www.ncbi.nlm.nih.gov/books/NBK53254/", "https://pmc.ncbi.nlm.nih.gov/articles/PMC7613408/"]
    case .renalTubuleRetention: values = ["https://www.niddk.nih.gov/health-information/kidney-disease/kidneys-how-they-work", "https://openstax.org/books/anatomy-and-physiology-2e/pages/25-6-tubular-reabsorption"]
    case .merkelContact: values = ["https://openstax.org/books/anatomy-and-physiology-2e/pages/5-1-layers-of-the-skin", "https://pubmed.ncbi.nlm.nih.gov/24717432/"]
    case .toothEnamelSection: values = ["https://www.nidcr.nih.gov/sites/default/files/2021-04/Open-Wide-and-Trek-Inside.pdf", "https://webpath.med.utah.edu/HISTHTML/NORMAL/NORM194.html"]
    case .mucosalSampling: values = ["https://openstax.org/books/anatomy-and-physiology-2e/pages/21-1-anatomy-of-the-lymphatic-and-immune-systems", "https://histology.leeds.ac.uk/home/lymphoid/prim_sec_lymp_tiss/"]
    case .mammaryDuctDelivery: values = ["https://openstax.org/books/anatomy-and-physiology-2e/pages/28-6-lactation", "https://pmc.ncbi.nlm.nih.gov/articles/PMC3098485/"]
    case .rectalReservoir: values = ["https://www.niddk.nih.gov/health-information/digestive-diseases/digestive-system-how-it-works", "https://openstax.org/books/anatomy-and-physiology-2e/pages/23-5-the-small-and-large-intestines"]
    case .stromalMatrix: values = ["https://openstax.org/books/anatomy-and-physiology-2e/pages/4-3-connective-tissue-supports-and-protects", "https://pmc.ncbi.nlm.nih.gov/articles/PMC8224746/"]
    case .mucusFilmThickness: values = ["https://openstax.org/books/anatomy-and-physiology-2e/pages/22-1-organs-and-structures-of-the-respiratory-system", "https://histology.leeds.ac.uk/home/digestive/small_intestine/"]
    }
    return values.map { URL(string: $0)! }
  }
  static func forEntry(_ id: String) -> Self? { allCases.first { $0.entryIDs.contains(id) } }
  static func control(_ key: String) -> Control? { allCases.lazy.flatMap(\.controls).first { $0.input.key == key } }
  static func resource(_ key: String) -> String? {
    if let control = control(key) { return control.label }
    for model in allCases {
      if key == "model_" + model.rawValue { return model.title }
      if key == "model_" + model.rawValue + "_scope" { return model.scope }
      if key == "model_" + model.rawValue + "_formula" { return model.formula }
    }
    return nil
  }
}
