import SwiftUI

@MainActor
struct GalaxySSIHealthCarePrioritySection: View {
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  let concernID: UUID
  @State private var warning: GalaxySSIHealthCarePriority.Warning?
  @State private var facts: GalaxySSIHealthCareApplicability.Facts?
  @State private var acknowledged = false
  @State private var failed = false

  var body: some View {
    Group {
      if scene == .active, let warning {
        Section {
          GalaxySSIHealthCarePriorityNotice(warning: warning, facts: facts)
          if acknowledged {
            Text(t("acknowledged", "Marked as reviewed for this reading")).font(.caption).foregroundColor(.secondary)
          } else {
            Button(t("acknowledge", "Mark this reading as reviewed")) {
              do { try records.acknowledgeLocalCareBloodPressure(warning); reload() }
              catch { failed = true; reload() }
            }
          }
          if failed { Text(t("changed", "The recorded reading has changed.")) }
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
    guard scene == .active, let archive = try? records.load(),
          let (concern, latest) = GalaxySSIHealthRecords.currentCareBloodPressureWarning(archive),
          concern.id == concernID else { warning = nil; facts = nil; acknowledged = false; failed = false; return }
    warning = latest
    facts = GalaxySSIHealthCareApplicability.currentFacts(concern)
    acknowledged = archive.localCare?.acknowledgedBloodPressure == latest.record
  }

  private func t(_ key: String, _ fallback: String) -> String { GalaxySSIHealthCarePriorityText.text(key, fallback, language: language) }
}

struct GalaxySSIHealthCarePriorityNotice: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let warning: GalaxySSIHealthCarePriority.Warning
  let facts: GalaxySSIHealthCareApplicability.Facts?
  var compact = false

  private var adultGuidanceAppliesPossibly: Bool { facts?.adult != .no && facts?.pregnant != .yes }

  var body: some View {
    VStack(alignment: .leading, spacing: compact ? 4 : 8) {
      Label(t("title", "Review this recorded blood pressure first"), systemImage: "exclamationmark.triangle")
        .font(compact ? .footnote.weight(.semibold) : .headline)
        .foregroundColor(.primary)
      Text(warning.measuredAt, format: .dateTime).font(.caption).foregroundColor(.secondary)
      if !compact {
        Text(warning.displayedValue).font(.headline.monospacedDigit())
        Text(t("threshold", "The recorded systolic value is above 180 or the diastolic value is above 120 mmHg (or its equivalent). This is not a diagnosis."))
      }
      if adultGuidanceAppliesPossibly {
        Text(t("emergency", "For an adult who is not pregnant: if the pressure is currently this high with chest discomfort, trouble breathing, back pain, numbness, weakness, changes in vision, or difficulty speaking, call local emergency services now. Do not wait for the Agent."))
          .font(compact ? .caption : .body.weight(.semibold))
          .foregroundColor(.primary)
        if !compact {
          Text(t("recheck", "For a current reading without new concerning symptoms, wait at least a minute and measure again. If it remains this high, contact a health professional promptly. Do not change medication on your own."))
        }
      }
      if !compact || !adultGuidanceAppliesPossibly {
        Text(t("scope", "This cutoff is for nonpregnant adults. Pregnancy and children require different assessment; seek prompt professional advice instead of relying on this cutoff."))
          .font(compact ? .caption : .body)
      }
      if !adultGuidanceAppliesPossibly {
        Text(t("different_scope", "If there are new severe symptoms, seek emergency help now."))
          .font(compact ? .caption : .body.weight(.semibold))
      }
      if !compact {
        Text(t("history", "Check the date. A past reading alone does not establish a current emergency. The app does not monitor symptoms or detect every dangerous condition."))
          .foregroundColor(.secondary)
        Link(t("source", "American Heart Association guidance (reviewed August 2025)"), destination: GalaxySSIHealthCarePriority.source)
      }
    }
    .accessibilityElement(children: .contain)
  }

  private func t(_ key: String, _ fallback: String) -> String { GalaxySSIHealthCarePriorityText.text(key, fallback, language: language) }
}

private enum GalaxySSIHealthCarePriorityText {
  static func text(_ key: String, _ fallback: String, language: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.priority." + key, fallback: fallback, language: language)
  }
}
