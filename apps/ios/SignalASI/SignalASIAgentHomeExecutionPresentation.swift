import SwiftUI

extension AgentHomeView {
  func agentPhaseLabel(_ phase: AgentPhase) -> String {
    switch phase {
    case .observing:
      return t("agent_status_observing", "Observing the current screen")
    case .planning:
      return t("agent_status_planning", "Planning from the goal")
    case .waitingConfirmation:
      return t("agent_status_waiting_confirmation", "Waiting for confirmation")
    case .executing:
      return t("agent_status_executing", "Executing action")
    case .verifying:
      return t("agent_status_verifying", "Verifying result")
    case .waitingResponse:
      return t("agent_status_waiting_response", "Waiting for reply")
    case .paused:
      return t("agent_status_paused", "Task paused")
    case .cancelled:
      return t("agent_status_cancelled", "Task cancelled")
    case .blocked:
      return t("agent_status_blocked", "Action blocked")
    case .completed:
      return t("agent_status_completed", "Action completed")
    case .failed:
      return t("agent_status_failed", "Action failed")
    }
  }

  func agentPhaseTint(_ phase: AgentPhase) -> Color {
    switch phase {
    case .blocked, .failed:
      return .red
    case .cancelled, .paused:
      return .signalASITextSecondary
    case .observing, .planning, .waitingConfirmation, .executing, .verifying,
         .waitingResponse, .completed:
      return .signalASIAccent
    }
  }

  func agentExecutionLocationSummary(_ task: AgentTaskRecord) -> String {
    let location = AgentExecutionPresentationPolicy.location(record: task)
    let summary = [
      locationLabel(location.locationKind),
      runtimeLabel(location.runtimeKind),
      location.locationName
    ]
      .filter { !$0.isBlank }
      .joined(separator: " · ")
      .ifBlank(t("signalasi.agent.execution.unknown", "Execution location unavailable"))
    return summary.replacingOccurrences(of: " \u{8DEF} ", with: " \u{00B7} ")
  }

  func agentExecutionStep(_ task: AgentTaskRecord) -> String {
    let pendingStep = task.pendingAction?.description ?? ""
    return pendingStep
      .ifBlank(task.executionLog.last ?? "")
      .ifBlank(agentPhaseLabel(task.phase))
  }

  func remoteAgentStatusLabel(_ status: String) -> String {
    SignalASIRemoteTaskStatusPresentation.title(status, language: interfaceLanguage)
  }

  func remoteAgentStatusTint(_ status: String) -> Color {
    SignalASIRemoteTaskStatusPresentation.tint(status)
  }

  func remoteAgentStep(_ snapshot: AgentRemoteTaskStatusSnapshot) -> String {
    snapshot.currentStep
      .ifBlank(snapshot.detail)
      .ifBlank(remoteAgentStatusLabel(snapshot.status))
  }

  func remoteAgentTimelineLine(_ event: AgentRemoteTaskStatusEvent) -> String {
    let label = remoteAgentStatusLabel(event.status)
    return event.currentStep
      .ifBlank(event.detail)
      .ifBlank(label)
  }

  func executionDuration(startedAtMillis: Int64, updatedAtMillis: Int64) -> String {
    guard startedAtMillis > 0, updatedAtMillis >= startedAtMillis else { return "" }
    return executionDuration(elapsedMillis: updatedAtMillis - startedAtMillis)
  }

  func executionDuration(elapsedMillis: Int64) -> String {
    AgentTranscriptPresentationPolicy.formatProcessedDuration(
      elapsedMillis,
      hoursUnit: t("signalasi.agent.trace.duration_hours", "h"),
      minutesUnit: t("signalasi.agent.trace.duration_minutes", "m"),
      secondsUnit: t("signalasi.agent.trace.duration_seconds", "s")
    )
  }

  func locationLabel(_ value: AgentExecutionLocationKind) -> String {
    switch value {
    case .phone:
      return t("signalasi.agent_execution.location.phone", "Phone")
    case .desktop:
      return t("signalasi.agent_execution.location.desktop", "Desktop")
    case .cloud:
      return t("signalasi.agent_execution.location.cloud", "Cloud")
    case .connectedDevice:
      return t("signalasi.agent_execution.location.device", "Connected device")
    case .unknown:
      return ""
    }
  }

  func runtimeLabel(_ value: AgentExecutionRuntimeKind) -> String {
    switch value {
    case .phoneNative:
      return t("signalasi.agent_execution.runtime.phone_native", "Phone native")
    case .phoneLinux:
      return t("signalasi.agent_execution.runtime.phone_linux", "Phone Linux")
    case .phoneLocalModel:
      return t("signalasi.agent_execution.runtime.local_model", "Local model")
    case .phoneCloudAPI:
      return t("signalasi.agent_execution.runtime.cloud_api", "Cloud API")
    case .desktopAgent:
      return t("signalasi.agent_execution.runtime.desktop_agent", "Desktop Agent")
    case .desktopTool:
      return t("signalasi.agent_execution.runtime.desktop_tool", "Desktop tool")
    case .connectedDevice:
      return t("signalasi.agent_execution.runtime.connected_device", "Connected device")
    case .knowledge:
      return t("signalasi.agent_execution.runtime.knowledge", "Knowledge")
    case .unknown:
      return ""
    }
  }

}
