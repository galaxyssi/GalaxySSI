import Foundation

enum GalaxySSIHealthAtlasAgingTopic: String, CaseIterable, Codable, Sendable {
  case genome, telomeres, epigenetics, proteins, autophagy, nutrients, mitochondria, senescence
  case stem_cells, signaling, inflammation, dysbiosis
  static let source = URL(string: "https://pubmed.ncbi.nlm.nih.gov/36599349/")!
  var exampleID: String {
    switch self {
    case .genome: return "epidermis"
    case .telomeres: return "skin-organ"
    case .epigenetics: return "cell-hepatocyte"
    case .proteins: return "cell-neuron"
    case .autophagy: return "cell-skeletal-myocyte"
    case .nutrients: return "pancreatic-islets"
    case .mitochondria: return "cell-cardiomyocyte"
    case .senescence: return "cell-t-cell"
    case .stem_cells: return "cell-hematopoietic-stem-cell"
    case .signaling: return "cell-fibroblast"
    case .inflammation: return "cell-macrophage"
    case .dysbiosis: return "colon"
    }
  }
  var study: Study? {
    switch self { case .telomeres: return .telomeres; case .senescence: return .tcells; default: return nil }
  }
  enum Study: String {
    case telomeres, tcells
    var source: URL {
      URL(string: self == .telomeres ? "https://pmc.ncbi.nlm.nih.gov/articles/PMC3615479/" : "https://pubmed.ncbi.nlm.nih.gov/19485966/")!
    }
    func text(_ field: String, language: String) -> String {
      GalaxySSIHealthAtlasAgingSelection.text(field + "_" + rawValue, language: language)
    }
  }
  static func forEntry(_ id: String) -> Self {
    if let topic = allCases.first(where: { $0.exampleID == id }) { return topic }
    switch id {
    case "heart", "cardio", "muscle": return .mitochondria
    case "skin": return .telomeres
    case "endocrine", "pancreas", "cell-pancreatic-beta-cell": return .nutrients
    case "immune", "thymus": return .senescence
    case "bone-marrow": return .stem_cells
    case "nervous", "brain": return .proteins
    case "gut", "digestive", "large-intestine": return .dysbiosis
    default: return .genome
    }
  }
}

/// Public conceptual selection, isolated from physiology controls and health records.
struct GalaxySSIHealthAtlasAgingSelection: Codable, Equatable, Sendable {
  let topic: GalaxySSIHealthAtlasAgingTopic
  let step: Int
  init(topic: GalaxySSIHealthAtlasAgingTopic) { self.topic = topic; step = 0 }
  init?(topic: GalaxySSIHealthAtlasAgingTopic, step: Int) {
    guard (0..<4).contains(step) else { return nil }
    self.topic = topic; self.step = step
  }
  static func resolved(_ saved: Self?, entryID: String) -> Self {
    if let saved, (0..<4).contains(saved.step) { return saved }
    return Self(topic: .forEntry(entryID))
  }
  static func text(_ key: String, language: String) -> String {
    GalaxySSIHealthAtlasText.get("health_atlas_aging_" + key, language)
  }
  func title(language: String) -> String { Self.text("topic_" + topic.rawValue, language: language) }
  func explanation(language: String) -> String { Self.text("explain_" + topic.rawValue, language: language) }
  func stages(language: String) -> [String] {
    (0..<4).map { Self.text("steps_" + topic.rawValue + "_" + String($0), language: language) }
  }
  func stageLabel(language: String) -> String {
    String(format: GalaxySSIHealthAtlasText.get("health_atlas_stage", language),
      Int64(min(3, max(0, step)) + 1), Int64(4), stages(language: language)[min(3, max(0, step))])
  }
  func context(language: String) -> String {
    var lines = [Self.text("scope", language: language), title(language: language),
      Self.text("diagram_scope", language: language), stageLabel(language: language), explanation(language: language)]
    if let study = topic.study {
      lines += ["study", "sample", "result", "limits"].map { study.text($0, language: language) }
      lines.append(study.source.absoluteString)
    }
    return lines.joined(separator: "\n")
  }
}
