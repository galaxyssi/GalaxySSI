import SwiftUI

@MainActor
struct GalaxySSIHealthCareContextEditor: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  let concern: GalaxySSIHealthCare.Concern
  @State private var facts = GalaxySSIHealthCareApplicability.Facts()
  @State private var fasting = ""
  @State private var failed = false

  var body: some View {
    Form {
      if scene == .active {
        truth(.adult, selection: $facts.adult)
        truth(.pregnant, selection: $facts.pregnant)
        truth(.diabetes, selection: $facts.diabetes)
        truth(.illnessMedication, selection: $facts.illnessMedication)
        Picker(t("field.specimen", "Specimen"), selection: $facts.specimen) {
          ForEach(GalaxySSIHealthCareApplicability.Specimen.allCases, id: \.rawValue) {
            Text(t("value." + $0.rawValue, $0.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)).tag($0)
          }
        }
        Picker(t("field.collection_condition", "Collection condition"), selection: $facts.collection) {
          ForEach(GalaxySSIHealthCareApplicability.Collection.allCases, id: \.rawValue) {
            Text(t("value." + $0.rawValue, $0.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)).tag($0)
          }
        }
        TextField(t("field.fasting", "Confirmed fasting hours"), text: $fasting).keyboardType(.numberPad)
        Button(t("save_context", "Confirm these facts"), action: save)
          .disabled(!fasting.isEmpty && Int(fasting).map { (0...72).contains($0) } != true)
        if failed { Text(t("stale_context", "The measurement changed. Reopen its context to confirm.")) }
      }
    }
    .navigationTitle(t("context", "Confirmed measurement facts"))
    .onAppear {
      if let existing = GalaxySSIHealthCareApplicability.currentFacts(concern) {
        facts = existing
        fasting = existing.fastingHours.map { String($0) } ?? ""
      }
    }
    .onChange(of: scene) { phase in
      if phase != .active { facts = .init(); fasting = ""; dismiss() }
    }
  }

  private func truth(_ field: GalaxySSIHealthCareApplicability.Field,
                     selection: Binding<GalaxySSIHealthCareApplicability.Truth>) -> some View {
    Picker(GalaxySSIHealthCareApplicabilityText.field(field, language: language), selection: selection) {
      ForEach(GalaxySSIHealthCareApplicability.Truth.allCases, id: \.rawValue) {
        Text(t("value." + $0.rawValue, $0.rawValue.capitalized)).tag($0)
      }
    }
  }
  private func save() {
    guard scene == .active, fasting.isEmpty || Int(fasting).map({ (0...72).contains($0) }) == true else { return }
    facts.fastingHours = fasting.isEmpty ? nil : Int(fasting)
    do { try records.setLocalCareContext(concern, applicability: .unknown, facts: facts); dismiss() }
    catch { failed = true }
  }
  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSIHealthCareApplicabilityText.string(key, fallback, language: language)
  }
}

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
