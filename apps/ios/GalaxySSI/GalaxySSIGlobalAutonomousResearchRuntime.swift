import Foundation

extension GalaxySSIGlobalAgentRuntimeBridge {
  @discardableResult
  static func consumeAutonomousResearchResponse(
    _ response: AgentConnectorResponse,
    settings: GlobalAgentSettings = .default,
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis()
  ) -> Bool {
    let researchStore = GalaxySSIGlobalResearchRuntimeStore()
    let state = researchStore.state()
    guard let task = state.tasks.first(where: { candidate in
      candidate.id.hasPrefix("autonomous-research:") &&
        (!response.taskId.isBlank ? candidate.id == response.taskId : candidate.sourceMessageId == response.sourceMessageId)
    }), [.completed, .failed].contains(task.status) else {
      return false
    }

    let parts = task.id.split(separator: ":", maxSplits: 2).map(String.init)
    guard parts.count == 3, parts[0] == "autonomous-research" else { return false }
    let runId = parts[1]
    let actionId = parts[2]
    let deliberationStore = GlobalAgentDeliberationStore()
    guard let run = deliberationStore.autonomousRuns().first(where: { $0.id == runId }),
          let action = run.actions.first(where: { $0.id == actionId }) else {
      return false
    }

    let result = task.result.ifBlank(task.lastError).ifBlank(response.content)
    let evidence = GlobalActionEvidence(
      kind: .researchLedger,
      summary: String(result.prefix(2_000)),
      sourceRef: "encrypted://global-agent/research/\(task.id)",
      confidence: task.evidenceLedger.overallConfidence,
      verified: task.evidenceLedger.verified,
      createdAtMillis: nowMillis
    )
    let contract = action.verificationContract.criteria.isEmpty
      ? GlobalActionVerificationPolicy.defaultContract(action: action)
      : action.verificationContract
    let evidenceHistory = Array((action.evidence + [evidence]).suffix(24))
    let verification = GlobalActionVerificationPolicy.evaluate(
      contract: contract,
      evidence: evidenceHistory
    )
    let accepted = [.supported, .verified].contains(verification)
    guard let updated = deliberationStore.updateAutonomousRun(runId: runId, transform: { current in
      var next = current
      next.actions = current.actions.map { candidate in
        guard candidate.id == actionId else { return candidate }
        var copy = candidate
        copy.status = accepted ? .completed : .failed
        copy.result = String(result.prefix(12_000))
        copy.evidence = evidenceHistory
        copy.verificationContract = contract
        copy.verificationStatus = verification
        copy.lastError = accepted ? "" : "Research evidence did not satisfy the step contract"
        copy.sourceMessageId = 0
        copy.leaseExpiresAtMillis = 0
        copy.completedAtMillis = nowMillis
        return copy
      }
      next.status = GlobalAutonomousRunPolicy.terminalStatus(next.actions) ??
        (next.actions.contains(where: { $0.status == .pending }) ? .queued : .waitingForResource)
      next.nextAttemptAtMillis = next.status == .queued ? nowMillis : 0
      next.leaseExpiresAtMillis = 0
      next.lastError = accepted ? "" : "Research evidence did not satisfy the step contract"
      next.updatedAtMillis = nowMillis
      return next
    }) else {
      return false
    }

    if GlobalAutonomousReplanPolicy.shouldReview(
      run: updated,
      action: updated.actions.first(where: { $0.id == actionId }) ?? action,
      succeeded: accepted,
      result: result,
      enabled: settings.dynamicAutonomousReplanningEnabled,
      maxReplans: settings.maxAutonomousReplans
    ) {
      deliberationStore.upsertAutonomousRun(
        GlobalAutonomousReplanPolicy.requestReview(
          run: updated,
          reason: "New research evidence may change the remaining plan",
          nowMillis: nowMillis
        )
      )
    }
    return true
  }
}
