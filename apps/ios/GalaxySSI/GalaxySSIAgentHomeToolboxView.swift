import SwiftUI

struct GalaxySSIAgentHomeToolboxView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var tools: [AgentNativeToolDescriptor]
  var t: (String, String) -> String
  var onCommand: (String) -> Void = { _ in }

  private var availableTools: [AgentNativeToolDescriptor] {
    tools
      .filter { $0.risk != .blocked && $0.availability.status == .available }
      .sorted { lhs, rhs in
        if lhs.risk != rhs.risk {
          return lhs.risk.weight < rhs.risk.weight
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
      }
  }

  private var visibleTools: [AgentNativeToolDescriptor] {
    let quickActions = availableTools.filter { example(for: $0) != nil }
    let informationalTools = availableTools.filter { example(for: $0) == nil }
    return Array((quickActions + informationalTools).prefix(6))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 7) {
        Image(systemName: "wrench.and.screwdriver")
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.galaxySSIAccent)
        Text(t("agent_section_toolbox", "Toolbox"))
          .font(.system(size: 13, weight: .bold))
          .foregroundColor(.galaxySSITextPrimary)
        Spacer(minLength: 6)
        Text(String(format: t("galaxyssi.agent_runtime.toolbox_summary", "%d local tools"), availableTools.count))
          .font(.system(size: 11, weight: .semibold))
          .foregroundColor(.galaxySSITextSecondary)
          .lineLimit(usesAccessibilityDynamicType ? 2 : 1)
          .multilineTextAlignment(.trailing)
      }

      if availableTools.isEmpty {
        Text(t("agent_toolbox_empty", "No local tools are available"))
          .font(.system(size: 12))
          .foregroundColor(.galaxySSITextSecondary)
          .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
          .padding(.horizontal, 12)
          .background(Color.galaxySSISurface)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      } else {
        ForEach(visibleTools) { tool in
          toolRow(tool)
        }
      }
    }
  }

  @ViewBuilder
  private func toolRow(_ tool: AgentNativeToolDescriptor) -> some View {
    if let example = example(for: tool) {
      Button(action: { onCommand(example) }) {
        toolRowContent(tool, example: example)
      }
      .buttonStyle(.plain)
      .accessibilityHint(Text(t("agent_toolbox_action_hint", "Tap to use this example")))
    } else {
      toolRowContent(tool, example: nil)
    }
  }

  private func toolRowContent(
    _ tool: AgentNativeToolDescriptor,
    example: String?
  ) -> some View {
    HStack(alignment: .top, spacing: 9) {
      Image(systemName: locationIcon(tool.location))
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(riskTint(tool.risk))
        .frame(width: 22, height: 22)
        .padding(.top, usesAccessibilityDynamicType ? 2 : 0)
      VStack(alignment: .leading, spacing: 2) {
        Text(tool.title.ifBlank(tool.id))
          .font(.system(size: 12.5, weight: .semibold))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(usesAccessibilityDynamicType ? 2 : 1)
        Text(example ?? String(format: t("agent_toolbox_meta", "%@ / %@ risk"), tool.id, riskText(tool.risk)))
          .font(.system(size: 10.5))
          .foregroundColor(.galaxySSITextSecondary)
          .lineLimit(usesAccessibilityDynamicType ? 2 : 1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Spacer(minLength: 6)
      toolRowStatus(hasExample: example != nil)
    }
    .padding(.horizontal, 12)
    .frame(
      maxWidth: .infinity,
      minHeight: usesAccessibilityDynamicType ? 64 : 44,
      alignment: .leading
    )
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .accessibilityElement(children: .combine)
  }

  private var usesAccessibilityDynamicType: Bool {
    dynamicTypeSize.isAccessibilitySize
  }

  @ViewBuilder
  private func toolRowStatus(hasExample: Bool) -> some View {
    if usesAccessibilityDynamicType {
      VStack(alignment: .trailing, spacing: 4) {
        toolEnabledLabel
        if hasExample {
          toolRowActionIcon
        }
      }
    } else {
      HStack(spacing: 6) {
        toolEnabledLabel
        if hasExample {
          toolRowActionIcon
        }
      }
    }
  }

  private var toolEnabledLabel: some View {
    Text(t("common_on", "On"))
      .font(.system(size: 10.5, weight: .bold))
      .foregroundColor(.galaxySSIAccent)
  }

  private var toolRowActionIcon: some View {
    Image(systemName: "arrow.up.right")
      .font(.system(size: 10, weight: .bold))
      .foregroundColor(.galaxySSITextSecondary)
  }

  private func example(for tool: AgentNativeToolDescriptor) -> String? {
    let id = tool.id.lowercased()
    switch true {
    case id.hasSuffix(".read.screen"):
      return t("agent_toolbox_example_read_screen", "summarize screen")
    case id.hasSuffix(".tap"):
      return t("agent_toolbox_example_tap", "tap first")
    case id.hasSuffix(".type.text"):
      return t("agent_toolbox_example_type", "type hello")
    case id.hasSuffix(".swipe"):
      return t("agent_toolbox_example_swipe", "swipe up")
    case id.hasSuffix(".long.press"):
      return t("agent_toolbox_example_long_press", "long press first")
    case id.hasSuffix(".copy.screen.text"):
      return t("agent_toolbox_example_copy_screen", "copy screen text")
    case id.hasSuffix(".paste.text"):
      return t("agent_toolbox_example_paste", "paste clipboard")
    case id.hasSuffix(".delete.text"):
      return t("agent_toolbox_example_delete", "clear text")
    case id.hasSuffix(".back"):
      return t("agent_toolbox_example_back", "go back")
    case id.hasSuffix(".home"):
      return t("agent_toolbox_example_home", "go home")
    case id.hasSuffix(".recents"):
      return t("agent_toolbox_example_recents", "show recents")
    case id.hasSuffix(".lock.screen"):
      return t("agent_toolbox_example_lock", "lock screen")
    case id.hasSuffix(".open.app"):
      return t("agent_toolbox_example_open_app", "open phone")
    case id.hasSuffix(".open.url"):
      return t("agent_toolbox_example_open_url", "open url https://example.com")
    case id.hasSuffix(".set.alarm"):
      return t("agent_toolbox_example_set_alarm", "set alarm 07:30")
    case id.hasSuffix(".reply.notification"):
      return t("agent_toolbox_example_reply_notification", "reply notification thanks")
    default:
      return nil
    }
  }

  private func locationIcon(_ location: AgentNativeToolLocation) -> String {
    switch location {
    case .phone: return "iphone"
    case .desktop: return "desktopcomputer"
    case .application: return "app.badge"
    case .androidSystem: return "cpu"
    case .accessibilityService: return "accessibility"
    case .unknown: return "wrench.and.screwdriver"
    }
  }

  private func riskText(_ risk: AgentNativeToolRisk) -> String {
    switch risk {
    case .low: return t("galaxyssi.agent_risk.low", "low")
    case .medium: return t("galaxyssi.agent_risk.medium", "medium")
    case .high: return t("galaxyssi.agent_risk.high", "high")
    case .blocked: return t("galaxyssi.agent_risk.blocked", "blocked")
    }
  }

  private func riskTint(_ risk: AgentNativeToolRisk) -> Color {
    switch risk {
    case .low: return .galaxySSIAccent
    case .medium: return .orange
    case .high, .blocked: return .red
    }
  }
}
