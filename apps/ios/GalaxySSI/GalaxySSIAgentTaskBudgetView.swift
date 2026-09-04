import SwiftUI
import UIKit

struct AgentTaskBudgetSettingsView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @State private var networkPolicyPresented = false

  private var budget: AgentTaskBudget {
    store.agentTaskBudget.normalized
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("cc_task_budget_title", "Task budget"),
        leading: {
          GalaxySSIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          GalaxySSISecurityHeroView(
            title: t("cc_task_budget_banner_title", "Resource guardrails"),
            subtitle: t(
              "cc_task_budget_banner_subtitle",
              "Resource counters follow the task across phone, Desktop, models, and Agents without interrupting execution. Network and privacy policies remain enforceable."
            ),
            systemImage: "hourglass.circle.fill",
            tint: .purple,
            badge: TaskBudgetCopy.profileLabel(budget.profile, language: interfaceLanguage)
          )
          profileSection
          telemetrySection
          resourceSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .sheet(isPresented: $networkPolicyPresented) {
      AgentTaskBudgetNetworkPolicySheet()
        .environmentObject(store)
    }
  }

  private var profileSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_task_budget_profile_section", "Budget profile"))
      ForEach(AgentTaskBudgetProfile.allCases) { profile in
        let selected = profile == budget.profile
        GalaxySSISecurityActionRow(
          title: TaskBudgetCopy.profileLabel(profile, language: interfaceLanguage),
          subtitle: TaskBudgetCopy.profileSubtitle(profile, language: interfaceLanguage),
          systemImage: "slider.horizontal.3",
          tint: selected ? .galaxySSIAccent : .galaxySSITextSecondary,
          badge: selected ? t("settings_language_selected", "Selected") : ""
        ) {
          if !selected {
            store.selectAgentTaskBudgetProfile(profile)
          }
        }
      }
    }
  }

  private var telemetrySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_task_budget_limits_section", "Runtime telemetry"))
      ForEach(TaskBudgetEditableLimit.allCases) { limit in
        GalaxySSISecurityStatusRow(
          title: limit.title(language: interfaceLanguage),
          subtitle: limit.subtitle(language: interfaceLanguage),
          systemImage: limit.systemImage,
          tint: limit.tint,
          badge: limit.valueLabel(from: budget, language: interfaceLanguage)
        )
      }
    }
  }

  private var resourceSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_task_budget_resource_section", "Resource access"))
      GalaxySSISecurityActionRow(
        title: t("cc_task_budget_network_policy_title", "Network policy"),
        subtitle: t("cc_task_budget_network_policy_subtitle", "Choose which network targets a task may use"),
        systemImage: "link",
        tint: .purple,
        badge: TaskBudgetCopy.networkPolicyLabel(budget.networkPolicy, language: interfaceLanguage)
      ) {
        networkPolicyPresented = true
      }
      TaskBudgetToggleRow(
        title: t("cc_task_budget_cloud_title", "Cloud resources"),
        subtitle: t("cc_task_budget_cloud_subtitle", "Allow configured cloud models, tools, and services"),
        systemImage: "cloud.fill",
        tint: .blue,
        isOn: boolBinding(\.allowCloud)
      )
      TaskBudgetToggleRow(
        title: t("cc_task_budget_paid_title", "Paid providers"),
        subtitle: t("cc_task_budget_paid_subtitle", "Allow resources that can report a non-zero cost"),
        systemImage: "creditcard.fill",
        tint: .galaxySSIAccent,
        isOn: boolBinding(\.allowPaidProviders)
      )
    }
  }

  private func boolBinding(_ keyPath: WritableKeyPath<AgentTaskBudget, Bool>) -> Binding<Bool> {
    Binding(
      get: { store.agentTaskBudget[keyPath: keyPath] },
      set: { value in store.updateAgentTaskBudget { $0[keyPath: keyPath] = value } }
    )
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct AgentTaskBudgetValueEditor: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  var limit: TaskBudgetEditableLimit
  @State private var draft: String
  @State private var errorText = ""

  init(limit: TaskBudgetEditableLimit, budget: AgentTaskBudget) {
    self.limit = limit
    _draft = State(initialValue: limit.editValue(from: budget))
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: limit.dialogTitle(language: interfaceLanguage),
        leading: {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 18, weight: .semibold))
              .foregroundColor(.galaxySSITextPrimary)
              .frame(width: 40, height: 40)
          }
          .buttonStyle(.plain)
        },
        trailing: {
          Button {
            save()
          } label: {
            Image(systemName: "checkmark")
              .font(.system(size: 18, weight: .semibold))
              .foregroundColor(.galaxySSIAccent)
              .frame(width: 40, height: 40)
          }
          .buttonStyle(.plain)
        }
      )
      VStack(alignment: .leading, spacing: 12) {
        GalaxySSISecurityHeroView(
          title: limit.title(language: interfaceLanguage),
          subtitle: limit.subtitle(language: interfaceLanguage),
          systemImage: limit.systemImage,
          tint: limit.tint,
          badge: limit.unitLabel(language: interfaceLanguage)
        )
        VStack(alignment: .leading, spacing: 8) {
          Text(limit.inputLabel(language: interfaceLanguage))
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.galaxySSITextSecondary)
          TextField(limit.inputLabel(language: interfaceLanguage), text: $draft)
            .font(.system(size: 18, weight: .semibold, design: .monospaced))
            .foregroundColor(.galaxySSITextPrimary)
            .keyboardType(limit.keyboardType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .padding(.horizontal, 12)
            .frame(minHeight: 52)
            .background(Color.galaxySSISurface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        if !errorText.isEmpty {
          GalaxySSISecurityStatusRow(
            title: t("cc_task_budget_invalid_value", "Enter zero or a positive number"),
            subtitle: errorText,
            systemImage: "exclamationmark.triangle.fill",
            tint: .orange,
            badge: ""
          )
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 12)
      .padding(.top, 12)
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
  }

  private func save() {
    if limit.apply(raw: draft, store: store) {
      dismiss()
    } else {
      errorText = t("cc_task_budget_invalid_value", "Enter zero or a positive number")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct AgentTaskBudgetNetworkPolicySheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("cc_task_budget_network_policy_title", "Network policy"),
        leading: {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 18, weight: .semibold))
              .foregroundColor(.galaxySSITextPrimary)
              .frame(width: 40, height: 40)
          }
          .buttonStyle(.plain)
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 8) {
          GalaxySSISecuritySectionTitle(title: t("cc_task_budget_resource_section", "Resource access"))
          ForEach(AgentTaskNetworkPolicy.allCases) { policy in
            let selected = policy == store.agentTaskBudget.networkPolicy
            GalaxySSISecurityActionRow(
              title: TaskBudgetCopy.networkPolicyLabel(policy, language: interfaceLanguage),
              subtitle: networkPolicySubtitle(policy),
              systemImage: selected ? "checkmark.circle.fill" : "link",
              tint: selected ? .galaxySSIAccent : .purple,
              badge: selected ? t("settings_language_selected", "Selected") : t("galaxyssi.common.select", "Select")
            ) {
              store.updateAgentTaskBudget { $0.networkPolicy = policy }
              dismiss()
            }
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
  }

  private func networkPolicySubtitle(_ policy: AgentTaskNetworkPolicy) -> String {
    switch policy {
    case .any:
      return t("cc_task_budget_network_any_subtitle", "Use the active network path selected by iOS.")
    case .unmeteredOnly:
      return t("cc_task_budget_network_unmetered_subtitle", "Avoid metered cellular or constrained network paths.")
    case .trustedOnly:
      return t("cc_task_budget_network_trusted_subtitle", "Limit network work to trusted private targets.")
    case .offlineOnly:
      return t("cc_task_budget_network_offline_subtitle", "Keep tasks on local and on-device resources.")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct TaskBudgetToggleRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  @Binding var isOn: Bool

  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(tint.opacity(0.16))
        Image(systemName: systemImage)
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(tint)
      }
      .frame(width: 42, height: 42)
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.82)
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundColor(.galaxySSITextSecondary)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      Toggle("", isOn: $isOn)
        .labelsHidden()
        .tint(tint)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private enum TaskBudgetEditableLimit: String, CaseIterable, Identifiable {
  case time
  case cost
  case inputTokens
  case outputTokens
  case network
  case battery
  case memory

  var id: String { rawValue }

  var systemImage: String {
    switch self {
    case .time:
      return "clock.fill"
    case .cost:
      return "dollarsign.circle.fill"
    case .inputTokens, .outputTokens:
      return "slider.horizontal.3"
    case .network:
      return "link"
    case .battery:
      return "battery.75"
    case .memory:
      return "memorychip.fill"
    }
  }

  var tint: Color {
    switch self {
    case .time, .inputTokens, .outputTokens, .memory:
      return .blue
    case .cost:
      return .galaxySSIAccent
    case .network:
      return .purple
    case .battery:
      return .orange
    }
  }

  var keyboardType: UIKeyboardType {
    switch self {
    case .time, .cost:
      return .decimalPad
    default:
      return .numberPad
    }
  }

  func title(language: String) -> String {
    switch self {
    case .time:
      return t("cc_task_budget_time_title", "Active time", language: language)
    case .cost:
      return t("cc_task_budget_cost_title", "Reported cost", language: language)
    case .inputTokens:
      return t("cc_task_budget_input_tokens_title", "Input tokens", language: language)
    case .outputTokens:
      return t("cc_task_budget_output_tokens_title", "Output tokens", language: language)
    case .network:
      return t("cc_task_budget_network_title", "Network data", language: language)
    case .battery:
      return t("cc_task_budget_battery_title", "Minimum battery", language: language)
    case .memory:
      return t("cc_task_budget_memory_title", "Working memory", language: language)
    }
  }

  func subtitle(language: String) -> String {
    switch self {
    case .time:
      return t("cc_task_budget_time_subtitle", "Waiting for approval does not consume active execution time", language: language)
    case .cost:
      return t("cc_task_budget_cost_subtitle", "Stop paid model use when reported or estimated cost reaches the limit", language: language)
    case .inputTokens:
      return t("cc_task_budget_input_tokens_subtitle", "Maximum context and prompt tokens consumed by the task", language: language)
    case .outputTokens:
      return t("cc_task_budget_output_tokens_subtitle", "Maximum generated tokens across task attempts", language: language)
    case .network:
      return t("cc_task_budget_network_subtitle", "Maximum encrypted payload, attachment, and provider traffic in MiB", language: language)
    case .battery:
      return t("cc_task_budget_battery_subtitle", "Pause new work below this level unless the phone is charging", language: language)
    case .memory:
      return t("cc_task_budget_memory_subtitle", "Maximum task working set in MiB; 0 lets the system manage it", language: language)
    }
  }

  func dialogTitle(language: String) -> String {
    switch self {
    case .time:
      return t("cc_task_budget_time_dialog", "Maximum active minutes (0 for unlimited)", language: language)
    case .cost:
      return t("cc_task_budget_cost_dialog", "Maximum USD cost (0 for unlimited)", language: language)
    default:
      return title(language: language)
    }
  }

  func inputLabel(language: String) -> String {
    switch self {
    case .time:
      return t("cc_task_budget_minutes_input", "Minutes", language: language)
    case .cost:
      return t("cc_task_budget_cost_input", "USD", language: language)
    case .network, .memory:
      return "MiB"
    case .battery:
      return "%"
    case .inputTokens, .outputTokens:
      return t("cc_task_budget_count_input", "Count", language: language)
    }
  }

  func unitLabel(language: String) -> String {
    switch self {
    case .time:
      return t("cc_task_budget_minutes_unit", "min", language: language)
    case .cost:
      return "USD"
    case .network, .memory:
      return "MiB"
    case .battery:
      return "%"
    case .inputTokens, .outputTokens:
      return t("cc_task_budget_tokens_unit", "tokens", language: language)
    }
  }

  func valueLabel(from budget: AgentTaskBudget, language: String) -> String {
    switch self {
    case .time:
      return TaskBudgetCopy.timeValue(budget.maxElapsedSeconds, language: language)
    case .cost:
      return TaskBudgetCopy.costValue(budget.maxCostMicros, language: language)
    case .inputTokens:
      return TaskBudgetCopy.countValue(budget.maxInputTokens, language: language)
    case .outputTokens:
      return TaskBudgetCopy.countValue(budget.maxOutputTokens, language: language)
    case .network:
      return TaskBudgetCopy.bytesValue(budget.maxNetworkBytes, zeroKey: "cc_task_budget_unlimited", zeroFallback: "Unlimited", language: language)
    case .battery:
      return String(format: t("cc_task_budget_battery_value", "%d%%", language: language), budget.minimumBatteryPercent)
    case .memory:
      return TaskBudgetCopy.bytesValue(budget.maxMemoryBytes, zeroKey: "cc_task_budget_system_managed", zeroFallback: "System managed", language: language)
    }
  }

  func editValue(from budget: AgentTaskBudget) -> String {
    switch self {
    case .time:
      guard budget.maxElapsedSeconds > 0 else { return "0" }
      return TaskBudgetCopy.decimalString(Double(budget.maxElapsedSeconds) / 60.0, maximumFractionDigits: budget.maxElapsedSeconds % 60 == 0 ? 0 : 2)
    case .cost:
      guard budget.maxCostMicros > 0 else { return "0" }
      return TaskBudgetCopy.decimalString(Double(budget.maxCostMicros) / 1_000_000.0, maximumFractionDigits: 6)
    case .inputTokens:
      return String(budget.maxInputTokens)
    case .outputTokens:
      return String(budget.maxOutputTokens)
    case .network:
      return budget.maxNetworkBytes <= 0 ? "0" : String(budget.maxNetworkBytes / AgentTaskBudget.mib)
    case .battery:
      return String(budget.minimumBatteryPercent)
    case .memory:
      return budget.maxMemoryBytes <= 0 ? "0" : String(budget.maxMemoryBytes / AgentTaskBudget.mib)
    }
  }

  @MainActor
  func apply(raw: String, store: GalaxySSIStore) -> Bool {
    switch self {
    case .time:
      guard let value = TaskBudgetCopy.parseDouble(raw), value >= 0 else { return false }
      store.updateAgentTaskBudget { $0.maxElapsedSeconds = Int64(value * 60.0) }
    case .cost:
      guard let value = TaskBudgetCopy.parseDouble(raw), value >= 0 else { return false }
      store.updateAgentTaskBudget { $0.maxCostMicros = Int64(value * 1_000_000.0) }
    case .inputTokens:
      guard let value = TaskBudgetCopy.parseInt64(raw), value >= 0 else { return false }
      store.updateAgentTaskBudget { $0.maxInputTokens = value }
    case .outputTokens:
      guard let value = TaskBudgetCopy.parseInt64(raw), value >= 0 else { return false }
      store.updateAgentTaskBudget { $0.maxOutputTokens = value }
    case .network:
      guard let value = TaskBudgetCopy.parseInt64(raw), value >= 0 else { return false }
      store.updateAgentTaskBudget { $0.maxNetworkBytes = safeMib(value) }
    case .battery:
      guard let value = TaskBudgetCopy.parseInt64(raw), (0...100).contains(value) else { return false }
      store.updateAgentTaskBudget { $0.minimumBatteryPercent = Int(value) }
    case .memory:
      guard let value = TaskBudgetCopy.parseInt64(raw), value >= 0 else { return false }
      store.updateAgentTaskBudget { $0.maxMemoryBytes = safeMib(value) }
    }
    return true
  }

  private func safeMib(_ value: Int64) -> Int64 {
    value > Int64.max / AgentTaskBudget.mib ? Int64.max : value * AgentTaskBudget.mib
  }

  private func t(_ key: String, _ fallback: String, language: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}

private enum TaskBudgetCopy {
  static func profileLabel(_ profile: AgentTaskBudgetProfile, language: String) -> String {
    switch profile {
    case .adaptive:
      return t("cc_task_budget_profile_adaptive", "Adaptive", language: language)
    case .fast:
      return t("cc_task_budget_profile_fast", "Fast", language: language)
    case .economy:
      return t("cc_task_budget_profile_economy", "Economy", language: language)
    case .privateMode:
      return t("cc_task_budget_profile_private", "Private", language: language)
    case .custom:
      return t("cc_task_budget_profile_custom", "Custom", language: language)
    }
  }

  static func profileSubtitle(_ profile: AgentTaskBudgetProfile, language: String) -> String {
    switch profile {
    case .adaptive:
      return t("cc_task_budget_profile_adaptive_subtitle", "Resource usage is recorded without stopping the task", language: language)
    case .fast:
      return t("cc_task_budget_profile_fast_subtitle", "Run without time, token, memory, or network byte cutoffs", language: language)
    case .economy:
      return t("cc_task_budget_profile_economy_subtitle", "Keep resource usage visible while preserving task completion", language: language)
    case .privateMode:
      return t("cc_task_budget_profile_private_subtitle", "Use phone, private, and trusted paired resources only", language: language)
    case .custom:
      return t("cc_task_budget_profile_custom_subtitle", "Retain custom values for compatibility and telemetry", language: language)
    }
  }

  static func networkPolicyLabel(_ policy: AgentTaskNetworkPolicy, language: String) -> String {
    switch policy {
    case .any:
      return t("cc_task_budget_network_any", "Any available network", language: language)
    case .unmeteredOnly:
      return t("cc_task_budget_network_unmetered", "Unmetered only", language: language)
    case .trustedOnly:
      return t("cc_task_budget_network_trusted", "Trusted and private only", language: language)
    case .offlineOnly:
      return t("cc_task_budget_network_offline", "Offline only", language: language)
    }
  }

  static func timeValue(_ seconds: Int64, language: String) -> String {
    guard seconds > 0 else {
      return t("cc_task_budget_unlimited", "Unlimited", language: language)
    }
    if seconds >= 3_600 && seconds % 3_600 == 0 {
      return String(format: t("cc_task_budget_hours_value", "%d h", language: language), seconds / 3_600)
    }
    return String(format: t("cc_task_budget_minutes_value", "%d min", language: language), (seconds + 59) / 60)
  }

  static func costValue(_ micros: Int64, language: String) -> String {
    micros <= 0
      ? t("cc_task_budget_unlimited", "Unlimited", language: language)
      : String(format: "$%.2f", Double(micros) / 1_000_000.0)
  }

  static func countValue(_ value: Int64, language: String) -> String {
    value <= 0 ? t("cc_task_budget_unlimited", "Unlimited", language: language) : decimalString(value)
  }

  static func bytesValue(_ value: Int64, zeroKey: String, zeroFallback: String, language: String) -> String {
    value <= 0 ? t(zeroKey, zeroFallback, language: language) : "\(value / AgentTaskBudget.mib) MiB"
  }

  static func parseDouble(_ raw: String) -> Double? {
    let value = raw
      .replacingOccurrences(of: ",", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : Double(value)
  }

  static func parseInt64(_ raw: String) -> Int64? {
    let value = raw
      .replacingOccurrences(of: ",", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : Int64(value)
  }

  static func decimalString(_ value: Double, maximumFractionDigits: Int) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = maximumFractionDigits
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: value)) ?? String(value)
  }

  static func decimalString(_ value: Int64) -> String {
    let formatter = NumberFormatter()
    formatter.locale = .autoupdatingCurrent
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: value)) ?? String(value)
  }

  private static func t(_ key: String, _ fallback: String, language: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}
