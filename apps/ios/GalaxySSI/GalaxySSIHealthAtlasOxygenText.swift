import Foundation

enum GalaxySSIHealthAtlasOxygenText {
  static func string(_ key: String, language: String) -> String? {
    let resource = "health_atlas_" + key
    guard let fallback = english[resource] else { return nil }
    return GalaxySSILocalization.string(resource, fallback: fallback, language: language)
  }
  private static let english: [String: String] = [
    "health_atlas_model_hemoglobin": "Hemoglobin concentration",
    "health_atlas_model_oxygen": "Hemoglobin oxygen saturation",
    "health_atlas_model_oxygen_binding_source": "Oxygen binding \u{b7} Hill equation and limits",
    "health_atlas_model_oxygen_content": "Oxygen content: %1$@ mL O\u{2082}/dL blood\nBound: %2$@ \u{b7} Dissolved: %3$@ mL O\u{2082}/dL",
    "health_atlas_model_oxygen_content_source": "Oxygen content \u{b7} Equation and units",
    "health_atlas_model_oxygen_formula": "S = 1 / (1 + (P50 / PO\u{2082})^2.7); saturation = S \u{d7} 100%. At PO\u{2082} = 0, S = 0. Oxygen content = 1.34 \u{d7} (Hb / 10) \u{d7} S + 0.0031 \u{d7} PO\u{2082}. Hb is in g/L and pressures in mmHg; content is in mL O\u{2082}/dL blood.",
    "health_atlas_model_oxygen_pressure": "Oxygen partial pressure",
    "health_atlas_model_oxygen_scope": "Simplified Hill equilibrium model with fixed exponent 2.7, most reliable around 20\u{2013}98% saturation. P50 changes affinity; hemoglobin changes oxygen content, not this saturation curve. Control ranges are teaching ranges, not clinical reference intervals. pH, CO\u{2082}, temperature and abnormal hemoglobins are not modeled separately. Not a pulse-ox reading, oxygen-delivery estimate or treatment recommendation.",
    "health_atlas_model_p50": "P50 \u{b7} Pressure at half saturation",
    "health_atlas_model_process_note": "The following process steps are qualitative illustrations, separate from the numerical model; animation speed is not biological timing.",
  ]
}
