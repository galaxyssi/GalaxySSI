import SwiftUI

struct GalaxySSIAgentEmptyStateView: View {
  var title: String
  var subtitle: String

  var body: some View {
    VStack(spacing: 10) {
      GalaxySSILogoView(size: 48, cornerRadius: 10)
      Text(title)
        .font(.system(size: 18, weight: .semibold))
        .foregroundColor(.galaxySSITextPrimary)
      Text(subtitle)
        .font(.system(size: 13))
        .foregroundColor(.galaxySSITextSecondary)
    }
    .frame(maxWidth: .infinity, minHeight: 180)
    .accessibilityElement(children: .combine)
  }
}

struct GalaxySSIAgentRouteLogo: View {
  var label: String
  var size: CGFloat = 20

  var body: some View {
    Group {
      if let assetName = assetName {
        Image(assetName)
          .resizable()
          .scaledToFit()
          .clipShape(RoundedRectangle(cornerRadius: max(3, size * 0.2), style: .continuous))
      } else {
        Circle()
          .fill(Color.galaxySSIAccent)
          .overlay(
            Image(systemName: "person.2.fill")
              .font(.system(size: max(7, size * 0.42), weight: .bold))
              .foregroundColor(.white)
          )
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }

  private var assetName: String? {
    let normalized = label.lowercased()
    if normalized.contains("codex") { return "CodexLogo" }
    if normalized.contains("claude") || normalized.contains("anthropic") {
      return "ClaudeLogo"
    }
    if normalized.contains("hermes") { return "HermesLogo" }
    if normalized.contains("deepseek") { return "CloudProviderDeepSeek" }
    if normalized.contains("openrouter") { return "CloudProviderOpenRouter" }
    if normalized.contains("qwen") { return "CloudProviderQwen" }
    if normalized.contains("gemini") || normalized.contains("google") {
      return "CloudProviderGemini"
    }
    if normalized.contains("openai") || normalized.contains("gpt") {
      return "CloudProviderOpenAI"
    }
    return nil
  }
}

struct GalaxySSIAgentLoadOlderButton: View {
  var title: String
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      Label(title, systemImage: "arrow.up")
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(.galaxySSIInsightText)
        .frame(maxWidth: .infinity, minHeight: 40)
        .background(Color.galaxySSIInsightBackground)
        .overlay(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(Color.galaxySSIInsightStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(title))
  }
}

struct GalaxySSIAgentLatestButton: View {
  var title: String
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      Label(title, systemImage: "arrow.down")
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(.galaxySSITextPrimary)
        .padding(.horizontal, 12)
        .frame(minHeight: 40)
        .background(Color.galaxySSIBarBackground)
        .overlay(
          Capsule(style: .continuous)
            .stroke(Color.galaxySSIInputStroke, lineWidth: 0.8)
        )
        .clipShape(Capsule(style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(title))
  }
}

struct AgentTranscriptScrollMetrics: Equatable {
  var contentMinY: CGFloat = 0
  var contentMaxY: CGFloat = 0
  var viewportHeight: CGFloat = 0
}

struct AgentTranscriptScrollMetricsKey: PreferenceKey {
  static let defaultValue = AgentTranscriptScrollMetrics()

  static func reduce(
    value: inout AgentTranscriptScrollMetrics,
    nextValue: () -> AgentTranscriptScrollMetrics
  ) {
    value = nextValue()
  }
}

extension View {
  func agentDeviceTouchTarget(_ policy: AgentDeviceInputTargetPolicy) -> some View {
    frame(
      minWidth: CGFloat(policy.minimumTouchTargetDp),
      minHeight: CGFloat(policy.minimumTouchTargetDp)
    )
    .contentShape(Rectangle())
  }
}

struct AgentInsightBanner: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  var unreadTotal: Int
  var runningTasks: Int
  var callableTargets: Int
  var executionPaused: Bool
  var nativeToolSummary: (total: Int, available: Int)

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        GalaxySSILogoView(size: 34, cornerRadius: 7)
        VStack(alignment: .leading, spacing: 2) {
          Text("GalaxySSI Agent")
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(.galaxySSITextPrimary)
          Text(summaryText)
            .font(.system(size: 12))
            .foregroundColor(.galaxySSIInsightText)
            .lineLimit(2)
        }
        Spacer()
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          AgentStatusChip(title: "iOS 15+", value: t("galaxyssi.status.ready", "Ready"))
          AgentStatusChip(title: t("galaxyssi.agent.status", "Agent"), value: agentStatusText)
          AgentStatusChip(title: t("cc_metric_native_tools", "Native tools"), value: nativeToolsText)
        }
      }
    }
    .padding(12)
    .background(Color.galaxySSIInsightBackground)
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.galaxySSIInsightStroke, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var summaryText: String {
    if unreadTotal > 0 {
      return String(format: t("galaxyssi.agent.insight.unread", "You have %d unread agent messages."), unreadTotal)
    }
    if executionPaused {
      return t("agent_status_paused_subtitle", "Execution is paused. Resume when you are ready.")
    }
    return String(
      format: t("agent_running_tasks_targets_value", "Running tasks: %d / targets: %d"),
      runningTasks,
      callableTargets
    )
  }

  private var agentStatusText: String {
    executionPaused
      ? t("on_device_agent_status_paused", "Paused")
      : t("on_device_agent_status_running", "Running")
  }

  private var nativeToolsText: String {
    "\(nativeToolSummary.available)/\(nativeToolSummary.total)"
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct AgentStatusChip: View {
  var title: String
  var value: String

  var body: some View {
    HStack(spacing: 4) {
      Text(title)
        .foregroundColor(.galaxySSITextSecondary)
      Text(value)
        .fontWeight(.bold)
        .foregroundColor(.galaxySSITextPrimary)
    }
    .font(.system(size: 11))
    .lineLimit(1)
    .minimumScaleFactor(0.85)
    .padding(.horizontal, 9)
    .padding(.vertical, 6)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
