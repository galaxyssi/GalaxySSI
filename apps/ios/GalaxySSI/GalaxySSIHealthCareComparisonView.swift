import SwiftUI

@MainActor
struct GalaxySSIHealthCareComparisonSection: View {
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  let id: UUID
  let metric: GalaxySSIHealthMetric
  @State private var pair: GalaxySSIHealthCareComparison.Pair?
  @State private var context: GalaxySSIHealthCare.Context?

  var body: some View {
    Group {
      if scene == .active, let pair {
        Section(t("title", "Measurement comparison")) {
          Text(kind(pair.kind)).font(.headline)
          sample(pair.before, title: pair.kind == .recordCorrection
            ? t("old_revision", "Earlier revision on this device") : t("before", "Before"),
            confirmedContext: pair.previousContext)
          sample(pair.after, title: t("after", "After"), confirmedContext: context)
          if !pair.changes.isEmpty {
            Text(t("arithmetic", "Arithmetic changes only")).font(.subheadline.weight(.semibold))
            ForEach(pair.changes, id: \.field.rawValue) { change in
              LabeledContentCare(label: field(change.field), value: change.delta + " " + change.unit)
            }
          }
          ForEach(pair.gaps(currentContext: context), id: \.rawValue) { gap in
            Text(gapLabel(gap)).foregroundColor(.secondary)
          }
        }
      }
    }
    .onAppear(perform: reload)
    .onChange(of: scene) { _ in reload() }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) {
      if $0.object as? String == records.owner { reload() }
    }
  }

  private func reload() {
    let now = Date()
    guard scene == .active, let archive = try? records.load(), archive.localCareAllowed == true,
          let concern = archive.localCare?.current[metric.rawValue], concern.id == id,
          let saved = concern.comparison else { pair = nil; context = nil; return }
    let readings = archive.current.filter { $0.metric == metric && $0.isValid && $0.measuredAt <= now }
    guard GalaxySSIHealthCareComparison.reconcile(readings, prior: concern).1 == saved
    else { pair = nil; context = nil; return }
    pair = saved
    context = concern.context?.record == saved.after.record ? concern.context : nil
  }

  private func sample(_ sample: GalaxySSIHealthCareComparison.Sample, title: String,
                      confirmedContext: GalaxySSIHealthCare.Context?) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).font(.caption).foregroundColor(.secondary)
      Text(sample.result + " " + sample.unit)
      if let pulse = sample.pulse {
        LabeledContentCare(label: field(.pulse), value: GalaxySSIHealthCareComparison.Sample.number(pulse) + " bpm")
      }
      Text(sample.measuredAt, format: .dateTime).foregroundColor(.secondary)
      if !sample.reference.isBlank {
        LabeledContentCare(label: t("reference", "Report reference"), value: sample.reference)
      }
      if !sample.condition.isBlank { Text(sample.condition).font(.caption).foregroundColor(.secondary) }
      if metric == .glucose {
        let state = confirmedContext?.record == sample.record ? confirmedContext?.applicability : nil
        Text(contextLabel(state)).font(.caption).foregroundColor(.secondary)
      }
    }
  }

  private func kind(_ kind: GalaxySSIHealthCareComparison.Kind) -> String {
    switch kind {
    case .newResult: return t("new_result", "New measurement result")
    case .recordCorrection: return t("record_correction", "Correction to an existing measurement")
    case .historyChanged: return t("history_changed", "Measurement history changed")
    }
  }

  private func contextLabel(_ context: GalaxySSIHealthCare.Context.Applicability?) -> String {
    switch context {
    case .applicable: return t("context_applicable", "Fasting plasma screening context confirmed")
    case .excluded: return t("context_excluded", "Screening context does not apply")
    default: return t("context_unconfirmed", "Measurement context not confirmed")
    }
  }

  private func field(_ field: GalaxySSIHealthCareComparison.Field) -> String {
    switch field {
    case .value: return t("field_value", "Value")
    case .systolic: return t("field_systolic", "Systolic")
    case .diastolic: return t("field_diastolic", "Diastolic")
    case .pulse: return t("field_pulse", "Pulse")
    }
  }

  private func gapLabel(_ gap: GalaxySSIHealthCareComparison.Gap) -> String {
    GalaxySSIHealthCareComparisonText.gap(gap, language: language)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.comparison." + key, fallback: fallback, language: language)
  }
}

enum GalaxySSIHealthCareComparisonText {
  static func gap(_ gap: GalaxySSIHealthCareComparison.Gap, language: String) -> String {
    let label: String
    switch gap {
    case .unitsDiffer: label = "Measurement units differ."
    case .conditionsDiffer: label = "Recorded conditions differ."
    case .conditionsUnknown: label = "Some measurement conditions are unknown."
    case .sourceDiffers: label = "The measurement sources differ."
    case .referenceDiffers: label = "The report references differ."
    case .nonExactResult: label = "Not all results are exact numbers."
    case .contextUnconfirmed: label = "Clinical context is not confirmed for both measurements."
    case .contextDiffers: label = "The separately confirmed contexts differ."
    case .methodUnverified: label = "Method comparability and clinical change are not established."
    }
    return GalaxySSILocalization.string("galaxyssi.health.comparison.gap." + gap.rawValue, fallback: label, language: language)
  }
}

private struct LabeledContentCare: View {
  let label: String
  let value: String
  var body: some View { Text(label + ": " + value).font(.subheadline) }
}
