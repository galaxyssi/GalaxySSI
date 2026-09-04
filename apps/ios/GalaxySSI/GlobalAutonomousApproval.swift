import Foundation

extension GlobalAgentDeliberationStore {
  @discardableResult
  func approveAutonomousRun(
    runId: String,
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis()
  ) -> Bool {
    guard let run = autonomousRuns().first(where: { $0.id == runId }),
          run.actions.contains(where: { $0.status == .waitingConfirmation }) else {
      return false
    }
    return updateAutonomousRun(runId: runId) { current in
      var updated = current
      updated.actions = current.actions.map { action in
        guard action.status == .waitingConfirmation else { return action }
        var approved = action
        approved.confirmationGranted = true
        approved.status = .pending
        approved.leaseExpiresAtMillis = 0
        approved.lastError = ""
        return approved
      }
      updated.status = .queued
      updated.nextAttemptAtMillis = max(nowMillis, 0)
      updated.leaseExpiresAtMillis = 0
      updated.lastError = ""
      updated.updatedAtMillis = max(nowMillis, 0)
      return updated
    } != nil
  }

  @discardableResult
  func rejectAutonomousRun(
    runId: String,
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis()
  ) -> Bool {
    guard let run = autonomousRuns().first(where: { $0.id == runId }),
          run.actions.contains(where: { $0.status == .waitingConfirmation }) else {
      return false
    }
    return updateAutonomousRun(runId: runId) { current in
      var updated = current
      updated.actions = current.actions.map { action in
        guard action.status == .waitingConfirmation else { return action }
        var rejected = action
        rejected.status = .skipped
        rejected.confirmationGranted = false
        rejected.lastError = "The user declined this external effect"
        rejected.completedAtMillis = max(nowMillis, 0)
        rejected.leaseExpiresAtMillis = 0
        return rejected
      }
      updated.status = .paused
      updated.nextAttemptAtMillis = 0
      updated.leaseExpiresAtMillis = 0
      updated.lastError = "The user declined this external effect"
      updated.updatedAtMillis = max(nowMillis, 0)
      return updated
    } != nil
  }
}
