import SwiftUI

@MainActor
struct GalaxySSIHealthReportSupplementView: View {
  typealias Quick = GalaxySSIHealthReportQuickImport
  let plan: Quick.Plan
  let language: String
  let save: (Quick.Supplement) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var date: Date
  @State private var dateConfirmed = false
  @State private var fasting = ""

  init(plan: Quick.Plan, language: String, save: @escaping (Quick.Supplement) -> Void) {
    self.plan = plan; self.language = language; self.save = save
    _date = State(initialValue: plan.collectedDate ?? Date())
  }
  private var resolved: Date? {
    guard let zone = TimeZone(identifier: plan.zone) else { return nil }
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
    let matches = GalaxySSIHealthEncounter.possibleTimes(day: date, hour: calendar.component(.hour, from: date),
      minute: calendar.component(.minute, from: date), zone: zone)
    return matches.count == 1 ? matches.first : nil
  }
  private var valid: Bool {
    (!plan.needsDate || (dateConfirmed && resolved.map { Quick.validSupplementDate($0, plan: plan, now: Date()) } == true)) &&
      (!plan.needsFasting || !fasting.isEmpty)
  }
  var body: some View {
    NavigationView {
      Form {
        if plan.needsDate {
          Section(t("sample_time", "Sample date and time")) {
            if plan.collectedDate != nil {
              Text(date, style: .date)
              DatePicker(t("sample_time", "Sample date and time"), selection: $date, displayedComponents: .hourAndMinute)
            } else {
              DatePicker(t("sample_time", "Sample date and time"), selection: $date, in: ...Date())
            }
            Text(plan.zone).foregroundColor(.secondary)
            Toggle(t("confirm_time", "I confirm the sample date and time"), isOn: $dateConfirmed)
            if resolved.map({ !Quick.validSupplementDate($0, plan: plan, now: Date()) }) ?? true {
              Text(t("invalid_time", "Choose an unambiguous sample time that is not in the future.")).foregroundColor(.secondary)
            }
          }.environment(\.timeZone, TimeZone(identifier: plan.zone) ?? .current)
        }
        if plan.needsFasting {
          Picker(t("fasting_prompt", "Was the glucose sample taken fasting?"), selection: $fasting) {
            Text(t("choose", "Choose")).tag("")
            Text(t("fasting", "Fasting")).tag("fasting")
            Text(t("non_fasting", "Not fasting")).tag("non_fasting")
            Text(t("unknown", "Not sure")).tag("unspecified")
          }
        }
        Button(t("save_all", "Save supported results")) {
          if valid { save(.init(measuredAt: plan.needsDate ? resolved : nil, fasting: fasting)) }
        }.disabled(!valid)
      }
      .navigationTitle(t("supplement", "Complete report information"))
      .navigationBarTitleDisplayMode(.inline)
      .onChange(of: date) { _ in dateConfirmed = false }
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button(t("cancel", "Cancel")) { dismiss() } } }
    }.navigationViewStyle(.stack)
  }
  private func t(_ key: String, _ fallback: String) -> String { Quick.text(key, fallback, language) }
}
