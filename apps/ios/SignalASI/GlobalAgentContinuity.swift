import Foundation

struct GlobalEventQueueState: Codable, Equatable {
  var ready: [GlobalConversationEvent]
  var overflow: [GlobalConversationEvent]

  init(
    ready: [GlobalConversationEvent] = [],
    overflow: [GlobalConversationEvent] = []
  ) {
    self.ready = ready
    self.overflow = overflow
  }
}

struct GlobalEventQueueMutation: Equatable {
  var state: GlobalEventQueueState
  var acceptedCount: Int
  var capacityRejected: [GlobalConversationEvent]

  init(
    state: GlobalEventQueueState,
    acceptedCount: Int,
    capacityRejected: [GlobalConversationEvent] = []
  ) {
    self.state = state
    self.acceptedCount = max(acceptedCount, 0)
    self.capacityRejected = capacityRejected
  }
}

struct GlobalDeadLetterReplayMutation: Equatable {
  var queueState: GlobalEventQueueState
  var deadLetters: [GlobalDeadLetterEvent]
  var replayed: Bool
  var enqueuedEvent: GlobalConversationEvent?

  init(
    queueState: GlobalEventQueueState,
    deadLetters: [GlobalDeadLetterEvent],
    replayed: Bool,
    enqueuedEvent: GlobalConversationEvent? = nil
  ) {
    self.queueState = queueState
    self.deadLetters = deadLetters
    self.replayed = replayed
    self.enqueuedEvent = enqueuedEvent
  }
}

enum GlobalEventQueuePolicy {
  static let defaultReadyCapacity = 2_000
  static let defaultOverflowCapacity = 8_000

  static func enqueue(
    state: GlobalEventQueueState,
    incoming: [GlobalConversationEvent],
    deadLetterEventIds: Set<String> = [],
    readyCapacity: Int = defaultReadyCapacity,
    overflowCapacity: Int = defaultOverflowCapacity
  ) -> GlobalEventQueueMutation {
    precondition(readyCapacity > 0)
    precondition(overflowCapacity >= 0)

    var knownIds = Set<String>()
    for event in state.ready + state.overflow where !event.id.isBlank {
      knownIds.insert(event.id)
    }
    for id in deadLetterEventIds where !id.isBlank {
      knownIds.insert(id)
    }

    let additions = incoming.filter { event in
      guard !event.id.isBlank else { return false }
      return knownIds.insert(event.id).inserted
    }
    if additions.isEmpty {
      return GlobalEventQueueMutation(state: state, acceptedCount: 0)
    }

    let readyRoom = max(readyCapacity - state.ready.count, 0)
    let readyAdditions = Array(additions.prefix(readyRoom))
    let remaining = Array(additions.dropFirst(readyAdditions.count))
    let overflowRoom = max(overflowCapacity - state.overflow.count, 0)
    let overflowAdditions = Array(remaining.prefix(overflowRoom))
    let rejected = Array(remaining.dropFirst(overflowAdditions.count))

    return GlobalEventQueueMutation(
      state: GlobalEventQueueState(
        ready: state.ready + readyAdditions,
        overflow: state.overflow + overflowAdditions
      ),
      acceptedCount: additions.count,
      capacityRejected: rejected
    )
  }

  static func removeAndPromote(
    state: GlobalEventQueueState,
    removedEventIds: Set<String>,
    readyCapacity: Int = defaultReadyCapacity
  ) -> GlobalEventQueueState {
    precondition(readyCapacity > 0)
    if removedEventIds.isEmpty && state.ready.count >= readyCapacity {
      return state
    }

    let remainingReady = Array(
      state.ready
        .filter { !removedEventIds.contains($0.id) }
        .prefix(readyCapacity)
    )
    let remainingOverflow = state.overflow.filter { !removedEventIds.contains($0.id) }
    let promoteCount = max(readyCapacity - remainingReady.count, 0)
    return GlobalEventQueueState(
      ready: remainingReady + Array(remainingOverflow.prefix(promoteCount)),
      overflow: Array(remainingOverflow.dropFirst(promoteCount))
    )
  }
}

struct GlobalPrivateDeletionArtifactCleanup: Equatable {
  var queueState: GlobalEventQueueState
  var contextJournal: [GlobalConversationEvent]
  var removedEventIds: Set<String>
}

enum GlobalPrivateDeletionArtifactPolicy {
  static func cleanup(
    queueState: GlobalEventQueueState,
    contextJournal: [GlobalConversationEvent],
    readyCapacity: Int = GlobalEventQueuePolicy.defaultReadyCapacity
  ) -> GlobalPrivateDeletionArtifactCleanup {
    let allEvents = queueState.ready + queueState.overflow + contextJournal
    let removedIDs = Set(allEvents.filter(isLegacyPrivateDeletion).map(\.id))
    return GlobalPrivateDeletionArtifactCleanup(
      queueState: GlobalEventQueuePolicy.removeAndPromote(
        state: queueState,
        removedEventIds: removedIDs,
        readyCapacity: readyCapacity
      ),
      contextJournal: contextJournal.filter { !removedIDs.contains($0.id) },
      removedEventIds: removedIDs
    )
  }

  private static func isLegacyPrivateDeletion(_ event: GlobalConversationEvent) -> Bool {
    event.type == .conversationDeleted && event.sensitivity == .sessionPrivate
  }
}

enum GlobalDeadLetterRecoveryPolicy {
  static func replay(
    state: GlobalEventQueueState,
    deadLetters: [GlobalDeadLetterEvent],
    eventId: String,
    readyCapacity: Int = GlobalEventQueuePolicy.defaultReadyCapacity,
    overflowCapacity: Int = GlobalEventQueuePolicy.defaultOverflowCapacity
  ) -> GlobalDeadLetterReplayMutation {
    guard let letter = deadLetters.first(where: { $0.event.id == eventId }) else {
      return GlobalDeadLetterReplayMutation(queueState: state, deadLetters: deadLetters, replayed: false)
    }

    let queuedIds = Set((state.ready + state.overflow).map(\.id))
    if queuedIds.contains(eventId) {
      return GlobalDeadLetterReplayMutation(
        queueState: state,
        deadLetters: deadLetters.filter { $0.event.id != eventId },
        replayed: true
      )
    }

    let mutation = GlobalEventQueuePolicy.enqueue(
      state: state,
      incoming: [letter.event],
      deadLetterEventIds: Set(
        deadLetters
          .map { $0.event.id }
          .filter { $0 != eventId }
      ),
      readyCapacity: readyCapacity,
      overflowCapacity: overflowCapacity
    )
    let queued = (mutation.state.ready + mutation.state.overflow).contains { $0.id == eventId }
    if !queued {
      return GlobalDeadLetterReplayMutation(queueState: state, deadLetters: deadLetters, replayed: false)
    }

    return GlobalDeadLetterReplayMutation(
      queueState: mutation.state,
      deadLetters: deadLetters.filter { $0.event.id != eventId },
      replayed: true,
      enqueuedEvent: letter.event
    )
  }
}

enum GlobalDeadLetterUpgradeRecoveryPolicy {
  static let defaultRecoveryLimit = 64
  private static let maxRecoveryLimit = 256

  static func eligible(
    _ letter: GlobalDeadLetterEvent,
    currentVersionCode: Int
  ) -> Bool {
    currentVersionCode > 0 &&
      letter.quarantinedVersionCode < currentVersionCode &&
      letter.lastAutoRecoveryVersionCode < currentVersionCode
  }

  static func select(
    _ deadLetters: [GlobalDeadLetterEvent],
    currentVersionCode: Int,
    limit: Int = defaultRecoveryLimit
  ) -> [GlobalDeadLetterEvent] {
    let boundedLimit = min(max(limit, 1), maxRecoveryLimit)
    return deadLetters
      .filter { eligible($0, currentVersionCode: currentVersionCode) }
      .sorted { left, right in
        if left.quarantinedAtMillis == right.quarantinedAtMillis {
          return left.event.id < right.event.id
        }
        return left.quarantinedAtMillis < right.quarantinedAtMillis
      }
      .prefix(boundedLimit)
      .map { $0 }
  }

  static func markAttempted(
    _ letter: GlobalDeadLetterEvent,
    currentVersionCode: Int
  ) -> GlobalDeadLetterEvent {
    var copy = letter
    copy.lastAutoRecoveryVersionCode = max(
      letter.lastAutoRecoveryVersionCode,
      max(currentVersionCode, 0)
    )
    return copy
  }
}

enum GlobalEventRetryPolicy {
  static let maxAttempts = 3

  static func recordFailure(
    eventId: String,
    previous: GlobalEventProcessingFailure?,
    error: Error,
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis()
  ) -> GlobalEventProcessingFailure {
    let attempt = (previous?.attemptCount ?? 0) + 1
    let reason = naturalReason(error)
    let quarantined = attempt >= maxAttempts
    let previousFirstFailure = previous?.firstFailedAtMillis ?? 0
    return GlobalEventProcessingFailure(
      eventId: eventId,
      attemptCount: attempt,
      firstFailedAtMillis: previousFirstFailure > 0 ? previousFirstFailure : nowMillis,
      lastFailedAtMillis: nowMillis,
      nextAttemptAtMillis: quarantined ? 0 : nowMillis + retryDelayMillis(attemptCount: attempt),
      errorFingerprint: GlobalAgentText.stableKey(String(describing: type(of: error)), reason),
      reason: reason,
      quarantined: quarantined
    )
  }

  static func capacityFailure(
    eventId: String,
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis()
  ) -> GlobalEventProcessingFailure {
    GlobalEventProcessingFailure(
      eventId: eventId,
      attemptCount: 0,
      firstFailedAtMillis: nowMillis,
      lastFailedAtMillis: nowMillis,
      nextAttemptAtMillis: 0,
      errorFingerprint: GlobalAgentText.stableKey("event_queue_capacity", eventId),
      reason: "The durable Agent event queue reached its safety capacity",
      quarantined: true
    )
  }

  static func eligible(
    _ failure: GlobalEventProcessingFailure?,
    nowMillis: Int64
  ) -> Bool {
    guard let failure else { return true }
    return !failure.quarantined && failure.nextAttemptAtMillis <= nowMillis
  }

  static func retryDelayMillis(attemptCount: Int) -> Int64 {
    switch max(attemptCount, 1) {
    case 1:
      return 30_000
    case 2:
      return 2 * 60 * 1_000
    default:
      return 10 * 60 * 1_000
    }
  }

  private static func naturalReason(_ error: Error) -> String {
    let localized = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    let compact = localized
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .prefix(500)
    if !compact.isEmpty { return String(compact) }
    let fallback = String(describing: type(of: error))
    return fallback.isEmpty ? "Event processing failed" : fallback
  }
}
