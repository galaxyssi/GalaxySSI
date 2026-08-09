import SwiftUI

struct SignalASIAgentHomeReadinessView: View {
  var runningTasks: Int
  var callableTargets: Int
  var nativeToolSummary: (total: Int, available: Int)
  var screenObservationAllowed: Bool
  var executionPaused: Bool
  var t: (String, String) -> String

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 9) {
        Image(systemName: executionPaused ? "pause.circle" : "checkmark.seal")
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(executionPaused ? .orange : .signalASIAccent)
          .frame(width: 24, height: 24)
        VStack(alignment: .leading, spacing: 2) {
          Text(t("signalasi.agent.readiness.title", "Agent readiness"))
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(.signalASITextPrimary)
          Text(readinessSubtitle)
            .font(.system(size: 11))
            .foregroundColor(.signalASITextSecondary)
            .lineLimit(2)
        }
        Spacer(minLength: 8)
        Text(executionPaused
          ? t("on_device_agent_status_paused", "Paused")
          : t("on_device_agent_status_running", "Ready"))
          .font(.system(size: 11, weight: .bold))
          .foregroundColor(executionPaused ? .orange : .signalASIAccent)
          .lineLimit(1)
      }

      HStack(spacing: 8) {
        metric(
          title: t("signalasi.agent.readiness.targets", "Targets"),
          value: "\(callableTargets)",
          systemImage: "person.2"
        )
        metric(
          title: t("cc_metric_native_tools", "Native tools"),
          value: "\(nativeToolSummary.available)/\(nativeToolSummary.total)",
          systemImage: "wrench.and.screwdriver"
        )
      }

      if !screenObservationAllowed {
        NavigationLink(destination: OnDeviceAgentPermissionsView()) {
          HStack(spacing: 8) {
            Image(systemName: "eye.slash")
              .foregroundColor(.orange)
            Text(t("agent_accessibility_status_disabled", "Screen access: needs permission"))
              .font(.system(size: 12, weight: .semibold))
              .foregroundColor(.signalASITextPrimary)
            Spacer(minLength: 4)
            Text(t("signalasi.common.manage", "Manage"))
              .font(.system(size: 11, weight: .bold))
              .foregroundColor(.orange)
            Image(systemName: "chevron.right")
              .font(.system(size: 11, weight: .bold))
              .foregroundColor(.orange)
          }
          .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(12)
    .background(Color.signalASIInsightBackground)
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.signalASIInsightStroke, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var readinessSubtitle: String {
    if executionPaused {
      return t("agent_status_paused_subtitle", "Execution is paused. Resume when you are ready.")
    }
    return String(
      format: t("agent_running_tasks_targets_value", "Running tasks: %d / targets: %d"),
      runningTasks,
      callableTargets
    )
  }

  private func metric(title: String, value: String, systemImage: String) -> some View {
    HStack(spacing: 7) {
      Image(systemName: systemImage)
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(.signalASIAccent)
      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .font(.system(size: 10))
          .foregroundColor(.signalASITextSecondary)
          .lineLimit(1)
        Text(value)
          .font(.system(size: 13, weight: .bold))
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 9)
    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
