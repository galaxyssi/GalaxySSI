import SwiftUI

struct GalaxySSIHealthCareTargetSummary: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let component: GalaxySSIHealthCareTarget.Component
  let bounds: GalaxySSIHealthCareTarget.Bounds
  let unit: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(componentTitle).font(.caption).foregroundColor(.secondary)
      Text(bounds.description + " " + unit).font(.body.monospacedDigit())
    }
  }

  private var componentTitle: String {
    let fallback: String
    switch component {
    case .value: fallback = "Measurement value"
    case .systolic: fallback = "Systolic pressure"
    case .diastolic: fallback = "Diastolic pressure"
    }
    return GalaxySSIHealthCareTargetText.text("component." + component.rawValue, fallback, language: language)
  }
}

enum GalaxySSIHealthCareTargetText {
  static func text(_ key: String, _ fallback: String, language: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.target_review." + key, fallback: fallback, language: language)
  }

  static func comparison(_ value: GalaxySSIHealthCareTarget.Comparison, language: String) -> String {
    let fallback: String
    switch value {
    case .reviewRequired: fallback = "The measurement or context needs review before comparing."
    case .notComparable: fallback = "No exact result for this component in the target unit."
    case .below: fallback = "This component is below the confirmed bound."
    case .within: fallback = "This component is within the confirmed bounds. This does not establish clinical stability."
    case .above: fallback = "This component is above the confirmed bound."
    }
    return text("comparison." + value.rawValue, fallback, language: language)
  }
}
