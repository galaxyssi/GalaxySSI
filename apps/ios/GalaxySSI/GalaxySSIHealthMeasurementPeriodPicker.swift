import SwiftUI
import UIKit

@MainActor
struct GalaxySSIHealthMeasurementPeriodPicker: View {
  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.locale) private var locale
  @Environment(\.timeZone) private var timeZone
  let records: GalaxySSIHealthRecords
  var initialKind = GalaxySSIHealthMeasurementPeriod.Kind.week
  var allowsKindChange = true
  var showsLatest = true
  let select: (GalaxySSIHealthMeasurementPeriod?) -> Void
  @StateObject private var query = GalaxySSIHealthMeasurementQuery()
  @State private var kind = GalaxySSIHealthMeasurementPeriod.Kind.week
  @State private var initialized = false
  @State private var before: String?
  @State private var history: [String?] = []

  var body: some View {
    List {
      if scene == .active && store.profile.identityFingerprint == records.owner {
        if allowsKindChange {
          Picker(t("choose", "Sampling period"), selection: $kind) {
            Text(t("weeks", "By week")).tag(GalaxySSIHealthMeasurementPeriod.Kind.week)
            Text(t("months", "By month")).tag(GalaxySSIHealthMeasurementPeriod.Kind.month)
          }.pickerStyle(.segmented)
        }
        if let failure = query.failure {
          Text(GalaxySSIHealthMeasurementPeriodText.failure(failure, language: language))
          Button(t("retry", "Reload")) { reload() }
        } else if let page = query.output?.periods {
          if showsLatest { Button(t("latest", "Latest measurements")) { choose(nil) } }
          ForEach(page.periods) { period in
            Button { choose(period) } label: {
              Text(GalaxySSIHealthMeasurementPeriodText.label(period, zone: timeZone, locale: locale))
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
          }
          if page.periods.isEmpty { Text(t("empty", "No matching measurements")) }
          if !history.isEmpty {
            Button(t("previous_page", "Previous page")) { before = history.removeLast(); reload() }
          }
          if let next = page.next {
            Button(t("next_page", "Next page")) { history.append(before); before = next; reload() }
          }
        } else { ProgressView() }
      }
    }
    .listStyle(.plain).navigationTitle(t("choose", "Sampling period"))
    .navigationBarTitleDisplayMode(.inline).privacySensitive()
    .onAppear {
      if !initialized { initialized = true; kind = initialKind }
      reload()
    }
    .onDisappear { query.cancel() }
    .onChange(of: kind) { _ in before = nil; history = []; reload() }
    .onChange(of: timeZone) { _ in before = nil; history = []; reload() }
    .onChange(of: scene) { if $0 == .active { reload() } else { query.cancel() } }
    .onChange(of: store.profile.identityFingerprint) { _ in query.cancel() }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) { changed($0) }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in query.cancel() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in reload() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in before = nil; history = []; reload() }
  }
  private func choose(_ period: GalaxySSIHealthMeasurementPeriod?) {
    guard scene == .active, store.profile.identityFingerprint == records.owner, query.isCurrent(records: records) else { reload(); return }
    select(period)
  }
  private func reload() {
    guard scene == .active else { query.cancel(); return }
    query.load(records: records, scope: .picker(kind: kind, before: before), zone: timeZone) {
      store.profile.identityFingerprint == records.owner
    }
  }
  private func changed(_ notification: Notification) { if notification.object as? String == records.owner { reload() } }
  private func t(_ key: String, _ fallback: String) -> String { GalaxySSIHealthMeasurementPeriodText.text(key, fallback, language) }
}
