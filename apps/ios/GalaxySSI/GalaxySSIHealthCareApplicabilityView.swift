import SwiftUI

struct GalaxySSIHealthCareApplicabilityDetails: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let action: GalaxySSIHealthCarePlan.Action
  let concern: GalaxySSIHealthCare.Concern?

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      if let concern {
        let status = GalaxySSIHealthCareApplicability.status(action.applicability, concern: concern)
        Text(t("status." + status.rawValue, statusLabel(status))).font(.caption.weight(.semibold))
      }
      if let review = action.applicability {
        ForEach(review.checks) { check in
          let field = GalaxySSIHealthCareApplicabilityText.field(check.field, language: language)
          let symbol = check.comparison == .atLeast ? ">=" : check.comparison == .atMost ? "<=" : "="
          let result = concern.map { GalaxySSIHealthCareApplicability.result(check, concern: $0) }
          Text(field + " " + symbol + " " + t("value." + check.expected, check.expected) + " · " +
               source(check.sourceIndex) + (result.map { " · " + t("result." + $0.rawValue, $0.rawValue.capitalized) } ?? ""))
            .font(.caption)
        }
        ForEach(Array(review.missingInformation.enumerated()), id: \.offset) { _, detail in
          Text(t("missing", "Missing information") + ": " + detail).font(.caption)
        }
        ForEach(Array(review.conflicts.enumerated()), id: \.offset) { _, conflict in
          Text(t("conflict", "Source conflict") + " (" + conflict.sourceIndices.map(source).joined(separator: ", ") + ")")
            .font(.caption.weight(.semibold))
          Text(conflict.detail).font(.caption)
          Text(t("next_step", "Next step") + ": " + conflict.nextStep).font(.caption)
        }
      }
    }.foregroundColor(.secondary)
  }

  private func source(_ index: Int) -> String {
    String(format: t("source_number", "Source %lld"), Int64(index) + 1)
  }
  private func statusLabel(_ status: GalaxySSIHealthCareApplicability.Status) -> String {
    switch status {
    case .missingReview: return "No applicability review"
    case .discussionOnly: return "Discussion only"
    case .matched: return "Declared requirements match saved facts; not clinically validated"
    case .needsContext: return "Requires missing context"
    case .mismatch: return "Saved facts do not match"
    case .conflict: return "Unresolved source conflict"
    }
  }
  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSIHealthCareApplicabilityText.string(key, fallback, language: language)
  }
}

private enum GalaxySSIHealthCareApplicabilityText {
  static func string(_ key: String, _ fallback: String, language: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.applicability." + key, fallback: fallback, language: language)
  }
  static func field(_ field: GalaxySSIHealthCareApplicability.Field, language: String) -> String {
    let label: String
    switch field {
    case .metric: label = "Metric"
    case .unit: label = "Unit"
    case .collectionCondition: label = "Collection condition"
    case .adult: label = "Adult"
    case .pregnant: label = "Pregnant"
    case .diabetes: label = "Known diabetes"
    case .specimen: label = "Specimen"
    case .fasting: label = "Confirmed fasting hours"
    case .illnessMedication: label = "Illness or medication may affect this result"
    }
    return string("field." + field.rawValue, label, language: language)
  }
}
