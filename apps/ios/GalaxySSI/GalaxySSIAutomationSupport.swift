import SwiftUI

struct AutomationEditorDraft {
  var taskId: String
  var name: String
  var triggerKind: AgentProactiveTriggerKind
  var cron: String
  var timeZone: String
  var intervalSeconds: String
  var goalId: String
  var webhookId: String
  var actionKind: AgentProactiveActionKind
  var targetId: String
  var prompt: String
  var argumentsJson: String
  var teamText: String
  var deliveryMode: String
  var maxAttempts: String
  var maxConcurrency: String
  var network: String
  var requiresCharging: Bool
  var enabled: Bool
  var original: AgentProactiveTask

  init(task: AgentProactiveTask) {
    taskId = task.taskId
    name = task.name
    triggerKind = task.trigger.kind
    cron = task.trigger.cron.ifBlank("0 9 * * *")
    timeZone = task.trigger.timeZone.ifBlank(TimeZone.autoupdatingCurrent.identifier)
    intervalSeconds = "\(max(task.trigger.intervalSeconds, AgentProactiveTrigger.minIntervalSeconds))"
    goalId = task.trigger.goalId.ifBlank(task.taskId)
    webhookId = task.trigger.webhookId.ifBlank(task.taskId)
    actionKind = task.action.kind
    targetId = task.action.targetId.ifBlank(Self.defaultTarget(for: task.action.kind))
    prompt = task.action.prompt
    argumentsJson = task.action.argumentsJson.ifBlank("{}")
    teamText = task.action.team.isEmpty
      ? "lead:codex"
      : task.action.team.map { "\($0.role.rawValue.lowercased()):\($0.agentId)" }.joined(separator: "\n")
    deliveryMode = task.action.deliveryMode.ifBlank("store")
    maxAttempts = "\(task.policy.maxAttempts)"
    maxConcurrency = "\(task.policy.maxConcurrency)"
    network = task.policy.network.ifBlank("any")
    requiresCharging = task.policy.requiresCharging
    enabled = task.enabled
    original = task
  }

  func makeTask() throws -> AgentProactiveTask {
    let trigger = try makeTrigger()
    let action = try makeAction()
    let policy = try AgentProactivePolicy(
      misfire: original.policy.misfire,
      catchUpLimit: original.policy.catchUpLimit,
      jitterSeconds: original.policy.jitterSeconds,
      maxAttempts: Int(maxAttempts) ?? original.policy.maxAttempts,
      retryBackoffSeconds: original.policy.retryBackoffSeconds,
      maxConcurrency: Int(maxConcurrency) ?? original.policy.maxConcurrency,
      maxConsecutiveFailures: original.policy.maxConsecutiveFailures,
      deadlineAtMillis: original.policy.deadlineAtMillis,
      maxRuns: original.policy.maxRuns,
      network: network,
      requiresCharging: requiresCharging
    )
    return try AgentProactiveTask(
      taskId: taskId,
      name: name,
      trigger: trigger,
      action: action,
      policy: policy,
      enabled: enabled,
      nextRunAtMillis: original.nextRunAtMillis,
      lastRunAtMillis: original.lastRunAtMillis,
      lastStatus: original.lastStatus,
      runCount: original.runCount,
      consecutiveFailures: original.consecutiveFailures,
      revision: original.revision,
      createdAtMillis: original.createdAtMillis,
      updatedAtMillis: original.updatedAtMillis
    )
  }

  mutating func applyTriggerKind(_ kind: AgentProactiveTriggerKind) {
    triggerKind = kind
    switch kind {
    case .manual:
      break
    case .cron:
      cron = cron.ifBlank("0 9 * * *")
      timeZone = timeZone.ifBlank(TimeZone.autoupdatingCurrent.identifier)
    case .interval:
      timeZone = timeZone.ifBlank(TimeZone.autoupdatingCurrent.identifier)
      intervalSeconds = validIntervalText(intervalSeconds)
    case .goalCheckpoint:
      timeZone = timeZone.ifBlank(TimeZone.autoupdatingCurrent.identifier)
      intervalSeconds = validIntervalText(intervalSeconds)
      goalId = goalId.ifBlank(taskId)
    case .webhook:
      timeZone = timeZone.ifBlank(TimeZone.autoupdatingCurrent.identifier)
      webhookId = webhookId.ifBlank(taskId)
    }
  }

  mutating func applyActionKind(_ kind: AgentProactiveActionKind) {
    actionKind = kind
    switch kind {
    case .agent:
      targetId = Self.defaultTarget(for: .agent)
    case .subagentTeam:
      teamText = teamText.ifBlank("lead:codex")
    case .workflow:
      targetId = Self.defaultTarget(for: .workflow)
    case .nativeTool:
      targetId = Self.defaultTarget(for: .nativeTool)
      argumentsJson = argumentsJson.ifBlank("{}")
    }
  }

  private func makeTrigger() throws -> AgentProactiveTrigger {
    switch triggerKind {
    case .manual:
      return try AgentProactiveTrigger(kind: .manual, timeZone: timeZone)
    case .cron:
      return try AgentProactiveTrigger(kind: .cron, cron: cron, timeZone: timeZone)
    case .interval:
      return try AgentProactiveTrigger(
        kind: .interval,
        timeZone: timeZone,
        intervalSeconds: max(Int64(intervalSeconds) ?? 3_600, AgentProactiveTrigger.minIntervalSeconds)
      )
    case .goalCheckpoint:
      return try AgentProactiveTrigger(
        kind: .goalCheckpoint,
        timeZone: timeZone,
        intervalSeconds: max(Int64(intervalSeconds) ?? 3_600, AgentProactiveTrigger.minIntervalSeconds),
        goalId: goalId.ifBlank(taskId)
      )
    case .webhook:
      return try AgentProactiveTrigger(
        kind: .webhook,
        timeZone: timeZone,
        webhookId: webhookId.ifBlank(taskId)
      )
    }
  }

  private func makeAction() throws -> AgentProactiveAction {
    switch actionKind {
    case .subagentTeam:
      return try AgentProactiveAction(
        kind: .subagentTeam,
        team: parseTeam(teamText),
        deliveryMode: deliveryMode
      )
    case .nativeTool:
      return try AgentProactiveAction(
        kind: .nativeTool,
        targetId: targetId.ifBlank(Self.defaultTarget(for: .nativeTool)),
        prompt: prompt,
        argumentsJson: argumentsJson,
        deliveryMode: deliveryMode
      )
    case .workflow:
      let reference = targetId.ifBlank(Self.defaultTarget(for: .workflow))
      guard AgentWorkflowResolver.resolve(reference) != nil else {
        throw AgentProactiveTaskError.invalid("Workflow '\(reference)' was not found")
      }
      return try AgentProactiveAction(
        kind: .workflow,
        targetId: reference,
        argumentsJson: "{}",
        deliveryMode: deliveryMode
      )
    case .agent:
      return try AgentProactiveAction(
        kind: .agent,
        targetId: targetId.ifBlank(Self.defaultTarget(for: .agent)),
        prompt: prompt,
        argumentsJson: "{}",
        deliveryMode: deliveryMode
      )
    }
  }

  private func parseTeam(_ value: String) throws -> [AgentProactiveTeamMember] {
    let rows = value
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    let members = try rows.map { row -> AgentProactiveTeamMember in
      let parts = row.split(separator: ":", maxSplits: 1).map(String.init)
      guard parts.count == 2,
            let role = AgentProactiveTeamRole.allCases.first(where: {
              $0.rawValue.caseInsensitiveCompare(parts[0]) == .orderedSame
            }) else {
        throw AgentProactiveTaskError.invalid("One member per line: lead:codex")
      }
      return try AgentProactiveTeamMember(agentId: parts[1], role: role)
    }
    return members.isEmpty ? [try AgentProactiveTeamMember(agentId: "codex", role: .lead)] : members
  }

  private static func defaultTarget(for kind: AgentProactiveActionKind) -> String {
    switch kind {
    case .agent: return "codex"
    case .subagentTeam: return ""
    case .workflow: return AgentWorkflowResolver.defaultReference()
    case .nativeTool: return AgentPhoneNativeToolCatalog.descriptors().first?.id ?? "galaxyssi.device.status"
    }
  }

  private func validIntervalText(_ value: String) -> String {
    "\(max(Int64(value) ?? 3_600, AgentProactiveTrigger.minIntervalSeconds))"
  }
}

enum GalaxySSIAutomationLabels {
  static func trigger(_ kind: AgentProactiveTriggerKind, language: String) -> String {
    switch kind {
    case .manual:
      return t("galaxyssi.automation.trigger_manual", "Manual", language: language)
    case .cron:
      return t("galaxyssi.automation.trigger_cron", "Cron schedule", language: language)
    case .interval:
      return t("galaxyssi.automation.trigger_interval", "Interval", language: language)
    case .goalCheckpoint:
      return t("galaxyssi.automation.trigger_goal", "Goal checkpoint", language: language)
    case .webhook:
      return t("galaxyssi.automation.trigger_webhook", "Trusted webhook", language: language)
    }
  }

  static func action(_ kind: AgentProactiveActionKind, language: String) -> String {
    switch kind {
    case .agent:
      return t("galaxyssi.automation.action_agent", "Agent", language: language)
    case .subagentTeam:
      return t("galaxyssi.automation.action_team", "Sub-agent team", language: language)
    case .workflow:
      return t("galaxyssi.automation.action_workflow", "Saved workflow", language: language)
    case .nativeTool:
      return t("galaxyssi.automation.action_tool", "Phone tool", language: language)
    }
  }

  static func delivery(_ value: String, language: String) -> String {
    switch value {
    case "notify":
      return t("galaxyssi.automation.delivery_notify", "Store and notify", language: language)
    case "mobile":
      return t("galaxyssi.automation.delivery_mobile", "Deliver through GalaxySSI Link", language: language)
    default:
      return t("galaxyssi.automation.delivery_store", "Store result", language: language)
    }
  }

  static func network(_ value: String, language: String) -> String {
    switch value {
    case "unmetered":
      return t("galaxyssi.automation.network_unmetered", "Unmetered network", language: language)
    case "offline":
      return t("galaxyssi.automation.network_offline", "Offline only", language: language)
    default:
      return t("galaxyssi.automation.network_any", "Any network state", language: language)
    }
  }

  static func status(_ status: AgentProactiveRunStatus, language: String) -> String {
    switch status {
    case .queued:
      return t("galaxyssi.agent_task.status_queued", "Queued", language: language)
    case .running, .retrying:
      return t("galaxyssi.automation.status_running", "Running", language: language)
    case .waiting:
      return t("galaxyssi.automation.status_waiting", "Waiting", language: language)
    case .completed:
      return t("galaxyssi.automation.status_completed", "Completed", language: language)
    case .failed:
      return t("galaxyssi.automation.status_failed", "Failed", language: language)
    case .cancelled:
      return t("galaxyssi.automation.status_cancelled", "Cancelled", language: language)
    case .skipped:
      return t("galaxyssi.automation.status_skipped", "Skipped", language: language)
    }
  }

  static func statusTint(_ status: AgentProactiveRunStatus) -> Color {
    switch status {
    case .completed:
      return .galaxySSIAccent
    case .failed, .cancelled:
      return .red
    case .running, .retrying, .waiting:
      return .orange
    case .queued:
      return .blue
    case .skipped:
      return .galaxySSITextSecondary
    }
  }

  static func time(_ millis: Int64, language: String) -> String {
    guard millis > 0 else { return "-" }
    let formatter = DateFormatter()
    formatter.dateFormat = "MM-dd HH:mm:ss"
    formatter.locale = Locale(identifier: language == LanguagePolicySettings.zhCN ? "zh_Hans_CN" : "en_US_POSIX")
    return formatter.string(from: Date(timeIntervalSince1970: Double(millis) / 1_000))
  }

  private static func t(_ key: String, _ fallback: String, language: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}

struct AutomationMetric: Identifiable {
  var id: String { label }
  var value: String
  var label: String
}

struct AutomationHeroCard: View {
  var title: String
  var subtitle: String
  var icon: String
  var tint: Color
  var metrics: [AutomationMetric]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .center, spacing: 12) {
        AutomationIcon(systemName: icon, tint: tint, size: 52, iconSize: 24)
        VStack(alignment: .leading, spacing: 4) {
          Text(title)
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(.galaxySSITextPrimary)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
          Text(subtitle)
            .font(.system(size: 14))
            .foregroundColor(.galaxySSITextSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      HStack(spacing: 8) {
        ForEach(metrics) { metric in
          VStack(alignment: .leading, spacing: 2) {
            Text(metric.value)
              .font(.system(size: 17, weight: .bold))
              .foregroundColor(.galaxySSITextPrimary)
              .lineLimit(1)
              .minimumScaleFactor(0.68)
            Text(metric.label)
              .font(.system(size: 10, weight: .semibold))
              .foregroundColor(.galaxySSITextSecondary)
              .lineLimit(2)
              .minimumScaleFactor(0.72)
          }
          .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
          .padding(.horizontal, 10)
          .background(Color.galaxySSISurface)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct AutomationTaskRow: View {
  var title: String
  var subtitle: String
  var icon: String
  var tint: Color
  var badge: String
  var badgeTint: Color

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      AutomationIcon(systemName: icon, tint: tint, size: 44, iconSize: 18)
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(2)
          .minimumScaleFactor(0.78)
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundColor(.galaxySSITextSecondary)
          .lineLimit(3)
      }
      Spacer(minLength: 8)
      AutomationBadge(title: badge, tint: badgeTint)
      Image(systemName: "chevron.right")
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(.galaxySSITextSecondary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

struct AutomationInfoRow: View {
  var title: String
  var subtitle: String
  var icon: String
  var tint: Color
  var badge: String

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      AutomationIcon(systemName: icon, tint: tint, size: 44, iconSize: 18)
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(2)
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundColor(.galaxySSITextSecondary)
          .lineLimit(3)
      }
      Spacer(minLength: 8)
      if !badge.isEmpty {
        AutomationBadge(title: badge, tint: tint)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

struct AutomationActionRow: View {
  var title: String
  var subtitle: String
  var icon: String
  var tint: Color
  var badge: String
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(alignment: .center, spacing: 12) {
        AutomationIcon(systemName: icon, tint: tint, size: 44, iconSize: 18)
        VStack(alignment: .leading, spacing: 4) {
          Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.galaxySSITextPrimary)
            .lineLimit(2)
          Text(subtitle)
            .font(.system(size: 12))
            .foregroundColor(.galaxySSITextSecondary)
            .lineLimit(3)
        }
        Spacer(minLength: 8)
        if !badge.isEmpty {
          AutomationBadge(title: badge, tint: tint)
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 11)
      .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
      .background(Color.galaxySSISurface)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}

struct AutomationTemplateRow: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  var title: String
  var subtitle: String
  var action: (String, String) -> Void

  var body: some View {
    AutomationActionRow(
      title: title,
      subtitle: subtitle,
      icon: "wand.and.stars",
      tint: .blue,
      badge: t("galaxyssi.automation.run", "Run")
    ) {
      action(title, subtitle)
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct AutomationSwitchRow: View {
  var title: String
  var subtitle: String
  var icon: String
  var tint: Color
  @Binding var isOn: Bool

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      AutomationIcon(systemName: icon, tint: tint, size: 44, iconSize: 18)
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(2)
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundColor(.galaxySSITextSecondary)
          .lineLimit(2)
      }
      Spacer(minLength: 8)
      Toggle("", isOn: $isOn)
        .labelsHidden()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

struct AutomationTextInputRow: View {
  var title: String
  var subtitle: String = ""
  var icon: String
  var tint: Color
  @Binding var text: String
  var keyboardType: UIKeyboardType = .default

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 12) {
        AutomationIcon(systemName: icon, tint: tint, size: 40, iconSize: 17)
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.galaxySSITextPrimary)
          if !subtitle.isEmpty {
            Text(subtitle)
              .font(.system(size: 12))
              .foregroundColor(.galaxySSITextSecondary)
          }
        }
      }
      TextField(title, text: $text)
        .keyboardType(keyboardType)
        .font(.system(size: 15))
        .padding(10)
        .background(Color.galaxySSIPageBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .padding(12)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

struct AutomationTextEditorRow: View {
  var title: String
  var subtitle: String
  var icon: String
  var tint: Color
  @Binding var text: String
  var minHeight: CGFloat

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 12) {
        AutomationIcon(systemName: icon, tint: tint, size: 40, iconSize: 17)
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.galaxySSITextPrimary)
          if !subtitle.isEmpty {
            Text(subtitle)
              .font(.system(size: 12))
              .foregroundColor(.galaxySSITextSecondary)
          }
        }
      }
      TextEditor(text: $text)
        .font(.system(size: 14))
        .frame(minHeight: minHeight)
        .padding(6)
        .background(Color.galaxySSIPageBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .padding(12)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

struct AutomationPickerRow<Value: Hashable>: View {
  var title: String
  var icon: String
  var tint: Color
  @Binding var selection: Value
  var values: [Value]
  var label: (Value) -> String

  var body: some View {
    HStack(spacing: 12) {
      AutomationIcon(systemName: icon, tint: tint, size: 44, iconSize: 18)
      Text(title)
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(.galaxySSITextPrimary)
      Spacer(minLength: 8)
      Picker(title, selection: $selection) {
        ForEach(values, id: \.self) { value in
          Text(label(value)).tag(value)
        }
      }
      .pickerStyle(MenuPickerStyle())
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct AutomationIcon: View {
  var systemName: String
  var tint: Color
  var size: CGFloat
  var iconSize: CGFloat

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(tint.opacity(0.14))
      Image(systemName: systemName)
        .font(.system(size: iconSize, weight: .semibold))
        .foregroundColor(tint)
    }
    .frame(width: size, height: size)
  }
}

private struct AutomationBadge: View {
  var title: String
  var tint: Color

  var body: some View {
    Text(title)
      .font(.system(size: 11, weight: .bold))
      .foregroundColor(tint)
      .lineLimit(1)
      .minimumScaleFactor(0.7)
      .padding(.horizontal, 8)
      .frame(minHeight: 26)
      .background(tint.opacity(0.1))
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
