import SwiftUI

struct SignalASIAgentHomeToolboxView: View {
  var tools: [AgentNativeToolDescriptor]
  var t: (String, String) -> String

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

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 7) {
        Image(systemName: "wrench.and.screwdriver")
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.signalASIAccent)
        Text(t("agent_section_toolbox", "Toolbox"))
          .font(.system(size: 13, weight: .bold))
          .foregroundColor(.signalASITextPrimary)
        Spacer(minLength: 6)
        Text(String(format: t("signalasi.agent_runtime.toolbox_summary", "%d local tools"), availableTools.count))
          .font(.system(size: 11, weight: .semibold))
          .foregroundColor(.signalASITextSecondary)
          .lineLimit(1)
      }

      if availableTools.isEmpty {
        Text(t("agent_toolbox_empty", "No local tools are available"))
          .font(.system(size: 12))
          .foregroundColor(.signalASITextSecondary)
          .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
          .padding(.horizontal, 12)
          .background(Color.signalASISurface)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      } else {
        ForEach(Array(availableTools.prefix(6))) { tool in
          toolRow(tool)
        }
      }
    }
  }

  private func toolRow(_ tool: AgentNativeToolDescriptor) -> some View {
    HStack(spacing: 9) {
      Image(systemName: locationIcon(tool.location))
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(riskTint(tool.risk))
        .frame(width: 22, height: 22)
      VStack(alignment: .leading, spacing: 2) {
        Text(tool.title.ifBlank(tool.id))
          .font(.system(size: 12.5, weight: .semibold))
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(1)
        Text(String(format: t("agent_toolbox_meta", "%@ / %@ risk"), tool.id, riskText(tool.risk)))
          .font(.system(size: 10.5))
          .foregroundColor(.signalASITextSecondary)
          .lineLimit(1)
      }
      Spacer(minLength: 6)
      Text(t("common_on", "On"))
        .font(.system(size: 10.5, weight: .bold))
        .foregroundColor(.signalASIAccent)
    }
    .padding(.horizontal, 12)
    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .accessibilityElement(children: .combine)
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
    case .low: return t("signalasi.agent_risk.low", "low")
    case .medium: return t("signalasi.agent_risk.medium", "medium")
    case .high: return t("signalasi.agent_risk.high", "high")
    case .blocked: return t("signalasi.agent_risk.blocked", "blocked")
    }
  }

  private func riskTint(_ risk: AgentNativeToolRisk) -> Color {
    switch risk {
    case .low: return .signalASIAccent
    case .medium: return .orange
    case .high, .blocked: return .red
    }
  }
}
