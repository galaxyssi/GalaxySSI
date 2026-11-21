import Foundation

enum GalaxySSIHealthAtlasPhysiologyText {
  static func string(_ key: String, language: String) -> String {
    let resource = "health_atlas_" + key
    return GalaxySSILocalization.string(resource, fallback: english[resource] ?? resource, language: language)
  }
  static func number(_ value: Double, digits: Int = 2, language: String) -> String {
    let format = NumberFormatter()
    format.locale = GalaxySSILocalization.interfaceLocale(language: language)
    format.numberStyle = .decimal
    format.maximumFractionDigits = digits
    return format.string(from: NSNumber(value: value)) ?? String(value)
  }
  static func input(_ model: GalaxySSIHealthAtlasPhysiology, index: Int, language: String) -> String {
    let spec = model.kind.inputs[index]
    return string(spec.key, language: language) + ": " + number(model.input(index), language: language) + " " + spec.unit
  }
  static func result(_ model: GalaxySSIHealthAtlasPhysiology, language: String) -> String {
    string("model_" + model.kind.rawValue, language: language) + ": " + number(model.result, language: language) + " " + model.kind.unit
  }
  static func companion(_ model: GalaxySSIHealthAtlasPhysiology, language: String) -> String {
    let key = model.kind == .ventilation ? "model_total_ventilation" : model.kind == .renal ? "model_reabsorbed_amount" : "model_concentration_ratio"
    return String(format: string(key, language: language),
      number(model.companionValue, digits: model.kind == .potassium ? 4 : 2, language: language))
  }
  static func context(_ model: GalaxySSIHealthAtlasPhysiology, language: String) -> String {
    ([string("model_synthetic", language: language), string("model_" + model.kind.rawValue + "_scope", language: language)] +
      model.inputs.indices.map { input(model, index: $0, language: language) } +
      [result(model, language: language), companion(model, language: language),
       string("model_" + model.kind.rawValue + "_formula", language: language), model.kind.source.absoluteString])
      .joined(separator: "\n")
  }
  private static let english: [String: String] = [
    "health_atlas_model_axis": "%1$@ (%2$@) · Other inputs held fixed",
    "health_atlas_model_concentration_ratio": "Outside / inside concentration ratio: %1$@",
    "health_atlas_model_dead_space": "Dead-space volume",
    "health_atlas_model_filtered": "Filtered load",
    "health_atlas_model_inside": "Potassium inside the cell",
    "health_atlas_model_outside": "Potassium outside the cell",
    "health_atlas_model_potassium": "Potassium equilibrium potential",
    "health_atlas_model_potassium_formula": "Eₖ = (RT/F) × ln(K outside / K inside); T = 310.15 K, charge = +1. Result shown in mV.",
    "health_atlas_model_potassium_scope": "An ideal membrane permeable only to potassium at 37 °C, using concentrations as activities. This is not a real neuron’s resting potential or an action-potential simulation; other ions, pumps and permeability changes are excluded.",
    "health_atlas_model_reabsorbed": "Reabsorbed fraction",
    "health_atlas_model_reabsorbed_amount": "Reabsorbed amount: %1$@ mg/min",
    "health_atlas_model_renal": "Solute excretion rate",
    "health_atlas_model_renal_formula": "Excretion = filtered load − reabsorbed amount + secreted amount.",
    "health_atlas_model_renal_scope": "Whole-nephron mass balance for an unspecified, freely filtered solute. Reabsorption is a fraction of the filtered load; secretion is a separate net addition. It is not urine volume, GFR, a drug dose or the isolated function of one tubular cell.",
    "health_atlas_model_secreted": "Net tubular secretion",
    "health_atlas_model_source": "Model assumptions and source",
    "health_atlas_model_synthetic": "Teaching inputs · Not personal measurements",
    "health_atlas_model_total_ventilation": "Total minute ventilation: %1$@ L/min",
    "health_atlas_model_ventilation": "Alveolar ventilation",
    "health_atlas_model_ventilation_formula": "Alveolar ventilation = respiratory rate × (tidal volume − dead space) ÷ 1,000.",
    "health_atlas_model_ventilation_scope": "Whole-lung ventilation at fixed inputs. Dead space is the part of each breath not exchanging gas. This does not calculate blood oxygen, carbon dioxide or a ventilator setting.",
    "health_atlas_rate": "Respiratory rate",
    "health_atlas_reset": "Reset view",
    "health_atlas_tidal": "Tidal volume",
  ]
}
