import CryptoKit
import Foundation

enum VoiceTranscriptSource {
  case onlinePrimary
  case localFallback
  case accuratePass
  case manualEdit
}

enum VoiceTranscriptArbitrationDecision {
  case commit(TranscriptHypothesis, VoiceTranscriptCommitRecord)
  case correction(TranscriptHypothesis)
  case displayOnly(TranscriptHypothesis)
  case ignored(reasonCode: String)
}

struct VoiceTranscriptCommitRecord: Equatable {
  let transcriptID: String
  let committedRevision: Int
  let committedTextHash: String
  let providerID: String
  let modelProfileID: String?
  let committedAtElapsedNanos: Int64
  let executionID: String?
  let userConfirmed: Bool
}

final class VoiceFinalTranscriptArbiter: @unchecked Sendable {
  private struct State {
    var highestRevision = -1
    var record: VoiceTranscriptCommitRecord?
    var latestTextHash = ""
  }

  private let elapsedNanos: () -> Int64
  private let lock = NSLock()
  private var states: [String: State] = [:]

  init(elapsedNanos: @escaping () -> Int64 = VoiceFinalTranscriptArbiter.defaultElapsedNanos) {
    self.elapsedNanos = elapsedNanos
  }

  func consider(
    hypothesis: TranscriptHypothesis,
    transcriptID: String,
    isFinal: Bool,
    source: VoiceTranscriptSource,
    executionID: String? = nil,
    userConfirmed: Bool = false
  ) -> VoiceTranscriptArbitrationDecision {
    locked {
      let identifier = transcriptID.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !identifier.isEmpty else { return .ignored(reasonCode: "missing_transcript_id") }
      let normalized = hypothesis.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !normalized.isEmpty else { return .ignored(reasonCode: "empty_transcript") }

      var state = states[identifier] ?? State()
      let hash = Self.hash(normalized)
      if hypothesis.revision < state.highestRevision, source != .manualEdit {
        return .ignored(reasonCode: "stale_revision")
      }
      state.highestRevision = max(state.highestRevision, hypothesis.revision)

      if !isFinal, source != .manualEdit {
        guard hash != state.latestTextHash else {
          states[identifier] = state
          return .ignored(reasonCode: "duplicate_partial")
        }
        state.latestTextHash = hash
        states[identifier] = state
        return .displayOnly(hypothesis)
      }

      if state.record == nil {
        if source == .accuratePass {
          states[identifier] = state
          return .correction(hypothesis)
        }
        let record = VoiceTranscriptCommitRecord(
          transcriptID: identifier,
          committedRevision: hypothesis.revision,
          committedTextHash: hash,
          providerID: hypothesis.provider,
          modelProfileID: hypothesis.modelProfileId.nilIfBlank,
          committedAtElapsedNanos: max(0, elapsedNanos()),
          executionID: executionID,
          userConfirmed: userConfirmed || source == .manualEdit
        )
        state.record = record
        state.latestTextHash = hash
        states[identifier] = state
        return .commit(hypothesis, record)
      }

      guard let committed = state.record else {
        states[identifier] = state
        return .ignored(reasonCode: "missing_commit_record")
      }
      states[identifier] = state
      if hash == committed.committedTextHash {
        return .ignored(reasonCode: "duplicate_final")
      }
      if committed.userConfirmed, source != .manualEdit {
        return .ignored(reasonCode: "confirmed_final_locked")
      }
      if source == .manualEdit || source == .accuratePass {
        return .correction(hypothesis)
      }
      return .ignored(reasonCode: "execution_already_committed")
    }
  }

  func committed(transcriptID: String) -> VoiceTranscriptCommitRecord? {
    locked { states[transcriptID.trimmingCharacters(in: .whitespacesAndNewlines)]?.record }
  }

  func clear(transcriptID: String) {
    locked { states.removeValue(forKey: transcriptID.trimmingCharacters(in: .whitespacesAndNewlines)) }
  }

  func clearAll() {
    locked { states.removeAll(keepingCapacity: false) }
  }

  private func locked<T>(_ action: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return action()
  }

  private static func hash(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  private static func defaultElapsedNanos() -> Int64 {
    Int64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
  }
}

private extension String {
  var nilIfBlank: String? {
    let value = trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }
}
