import SwiftUI
import UIKit

@MainActor
struct GalaxySSIHealthMotionView: View {
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var motion = GalaxySSIHealthMotionController.shared
  let records: GalaxySSIHealthRecords
  @State private var goal = ""
  @State private var failed = false
  @State private var saveUnavailable = false
  private var state: GalaxySSIHealthMotion.State? { motion.matches(records) ? motion.state : nil }
  private var stepStatus: GalaxySSIHealthMotionController.Status { motion.matches(records) ? motion.stepStatus : .failed }
  private var cyclingStatus: GalaxySSIHealthMotionController.Status { motion.matches(records) ? motion.cyclingStatus : .failed }
  var body: some View {
    Form {
      if scene == .active {
        Section(t("goal", "Daily step goal")) {
          TextField(t("goal", "Daily step goal"), text: $goal).keyboardType(.numberPad)
          Button(t("save", "Save goal")) { saveGoal() }
          Button(t("clear", "Clear goal"), role: .destructive) { saveGoal(clear: true) }
          if failed { Text(saveUnavailable ? t("save_failed", "The goal could not be saved. The previous goal is unchanged.") :
            t("invalid_goal", "Enter a whole number from 1 to 1000000, or leave it empty.")).foregroundColor(.secondary) }
        }.disabled(state == nil)
        Section(t("phone_steps", "Phone step counter")) {
          Toggle(t("phone_steps", "Phone step counter"), isOn: Binding(
            get: { state?.stepsEnabled != nil }, set: { motion.setEnabled(.steps, enabled: $0, for: records) }))
            .disabled(state == nil || (state?.stepsEnabled == nil && (motion.stepStatus == .unsupported || motion.stepStatus == .restricted)) || motion.stepStatus == .requesting || motion.cyclingStatus == .requesting)
          Text(Self.status(stepStatus, language: language)).foregroundColor(.secondary)
          if let count = state?.steps?.today(Date(), calendar: .autoupdatingCurrent) {
            Text(count.formatted() + " " + t("steps_today", "phone steps today"))
          }
        }
        Section(t("cycling", "Automatic cycling detection")) {
          Toggle(t("cycling", "Automatic cycling detection"), isOn: Binding(
            get: { state?.cyclingEnabled != nil }, set: { motion.setEnabled(.cycling, enabled: $0, for: records) }))
            .disabled(state == nil || (state?.cyclingEnabled == nil && (motion.cyclingStatus == .unsupported || motion.cyclingStatus == .restricted)) || motion.stepStatus == .requesting || motion.cyclingStatus == .requesting)
          Text(Self.status(cyclingStatus, language: language)).foregroundColor(.secondary)
          Text(t("privacy", "Automatic detection. No location or route data.")).font(.caption).foregroundColor(.secondary)
        }
        if motion.stepStatus == .denied || motion.cyclingStatus == .denied {
          Link(t("system_settings", "System settings"), destination: URL(string: UIApplication.openSettingsURLString)!)
        }
        Button(t("retry", "Refresh motion data")) { if motion.matches(records) { motion.refresh() } }
      }
    }
    .navigationTitle(t("title", "Movement"))
    .galaxySSIHealthTheme()
    .privacySensitive()
    .toolbar { ToolbarItem(placement: .cancellationAction) { Button(t("close", "Close")) { dismiss() } } }
    .onAppear { reload() }
    .onChange(of: scene) { if $0 == .active { reload() } else if $0 == .background { goal = ""; failed = false } }
  }
  private func reload() { if motion.matches(records) { motion.refresh() }; goal = state?.goal.map(String.init) ?? ""; failed = false }
  private func saveGoal(clear: Bool = false) {
    let input = goal.trimmingCharacters(in: .whitespacesAndNewlines)
    let value = Int(input)
    guard clear || input.isEmpty || (input.range(of: #"^[0-9]{1,7}$"#, options: .regularExpression) != nil &&
      value.map({ (1...GalaxySSIHealthMotion.maximumGoal).contains($0) }) == true) else { failed = true; saveUnavailable = false; return }
    do { try motion.setGoal(clear || input.isEmpty ? nil : value, for: records); goal = state?.goal.map(String.init) ?? ""; failed = false }
    catch { failed = true; saveUnavailable = true }
  }
  static func status(_ status: GalaxySSIHealthMotionController.Status, language: String) -> String {
    let fallback: String
    switch status {
    case .off: fallback = "Off"
    case .active: fallback = "Automatic collection on"
    case .waiting: fallback = "Waiting for movement data"
    case .requesting: fallback = "Waiting for Motion & Fitness authorization"
    case .denied: fallback = "Motion & Fitness access denied"
    case .restricted: fallback = "Motion & Fitness access restricted"
    case .unsupported: fallback = "Motion sensor unavailable on this device"
    case .failed: fallback = "Motion data unavailable. Saved totals are unchanged."
    }
    return text("status." + status.rawValue, fallback, language)
  }
  static func text(_ key: String, _ fallback: String, _ language: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.motion." + key, fallback: fallback, language: language)
  }
  static func cyclingDuration(_ seconds: TimeInterval, language: String) -> String {
    let minutes = max(0, Int64(seconds / 60))
    if seconds > 0 && seconds < 60 { return text("under_minute", "Under 1 min", language) }
    if minutes >= 60 {
      return String(format: text("hours_minutes", "%lld h %lld min", language), minutes / 60, minutes % 60)
    }
    return String(format: text("minutes", "%lld min", language), minutes)
  }
  private func t(_ key: String, _ fallback: String) -> String { Self.text(key, fallback, language) }
}

@MainActor
struct GalaxySSIHealthCyclingOverviewRow: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.sizeCategory) private var sizeCategory
  @ObservedObject private var motion = GalaxySSIHealthMotionController.shared
  let records: GalaxySSIHealthRecords
  var activityTile = false
  @State private var settings = false
  var body: some View {
    TimelineView(.periodic(from: Date(), by: 30)) { context in
      Button { settings = true } label: {
        VStack(alignment: .leading, spacing: 5) {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label(title: { Text(t("cycling_today", "Cycling today")).foregroundColor(.primary) },
              icon: { Image(systemName: "bicycle").foregroundColor(.green) })
              .font(.subheadline.weight(.semibold))
            Spacer(minLength: 4)
            if !spacious && !activityTile { amount(context.date) }
            if !activityTile { Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary) }
          }
          if spacious || activityTile { amount(context.date).frame(maxWidth: .infinity, alignment: activityTile ? .leading : .trailing) }
          Text(detail(context.date)).font(.caption).foregroundColor(.secondary)
        }.frame(maxWidth: .infinity, minHeight: 50, alignment: .leading).contentShape(Rectangle()).padding(.vertical, 5)
      }.buttonStyle(.plain)
    }
    .accessibilityIdentifier("health-overview-cycling")
    .sheet(isPresented: $settings) { NavigationView { GalaxySSIHealthMotionView(records: records) }.navigationViewStyle(.stack) }
  }
  private var spacious: Bool { sizeCategory.isAccessibilityCategory || [.extraExtraLarge, .extraExtraExtraLarge].contains(sizeCategory) }
  private func amount(_ date: Date) -> some View {
    Text(duration(date)).font(.title3.weight(.semibold)).foregroundColor(.primary)
  }
  private func detail(_ now: Date) -> String {
    guard motion.matches(records), let state = motion.state else { return t("status.failed", "Motion data unavailable. Saved totals are unchanged.") }
    if [.active, .waiting].contains(motion.cyclingStatus) && state.cyclingEnabled != nil {
      return state.cycling.riding(now) ? t("riding", "Cycling") : t("stopped", "Stopped")
    }
    return GalaxySSIHealthMotionView.status(motion.cyclingStatus, language: language)
  }
  private func duration(_ now: Date) -> String {
    guard motion.matches(records), let state = motion.state else { return "\u{2014}" }
    let seconds = state.cycling.today(now, calendar: .autoupdatingCurrent)
    return GalaxySSIHealthMotionView.cyclingDuration(seconds, language: language)
  }
  private func t(_ key: String, _ fallback: String) -> String { GalaxySSIHealthMotionView.text(key, fallback, language) }
}
