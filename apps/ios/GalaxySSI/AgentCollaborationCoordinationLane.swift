import Foundation

enum AgentCollaborationAdmissionCapacity {
  static let workersPerRun = 3
  static let sharedCoordinators = 1

  static var wire: AgentMcpJSONObject {
    ["worker_limit_per_run": .int(Int64(workersPerRun)), "coordinator_limit_shared": .int(Int64(sharedCoordinators)),
     "maximum_single_run": .int(Int64(workersPerRun + sharedCoordinators)),
     "coordination_lane": .string("host_live_planning"), "downstream_capacity_reserved": .bool(false)]
  }
}

@MainActor
final class AgentCollaborationCoordinationLane {
  static let shared = AgentCollaborationCoordinationLane()
  private static let queueLimit = 32

  struct Lease: Equatable {
    fileprivate let id: UUID
    let owner: AgentCollaborationToolEvidenceScope
    let resourceID: String
  }

  enum Failure: Error { case unavailable }

  private struct Waiter {
    let lease: Lease
    let continuation: CheckedContinuation<Lease?, Never>
  }

  private var active: Lease?
  private var waiters: [Waiter] = []
  var available: Bool { active == nil && waiters.isEmpty }
  var queuedCount: Int { waiters.count }

  static func validate(_ scope: AgentCollaborationToolEvidenceScope, resourceID: String,
      store: GalaxySSIStore, profileID: String) throws {
    try Task.checkCancellation()
    guard store.profile.identityFingerprint == profileID,
          let session = store.agentSession(id: scope.conversationId), session.id == scope.conversationId,
          !session.privateMode, !session.trackingPaused, session.mergedIntoConversationId.isBlank,
          let roster = session.collaborationRoster, let member = scope.rosterMember(in: roster),
          roster.coordinatorId == member.id, member.resourceId == resourceID,
          let parent = store.agentTask(id: scope.turnId), parent.sessionId == scope.conversationId,
          !parent.blocked, parent.phase == .executing || parent.phase == .waitingResponse,
          !PhoneExecutionAuthority.isCancelled(taskId: scope.turnId) else { throw CancellationError() }
    try AgentTeamExecutionHistoryStore.shared.requireGoalCoordinationAuthority(scope, resourceID: resourceID)
  }

  func acquireIfAvailable(owner: AgentCollaborationToolEvidenceScope, resourceID: String) -> Lease? {
    guard available, !Task.isCancelled, !resourceID.isBlank else { return nil }
    let lease = Lease(id: UUID(), owner: owner, resourceID: resourceID)
    active = lease
    return lease
  }

  func withLease<T>(owner: AgentCollaborationToolEvidenceScope, resourceID: String,
      validate: () throws -> Void, operation: () async throws -> T) async throws -> T {
    try validate()
    let lease = try await acquire(owner: owner, resourceID: resourceID)
    defer { release(lease) }
    try Task.checkCancellation()
    try validate()
    return try await operation()
  }

  func release(_ lease: Lease) {
    guard active == lease else { return }
    active = nil
    if !waiters.isEmpty {
      let waiter = waiters.removeFirst()
      active = waiter.lease
      waiter.continuation.resume(returning: waiter.lease)
    }
  }

  private func acquire(owner: AgentCollaborationToolEvidenceScope, resourceID: String) async throws -> Lease {
    try Task.checkCancellation()
    if let lease = acquireIfAvailable(owner: owner, resourceID: resourceID) { return lease }
    guard !resourceID.isBlank, active?.owner != owner, !waiters.contains(where: { $0.lease.owner == owner }),
          waiters.count < Self.queueLimit else { throw Failure.unavailable }
    let request = Lease(id: UUID(), owner: owner, resourceID: resourceID)
    let granted: Lease? = await withTaskCancellationHandler(operation: {
      await withCheckedContinuation { continuation in
        if Task.isCancelled { continuation.resume(returning: nil) }
        else if available { active = request; continuation.resume(returning: request) }
        else { waiters.append(.init(lease: request, continuation: continuation)) }
      }
    }, onCancel: {
      Task { @MainActor in self.cancelWaiting(request.id) }
    })
    guard let granted else { throw CancellationError() }
    return granted
  }

  private func cancelWaiting(_ id: UUID) {
    guard let index = waiters.firstIndex(where: { $0.lease.id == id }) else { return }
    waiters.remove(at: index).continuation.resume(returning: nil)
  }
}

@MainActor
final class AgentGoalWorkAdmissionOrder {
  private var next = 0
  private var held = false
  private var waiters: [Int: CheckedContinuation<Bool, Never>] = [:]
  private var cancelled: Set<Int> = []
  private(set) var claimedIDs: [String] = []

  func wait(for index: Int) async -> Bool {
    guard index >= next, !cancelled.contains(index) else { return false }
    if Task.isCancelled { cancelWaiting(index); return false }
    if index == next, !held { held = true; return true }
    return await withTaskCancellationHandler(operation: {
      await withCheckedContinuation { continuation in
        if Task.isCancelled || index < next || cancelled.contains(index) {
          cancelWaiting(index)
          continuation.resume(returning: false)
        } else if index == next, !held {
          held = true
          continuation.resume(returning: true)
        } else if index > next, waiters[index] == nil {
          waiters[index] = continuation
        } else { continuation.resume(returning: false) }
      }
    }, onCancel: {
      Task { @MainActor in self.cancelWaiting(index) }
    })
  }

  func finish(_ index: Int, claimedID: String?) {
    precondition(index == next && held)
    if let claimedID { claimedIDs.append(claimedID) }
    held = false
    next += 1
    advance()
  }

  private func cancelWaiting(_ index: Int) {
    guard index >= next, index != next || !held else { return }
    cancelled.insert(index)
    waiters.removeValue(forKey: index)?.resume(returning: false)
    advance()
  }

  private func advance() {
    guard !held else { return }
    while cancelled.remove(next) != nil { next += 1 }
    if let waiter = waiters.removeValue(forKey: next) {
      held = true
      waiter.resume(returning: true)
    }
  }
}
