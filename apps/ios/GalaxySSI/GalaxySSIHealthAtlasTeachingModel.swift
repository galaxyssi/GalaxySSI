import Foundation

/// Android #4397 synthetic teaching examples, never patient measurements or estimates.
enum GalaxySSIHealthAtlasTeachingModel: String, CaseIterable, Sendable {
  case capillaryExchange, valveFlux, glomerularFiltration, skinWaterBarrier, salivaryDelivery
  case tendonElongation, airwaySplit, peristalticTravel, cochlearFrequency

  struct Control: Sendable {
    let input: GalaxySSIHealthAtlasPhysiology.Input
    let label: String
    var digits: Int = 2
  }
  var inputs: [GalaxySSIHealthAtlasPhysiology.Input] { controls.map(\.input) }
  var axis: Int {
    switch self {
    case .valveFlux, .skinWaterBarrier, .airwaySplit, .peristalticTravel: return 1
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
    }
  }
  var digits: Int { self == .glomerularFiltration ? 1 : self == .tendonElongation ? 3 : 2 }
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
