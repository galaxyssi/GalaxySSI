import SwiftUI

enum GalaxySSIRemoteTaskStatusPresentation {
  static func title(_ status: String, language: String) -> String {
    switch AgentRemoteTaskStatusPolicy.normalize(status) {
    case "accepted": return localized("agent_task_status_accepted", fallback: "Accepted", language: language)
    case "queued": return localized("agent_task_status_queued", fallback: "Queued", language: language)
    case "starting": return localized("agent_task_status_starting", fallback: "Starting", language: language)
    case "recovering": return localized("agent_task_status_recovering", fallback: "Recovering", language: language)
    case "running": return localized("agent_task_status_running", fallback: "Running", language: language)
    case "waiting_input": return localized("agent_task_status_waiting_input", fallback: "Waiting for input", language: language)
    case "waiting_approval": return localized("agent_task_status_waiting_approval", fallback: "Waiting for approval", language: language)
    case "completed": return localized("agent_task_status_completed", fallback: "Completed", language: language)
    case "failed": return localized("agent_task_status_failed", fallback: "Failed", language: language)
    case "cancelled": return localized("agent_task_status_cancelled", fallback: "Cancelled", language: language)
    case "timed_out": return localized("agent_task_status_timed_out", fallback: "Timed out", language: language)
    case "not_found": return localized("agent_task_status_not_found", fallback: "Task unavailable", language: language)
    case "cancelling": return localized("agent_task_status_cancelling", fallback: "Cancelling", language: language)
    default: return status.replacingOccurrences(of: "_", with: " ").capitalized
    }
  }

  static func tint(_ status: String) -> Color {
    switch AgentRemoteTaskStatusPolicy.normalize(status) {
    case "failed", "timed_out", "not_found": return .red
    case "cancelled", "cancelling": return .galaxySSITextSecondary
    default: return .galaxySSIAccent
    }
  }

  private static func localized(_ key: String, fallback: String, language: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}
