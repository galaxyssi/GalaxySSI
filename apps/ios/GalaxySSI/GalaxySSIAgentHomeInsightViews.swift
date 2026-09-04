import SwiftUI

struct GalaxySSIAgentHomeInsightBanner: View {
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
          GalaxySSIAgentHomeStatusChip(
            title: "iOS 15+",
            value: t("galaxyssi.status.ready", "Ready")
          )
          GalaxySSIAgentHomeStatusChip(
            title: t("galaxyssi.agent.status", "Agent"),
            value: agentStatusText
          )
          GalaxySSIAgentHomeStatusChip(
            title: t("cc_metric_native_tools", "Native tools"),
            value: nativeToolsText
          )
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
      return String(
        format: t(
          "galaxyssi.agent.insight.unread",
          "You have %d unread agent messages."
        ),
        unreadTotal
      )
    }
    if executionPaused {
      return t(
        "agent_status_paused_subtitle",
        "Execution is paused. Resume when you are ready."
      )
    }
    return String(
      format: t(
        "agent_running_tasks_targets_value",
        "Running tasks: %d / targets: %d"
      ),
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

struct GalaxySSIAgentHomeStatusChip: View {
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
