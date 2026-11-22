import SwiftUI
import UIKit

@MainActor
struct GalaxySSIHealthReportContextForm: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let review: GalaxySSIHealthReportBatch.Review
  let save: (GalaxySSIHealthReportBatch.Supplement) throws -> Void
  @State private var day = Date()
  @State private var clock = Date()
  @State private var condition = "unspecified"
  @State private var timeConfirmed = false
  @State private var failed = false

  var body: some View {
    NavigationView {
      Form {
        if scene == .active {
          ForEach(review.plans) { plan in
            Section(plan.job.original.name) {
              if let printed = plan.job.reportVision?.collected, !printed.isEmpty {
                Text(printed).foregroundColor(.secondary)
              }
              Text(plan.zone).font(.caption).foregroundColor(.secondary)
              if let condition = plan.job.reportVision?.fasting, !condition.isEmpty {
                Text(GalaxySSIHealthReportBatch.conditionTitle(condition, language: language)).font(.caption).foregroundColor(.secondary)
              }
              ForEach(plan.items) { item in
                HStack {
                  Text(item.reading.metric.title(language: language))
                  Spacer()
                  Text(value(item.reading)).foregroundColor(.secondary).multilineTextAlignment(.trailing)
                }
              }
            }
          }
          Section {
            if review.scope.needsDate {
              DatePicker(t("sample_date", "Sampling date"), selection: $day, in: ...Date(), displayedComponents: .date)
            }
            if review.scope.needsTime {
              DatePicker(t("sample_clock", "Sampling time"), selection: $clock, displayedComponents: .hourAndMinute)
              Toggle(t("confirm_time", "I confirm the sampling date and time"), isOn: $timeConfirmed)
            }
            if review.scope.needsCondition {
              Picker(t("sample_condition", "Glucose sampling condition"), selection: $condition) {
                ForEach(GalaxySSIHealthReportBatch.conditions, id: \.self) {
                  Text(GalaxySSIHealthReportBatch.conditionTitle($0, language: language)).tag($0)
                }
              }
            }
            if failed { Text(t("context_failed", "The source, permissions or records changed, or the sampling time is invalid. Reopen confirmation and check the fields.")) }
          }
        }
      }
      .environment(\.timeZone, TimeZone(identifier: review.zone) ?? .current)
      .navigationTitle(t("confirm_batch", "Confirm sampling details"))
      .galaxySSIHealthTheme()
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(t("cancel", "Cancel")) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(t("confirm_save", "Confirm and save")) {
            guard scene == .active, UIApplication.shared.isProtectedDataAvailable else { return }
            do {
              try save(.init(day: review.scope.needsDate ? day : nil,
                clock: review.scope.needsTime ? clock : nil, condition: condition))
              dismiss()
            } catch { failed = true }
          }.disabled(scene != .active || (review.scope.needsTime && !timeConfirmed))
        }
      }
    }.navigationViewStyle(.stack)
    .onChange(of: scene) { if $0 == .background { dismiss() } }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in dismiss() }
  }

  private func value(_ reading: GalaxySSIHealthReading) -> String {
    var text = reading.reportedNotation ?? reading.value.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
    if let diastolic = reading.diastolic { text += " / " + NSDecimalNumber(decimal: diastolic).stringValue }
    return text + (reading.unit.isEmpty ? "" : " " + reading.unit)
  }

  private func t(_ key: String, _ fallback: String) -> String { GalaxySSIHealthReportQuickImport.text(key, fallback, language) }
}
