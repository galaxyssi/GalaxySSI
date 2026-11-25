import SwiftUI

enum GalaxySSIHealthCareAgentPanelText {
  static func get(_ key: String, language: String) -> String {
    func value(_ locale: String, fallback: String) -> String {
      guard let path = Bundle.main.path(forResource: locale, ofType: "lproj"), let bundle = Bundle(path: path) else { return fallback }
      return bundle.localizedString(forKey: key, value: fallback, table: "HealthAssessmentPanel")
    }
    let english = value("en", fallback: key)
    return value(LanguagePolicySettings.resolveInterface(language) == LanguagePolicySettings.zhCN ? "zh-Hans" : "en", fallback: english)
  }

  static func measurement(_ assessment: GalaxySSIHealthCare.Assessment) -> String? {
    let value = assessment.result.trimmingCharacters(in: .whitespacesAndNewlines)
    guard assessment.record != nil, !value.isEmpty else { return nil }
    return [value, assessment.unit.trimmingCharacters(in: .whitespacesAndNewlines)]
      .filter { !$0.isEmpty }.joined(separator: " ")
  }

  static func reportReference(_ assessment: GalaxySSIHealthCare.Assessment) -> String? {
    guard measurement(assessment) != nil else { return nil }
    let reference = assessment.reference.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !reference.isEmpty else { return nil }
    let unit = assessment.unit.trimmingCharacters(in: .whitespacesAndNewlines)
    // Reuse the laboratory-wide notation grammar, not a clinical range or unit conversion.
    if !unit.isEmpty, let kind = GalaxySSIHealthReportedResult.parse(reference, metric: .glucose)?.kind, kind != .qualitative {
      return reference + " " + unit
    }
    return reference
  }
}

struct GalaxySSIHealthCareAgentPanel: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let metric: GalaxySSIHealthMetric
  let assessment: GalaxySSIHealthCare.Assessment

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(metric.title(language: language))
        .font(.subheadline.weight(.semibold))
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("agent-health-care-metric")
      if let value = GalaxySSIHealthCareAgentPanelText.measurement(assessment) {
        (Text(value).font(.footnote.weight(.semibold)) + reference)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("agent-health-care-value")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("agent-health-care-panel")
  }

  private var reference: Text {
    guard let value = GalaxySSIHealthCareAgentPanelText.reportReference(assessment) else { return Text("") }
    return Text(String(format: GalaxySSIHealthCareAgentPanelText.get("health_agent_report_reference", language: language), value))
      .font(.caption)
      .foregroundColor(.secondary)
  }
}
