import SwiftUI

@MainActor
struct GalaxySSIHealthCareTargetSection: View {
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  let concern: GalaxySSIHealthCare.Concern

  @State private var descriptive = ""
  @State private var source = ""
  @State private var rationale = ""
  @State private var confirmedBy = ""
  @State private var lower = ""
  @State private var upper = ""
  @State private var includeLower = true
  @State private var includeUpper = true
  @State private var numeric = false
  @State private var component = GalaxySSIHealthCareTarget.Component.value
  @State private var editing = false
  @State private var review: Review?
  @State private var revoke: GalaxySSIHealthCare.Concern?
  @State private var failed = false
  @State private var comparison: GalaxySSIHealthCareTarget.Comparison = .reviewRequired

  private struct Review: Identifiable {
    let id = UUID()
    let concern: GalaxySSIHealthCare.Concern
    let bounds: GalaxySSIHealthCareTarget.Bounds?
    let component: GalaxySSIHealthCareTarget.Component
    let value: String
    let source: String
    let rationale: String
    let confirmedBy: String
  }

  var body: some View {
    Section(t("title", "Confirmed individual target")) {
      if let target = concern.target {
        Text(target.value)
        if let numeric = target.numeric {
          Text(componentTitle(numeric.component)).foregroundColor(.secondary)
          Text(comparisonText(comparison)).font(.caption)
        }
        Text(target.source)
        Text(target.rationale)
        Text(target.confirmedBy)
        Text(target.confirmedAt, style: .date)
        Button(t("revoke", "Revoke target"), role: .destructive) { revoke = concern }
      }
      DisclosureGroup(t("edit", "Record an individual target"), isExpanded: $editing) {
        let components = GalaxySSIHealthCareTarget.components(for: concern.metric)
        if !components.isEmpty, concern.assessment.record != nil, !concern.assessment.unit.isEmpty {
          Toggle(t("numeric", "Use numeric bounds"), isOn: $numeric)
          if numeric {
            Picker(t("component", "Measurement component"), selection: $component) {
              ForEach(components, id: \.rawValue) { Text(componentTitle($0)).tag($0) }
            }
            Text(concern.assessment.unit).foregroundColor(.secondary)
            TextField(t("lower", "Lower bound (optional)"), text: $lower).keyboardType(.decimalPad)
            if !lower.isBlank { Toggle(t("include_lower", "Include the lower bound"), isOn: $includeLower) }
            TextField(t("upper", "Upper bound (optional)"), text: $upper).keyboardType(.decimalPad)
            if !upper.isBlank { Toggle(t("include_upper", "Include the upper bound"), isOn: $includeUpper) }
          }
        }
        if !numeric { TextField(t("title", "Confirmed individual target"), text: $descriptive) }
        TextField(t("source", "Target source"), text: $source)
        TextField(t("reason", "Reason"), text: $rationale)
        TextField(t("confirmed_by", "Confirmed by"), text: $confirmedBy)
        Button(t("review", "Review target"), action: prepareReview)
          .disabled([source, rationale, confirmedBy].contains(where: \.isBlank) ||
                    (numeric ? lower.isBlank && upper.isBlank : descriptive.isBlank))
      }
      if failed { Text(t("unavailable", "The target is invalid or its measurement has changed.")) }
    }
    .onAppear { component = GalaxySSIHealthCareTarget.components(for: concern.metric).first ?? .value; refreshComparison() }
    .onDisappear(perform: clear)
    .onChange(of: scene) { if $0 != .active { clear() }; refreshComparison() }
    .onChange(of: concern.revision) { _ in clear(); refreshComparison() }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) {
      if $0.object as? String == records.owner {
        if let review, !records.isCurrentLocalCareTargetReview(review.concern) { clear() }
        refreshComparison()
      }
    }
    .sheet(item: $review) { candidate in
      NavigationView {
        List {
          if scene == .active {
            if candidate.bounds != nil { Text(componentTitle(candidate.component)) }
            Text(candidate.value)
            Text(candidate.source)
            Text(candidate.rationale)
            Text(candidate.confirmedBy)
            Text(t("scope", "Your confirmation records this target; the app has not verified clinician approval."))
              .font(.footnote).foregroundColor(.secondary)
            Button(t("confirm", "Confirm target")) { confirm(candidate) }
          }
        }
        .navigationTitle(t("review", "Review target"))
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(t("cancel", "Cancel")) { review = nil } } }
      }.navigationViewStyle(.stack)
    }
    .confirmationDialog(t("revoke", "Revoke target"), isPresented: Binding(
      get: { revoke != nil }, set: { if !$0 { revoke = nil } }), presenting: revoke) { candidate in
        Button(t("revoke", "Revoke target"), role: .destructive) {
          guard scene == .active else { return }
          do { try records.revokeLocalCareTarget(candidate); clear() }
          catch { failed = true }
        }
    }
  }

  private func prepareReview() {
    guard scene == .active, records.isCurrentLocalCareTargetReview(concern) else { failed = true; return }
    do {
      let bounds = numeric ? try GalaxySSIHealthCareTarget.Bounds(low: lower, high: upper,
        lowInclusive: includeLower, highInclusive: includeUpper) : nil
      if let bounds, !GalaxySSIHealthCareTarget.canConfirm(bounds, component: component, concern: concern) {
        throw GalaxySSIHealthRecords.Failure.invalid
      }
      review = .init(concern: concern, bounds: bounds, component: component,
        value: bounds.map { $0.description + " " + concern.assessment.unit } ?? descriptive,
        source: source, rationale: rationale, confirmedBy: confirmedBy)
      failed = false
    } catch { failed = true }
  }

  private func confirm(_ candidate: Review) {
    guard scene == .active, review?.id == candidate.id, concern == candidate.concern else {
      clear(); return
    }
    do {
      if let bounds = candidate.bounds {
        try records.confirmLocalCareNumericTarget(candidate.concern, component: candidate.component, bounds: bounds,
          source: candidate.source, rationale: candidate.rationale, confirmedBy: candidate.confirmedBy)
      } else {
        try records.setLocalCareTarget(candidate.concern, target: .init(value: candidate.value,
          source: candidate.source, rationale: candidate.rationale, confirmedBy: candidate.confirmedBy, confirmedAt: Date()))
      }
      clear()
    } catch { review = nil; failed = true }
  }

  private func clear() {
    editing = false; review = nil; revoke = nil; failed = false
    descriptive = ""; source = ""; rationale = ""; confirmedBy = ""; lower = ""; upper = ""
    numeric = false; includeLower = true; includeUpper = true
    component = GalaxySSIHealthCareTarget.components(for: concern.metric).first ?? .value
  }

  private func refreshComparison() {
    comparison = scene == .active && concern.target?.numeric != nil
      ? records.localCareTargetComparison(concern) : .reviewRequired
  }

  private func componentTitle(_ component: GalaxySSIHealthCareTarget.Component) -> String {
    switch component {
    case .value: return t("component.value", "Measurement value")
    case .systolic: return t("component.systolic", "Systolic pressure")
    case .diastolic: return t("component.diastolic", "Diastolic pressure")
    }
  }

  private func comparisonText(_ comparison: GalaxySSIHealthCareTarget.Comparison) -> String {
    switch comparison {
    case .reviewRequired: return t("comparison.reviewRequired", "Review the changed measurement or context before comparing.")
    case .notComparable: return t("comparison.notComparable", "No exact result for this component in the target unit.")
    case .below: return t("comparison.below", "This component is below the confirmed bound.")
    case .within: return t("comparison.within", "This component is within the bounds. This does not establish clinical stability.")
    case .above: return t("comparison.above", "This component is above the confirmed bound.")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.target_review." + key, fallback: fallback, language: language)
  }
}
