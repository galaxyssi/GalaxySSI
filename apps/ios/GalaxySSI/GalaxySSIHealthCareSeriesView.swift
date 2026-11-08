import SwiftUI
import UIKit

@MainActor
struct GalaxySSIHealthCareSeriesLink: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  let id: UUID
  let metric: GalaxySSIHealthMetric

  var body: some View {
    NavigationLink {
      GalaxySSIHealthCareSeriesView(records: records, id: id, metric: metric)
    } label: {
      Label(GalaxySSIHealthCareText.string("series_title", "Measurement history", language: language),
            systemImage: "list.bullet")
    }
  }
}

@MainActor
private struct GalaxySSIHealthCareSeriesView: View {
  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  let id: UUID
  let metric: GalaxySSIHealthMetric
  @State private var page: GalaxySSIHealthCareSeries.Page?
  @State private var start: GalaxySSIHealthCareSeries.Cursor?
  @State private var changed = false

  var body: some View {
    List {
      if scene == .active, store.profile.identityFingerprint == records.owner {
        if let page {
          Section {
            Text(t("series_notice", "Numeric agreement does not establish clinical stability."))
              .foregroundColor(.secondary)
            ForEach(page.rows) { row in
              VStack(alignment: .leading, spacing: 5) {
                Text(row.measuredAt, style: .date).font(.caption).foregroundColor(.secondary)
                Text(row.measuredAt, style: .time).font(.caption).foregroundColor(.secondary)
                Text([row.result, row.unit].filter { !$0.isEmpty }.joined(separator: " "))
                  .font(.headline)
                ForEach(row.gaps, id: \.rawValue) { gap in
                  Text(gapLabel(gap))
                    .font(.caption).foregroundColor(.secondary)
                }
              }
            }
            if let next = page.next {
              Button(t("series_more", "Earlier measurements")) { load(after: next, expected: page.binding) }
            } else {
              Text(t("series_end", "No earlier measurements")).foregroundColor(.secondary)
            }
            if start != nil {
              Button(t("series_recent", "Most recent measurements")) { load(after: nil, expected: page.binding) }
            }
          }
        } else if changed {
          Text(t("series_changed", "Measurement history or permission changed."))
          Button(t("series_recent", "Most recent measurements"), action: loadRecent)
        }
      }
    }
    .navigationTitle(t("series_title", "Measurement history"))
    .onAppear(perform: loadRecent)
    .onDisappear { clear() }
    .onChange(of: scene) { phase in
      if phase == .active { loadRecent() }
      else { clear() }
    }
    .onChange(of: store.profile.identityFingerprint) { _ in clear() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in
      clear()
    }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
      loadRecent()
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) { event in
      if event.object as? String == records.owner, let page { load(after: start, expected: page.binding) }
    }
  }

  private func clear() { page = nil; start = nil; changed = false }

  private func loadRecent() {
    guard scene == .active, UIApplication.shared.isProtectedDataAvailable,
          store.profile.identityFingerprint == records.owner else { clear(); return }
    do { try records.reconcileLocalCare(); load(after: nil, expected: nil) }
    catch { clear(); changed = true }
  }

  private func load(after: GalaxySSIHealthCareSeries.Cursor?, expected: GalaxySSIHealthCareSeries.Binding?) {
    guard scene == .active, UIApplication.shared.isProtectedDataAvailable,
          store.profile.identityFingerprint == records.owner else { clear(); return }
    do {
      page = try records.localCareMeasurementPage(id: id, metric: metric, expected: expected, after: after)
      start = after
      changed = false
    } catch { clear(); changed = true }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSIHealthCareText.string(key, fallback, language: language)
  }

  private func gapLabel(_ gap: GalaxySSIHealthCareSeries.Gap) -> String {
    let fallback: String
    switch gap {
    case .unitsDiffer: fallback = "Different units"
    case .conditionsDiffer: fallback = "Different measurement conditions"
    case .conditionsUnknown: fallback = "Measurement conditions not fully recorded"
    case .sourceDiffers: fallback = "Different or unverified source"
    case .referenceDiffers: fallback = "Different report reference intervals"
    case .nonExactResult: fallback = "Not an exact numeric result"
    case .contextUnconfirmed: fallback = "Glucose context not confirmed for both measurements"
    case .methodUnverified: fallback = "Measurement method comparability not verified"
    }
    return t("series_gap." + gap.rawValue, fallback)
  }
}
