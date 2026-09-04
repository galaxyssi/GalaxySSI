import SwiftUI

struct GalaxySSIAgentConfirmationCard: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let task: AgentTaskRecord
  let onApproveOnce: () -> Void
  let onApproveSession: () -> Void
  let onApproveAlways: () -> Void
  let onDeny: () -> Void

  private var action: AgentAction? {
    task.pendingAction
  }

  private var canRemember: Bool {
    guard let action else { return false }
    return AgentConfirmationPolicy.tier(for: action) == .confirmOnce
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        Image(systemName: "checkmark.shield")
          .font(.system(size: 20, weight: .semibold))
          .foregroundColor(.orange)
          .frame(width: 36, height: 36)
          .background(Color.orange.opacity(0.14))
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        VStack(alignment: .leading, spacing: 3) {
          Text(t("galaxyssi.agent.confirmation.title", "Action needs your approval"))
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(.galaxySSITextPrimary)
          Text(t("galaxyssi.agent.confirmation.subtitle", "Review the requested phone action before it runs."))
            .font(.system(size: 12))
            .foregroundColor(.galaxySSITextSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      if let action {
        VStack(alignment: .leading, spacing: 6) {
          Text(action.description.ifBlank(t("galaxyssi.agent.confirmation.untitled", "Phone action")))
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.galaxySSITextPrimary)
            .fixedSize(horizontal: false, vertical: true)
          if !action.target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Label(action.target, systemImage: "scope")
              .font(.system(size: 12))
              .foregroundColor(.galaxySSITextSecondary)
          }
          Label(
            String(
              format: t("galaxyssi.agent.confirmation.risk", "Risk: %@"),
              riskTitle(action.risk)
            ),
            systemImage: "exclamationmark.triangle"
          )
          .font(.system(size: 12, weight: .medium))
          .foregroundColor(.orange)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.galaxySSIPageBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }

      primaryDecisionControls

      if canRemember {
        Button(action: onApproveSession) {
          Label(
            t("galaxyssi.agent.confirmation.allow_session", "Allow for this session"),
            systemImage: "arrow.triangle.2.circlepath"
          )
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.galaxySSITextPrimary)
          .frame(maxWidth: .infinity, minHeight: 38)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ios.agent.confirmation.allow-session")

        Button(action: onApproveAlways) {
          Label(
            t("galaxyssi.agent.confirmation.allow_always", "Remember this permission"),
            systemImage: "checkmark.shield"
          )
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.galaxySSITextPrimary)
          .frame(maxWidth: .infinity, minHeight: 38)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ios.agent.confirmation.allow-always")
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.galaxySSISurface)
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.orange.opacity(0.55), lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func riskTitle(_ risk: AgentRisk) -> String {
    switch risk {
    case .low:
      return t("galaxyssi.agent.confirmation.risk_low", "Low")
    case .medium:
      return t("galaxyssi.agent.confirmation.risk_medium", "Medium")
    case .high:
      return t("galaxyssi.agent.confirmation.risk_high", "High")
    case .blocked:
      return t("galaxyssi.agent.confirmation.risk_blocked", "Blocked")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }

  @ViewBuilder
  private var primaryDecisionControls: some View {
    if usesAccessibilityDynamicType {
      VStack(spacing: 8) {
        denyControl
        approveOnceControl
      }
    } else {
      HStack(spacing: 8) {
        denyControl
        approveOnceControl
      }
    }
  }

  private var denyControl: some View {
    Button(action: onDeny) {
      Text(t("galaxyssi.agent.confirmation.deny", "Deny"))
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(.red)
        .frame(maxWidth: .infinity, minHeight: 42)
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("ios.agent.confirmation.deny")
  }

  private var approveOnceControl: some View {
    Button(action: onApproveOnce) {
      Text(t("galaxyssi.agent.confirmation.allow_once", "Allow once"))
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(.white)
        .frame(maxWidth: .infinity, minHeight: 42)
        .background(Color.galaxySSIAccent)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("ios.agent.confirmation.allow-once")
  }

  private var usesAccessibilityDynamicType: Bool {
    dynamicTypeSize.isAccessibilitySize
  }
}
