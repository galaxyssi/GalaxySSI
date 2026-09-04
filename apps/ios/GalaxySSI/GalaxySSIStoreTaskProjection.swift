import Foundation

extension GalaxySSIStore {
  func mergedAgentTaskRecords() -> [AgentTaskRecord] {
    var byId: [String: AgentTaskRecord] = [:]
    for record in agentTaskRecords + workspaceAgentTaskRecords() where !record.taskId.isBlank {
      if let existing = byId[record.taskId],
         existing.updatedAtMillis >= record.updatedAtMillis {
        continue
      }
      byId[record.taskId] = record
    }
    return Self.sortedAgentTasks(Array(byId.values))
  }

  private func workspaceAgentTaskRecords() -> [AgentTaskRecord] {
    agentWorkspaceStore.list().compactMap { workspace in
      let taskId = workspace.taskId.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !taskId.isEmpty else { return nil }
      let routeKind = workspaceRouteKind(workspace)
      let locationKind = workspaceLocationKind(workspace, routeKind: routeKind)
      let runtimeKind = workspaceRuntimeKind(workspace, routeKind: routeKind, locationKind: locationKind)
      return AgentTaskRecord(
        taskId: taskId,
        sessionId: workspace.sessionId,
        goal: workspace.goal.ifBlank(workspace.workspaceId),
        phase: workspacePhase(workspace.status),
        routeKind: routeKind,
        targetTitle: workspaceTargetTitle(workspace, routeKind: routeKind),
        risk: workspace.status == .blocked ? .blocked : .medium,
        blocked: workspace.status == .blocked,
        executionLocationKind: locationKind,
        executionRuntimeKind: runtimeKind,
        executionLocationId: workspace.deviceId.ifBlank(workspace.agentId),
        executionLocationName: workspace.deviceId.ifBlank(workspace.agentId),
        executionRuntimeId: workspace.remoteRunId,
        executionLocationTrusted: true,
        result: workspaceResultText(workspace),
        verification: workspace.currentPlanSnapshot,
        outputFiles: workspace.artifacts.map(\.uri),
        executionLog: workspace.eventJournal.map { event in
          [Self.formatMillis(event.timestampMillis), event.kind, event.message]
            .filter { !$0.isBlank }
            .joined(separator: " / ")
        },
        createdAtMillis: workspace.createdAtMillis,
        updatedAtMillis: workspace.updatedAtMillis
      )
    }
  }

  private func workspacePhase(_ status: AgentWorkspaceStatus) -> AgentPhase {
    switch status {
    case .created, .queued:
      return .planning
    case .running:
      return .executing
    case .waitingConfirmation:
      return .waitingConfirmation
    case .waitingResponse:
      return .waitingResponse
    case .paused:
      return .paused
    case .blocked:
      return .blocked
    case .completed:
      return .completed
    case .failed:
      return .failed
    case .cancelled:
      return .cancelled
    }
  }

  private func workspaceRouteKind(_ workspace: AgentWorkspace) -> AgentRouteKind {
    if !workspace.remoteRunId.isBlank || !workspace.agentId.isBlank {
      return .desktopAgent
    }
    return .localSystem
  }

  private func workspaceLocationKind(_ workspace: AgentWorkspace, routeKind: AgentRouteKind) -> AgentExecutionLocationKind {
    if !workspace.deviceId.isBlank || routeKind == .desktopAgent {
      return .desktop
    }
    return .phone
  }

  private func workspaceRuntimeKind(
    _ workspace: AgentWorkspace,
    routeKind: AgentRouteKind,
    locationKind: AgentExecutionLocationKind
  ) -> AgentExecutionRuntimeKind {
    if routeKind == .desktopAgent || locationKind == .desktop {
      return .desktopAgent
    }
    return .phoneNative
  }

  private func workspaceTargetTitle(_ workspace: AgentWorkspace, routeKind: AgentRouteKind) -> String {
    if routeKind == .desktopAgent {
      return workspace.agentId.ifBlank(workspace.deviceId).ifBlank("Desktop Agent")
    }
    return workspace.agentId.ifBlank("GalaxySSI")
  }

  private func workspaceResultText(_ workspace: AgentWorkspace) -> String {
    if !workspace.errorMessage.isBlank {
      return workspace.errorMessage
    }
    let clean = workspace.resultJson.trimmingCharacters(in: .whitespacesAndNewlines)
    return clean == "{}" ? "" : clean
  }

  static func sortedAgentTasks(_ records: [AgentTaskRecord]) -> [AgentTaskRecord] {
    records.sorted { left, right in
      let leftTime = max(left.updatedAtMillis, left.createdAtMillis)
      let rightTime = max(right.updatedAtMillis, right.createdAtMillis)
      if leftTime != rightTime {
        return leftTime > rightTime
      }
      return left.taskId > right.taskId
    }
  }

  private static func formatMillis(_ value: Int64) -> String {
    guard value > 0 else { return "" }
    let formatter = DateFormatter()
    formatter.dateFormat = "MM-dd HH:mm:ss"
    return formatter.string(from: Date(timeIntervalSince1970: Double(value) / 1_000))
  }
}
