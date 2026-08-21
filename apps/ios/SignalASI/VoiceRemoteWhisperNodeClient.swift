import Foundation

typealias VoiceRemoteWhisperPublisher = (String, [String: Any]) async -> Bool

enum VoiceRemoteWhisperClientError: LocalizedError, Equatable {
  case invalidRequest
  case publishFailed
  case timedOut
  case failed(code: String, message: String)

  var errorDescription: String? {
    switch self {
    case .invalidRequest:
      return "Remote Whisper request is invalid."
    case .publishFailed:
      return "Remote Whisper audio could not be delivered."
    case .timedOut:
      return "Remote Whisper did not respond before the deadline."
    case let .failed(_, message):
      return message
    }
  }
}

/// Serializes a remote Whisper request against its desktop-issued capability and
/// accepts a reply only while the exact request is still active.
@MainActor
final class VoiceRemoteWhisperNodeClient {
  static let shared = VoiceRemoteWhisperNodeClient()
  static let defaultTimeoutMillis: Int64 = 180_000

  private struct Pending {
    let request: VoicePreparedRemoteWhisperRequest
    let publish: VoiceRemoteWhisperPublisher
    var continuation: CheckedContinuation<VoiceRemoteWhisperOutcome, Error>?
    var settledOutcome: VoiceRemoteWhisperOutcome?
  }

  private var pending: [String: Pending] = [:]
  private var completedRequestIDs: [String] = []

  func transcribe(
    node: VoiceRemoteWhisperNodeCapability,
    clientID: String,
    voiceSessionID: String,
    transcriptID: String,
    pcm16: [Int16],
    sampleRateHz: Int,
    language: String,
    timeoutMillis: Int64 = defaultTimeoutMillis,
    publish: @escaping VoiceRemoteWhisperPublisher
  ) async throws -> VoiceRemoteWhisperTranscript {
    guard let request = VoiceRemoteWhisperProtocol.prepare(
      node: node,
      clientID: clientID,
      voiceSessionID: voiceSessionID,
      transcriptID: transcriptID,
      pcm16: pcm16,
      sampleRateHz: sampleRateHz,
      language: language,
      authorizedAtMillis: Int64(Date().timeIntervalSince1970 * 1_000)
    ) else {
      throw VoiceRemoteWhisperClientError.invalidRequest
    }
    pending[request.requestID] = Pending(request: request, publish: publish)
    defer { pending.removeValue(forKey: request.requestID) }

    var fullyPublished = false
    do {
      guard await publish(request.desktopID, request.manifest) else {
        throw VoiceRemoteWhisperClientError.publishFailed
      }
      for chunk in request.chunks {
        guard await publish(request.desktopID, chunk) else {
          throw VoiceRemoteWhisperClientError.publishFailed
        }
      }
      fullyPublished = true
      let deadline = max(1_000, timeoutMillis)
      let timeoutTask = Task { @MainActor [weak self] in
        try? await Task.sleep(nanoseconds: UInt64(deadline) * 1_000_000)
        guard !Task.isCancelled else { return }
        self?.settle(
          requestID: request.requestID,
          outcome: .failed(
            requestID: request.requestID,
            code: "timeout",
            message: "Remote Whisper did not respond before the deadline."
          ),
          requestRemoteCancellation: true
        )
      }
      defer { timeoutTask.cancel() }
      let outcome = try await withTaskCancellationHandler(operation: {
        try await waitForOutcome(requestID: request.requestID)
      }, onCancel: { [weak self] in
        Task { @MainActor in
          self?.settle(
            requestID: request.requestID,
            outcome: .failed(
              requestID: request.requestID,
              code: "cancelled",
              message: "Remote Whisper session was cancelled.",
              cancelled: true
            ),
            requestRemoteCancellation: true
          )
        }
      })
      switch outcome {
      case let .completed(transcript):
        return transcript
      case let .failed(_, code, message, _):
        if code == "timeout" { throw VoiceRemoteWhisperClientError.timedOut }
        throw VoiceRemoteWhisperClientError.failed(code: code, message: message)
      }
    } catch {
      if !fullyPublished {
        settle(
          requestID: request.requestID,
          outcome: .failed(
            requestID: request.requestID,
            code: "publish_failed",
            message: "Remote Whisper audio could not be delivered.",
            cancelled: true
          ),
          requestRemoteCancellation: true
        )
      }
      throw error
    }
  }

  @discardableResult
  func handleIncoming(
    _ payload: [String: Any],
    sourceDesktopID: String
  ) -> Bool {
    let type = payload.string("type")
    guard [
      VoiceRemoteWhisperProtocol.resultType,
      VoiceRemoteWhisperProtocol.errorType,
      VoiceRemoteWhisperProtocol.cancelledType
    ].contains(type) else {
      return false
    }
    let requestID = payload.string("request_id")
    guard let holder = pending[requestID] else {
      rememberCompleted(requestID)
      return !requestID.isEmpty
    }
    let source = sourceDesktopID.trimmingCharacters(in: .whitespacesAndNewlines)
    let outcome: VoiceRemoteWhisperOutcome
    if !source.isEmpty && source != holder.request.desktopID {
      outcome = .failed(
        requestID: requestID,
        code: "response_identity_mismatch",
        message: "Remote node identity could not be verified."
      )
    } else {
      outcome = VoiceRemoteWhisperProtocol.parseOutcome(payload, expected: holder.request) ?? .failed(
        requestID: requestID,
        code: "response_invalid",
        message: "Remote Whisper response is invalid."
      )
    }
    settle(requestID: requestID, outcome: outcome)
    return true
  }

  func cancelAll() {
    for requestID in Array(pending.keys) {
      settle(
        requestID: requestID,
        outcome: .failed(
          requestID: requestID,
          code: "cancelled",
          message: "Remote Whisper session was cancelled.",
          cancelled: true
        ),
        requestRemoteCancellation: true
      )
    }
  }

  var pendingCount: Int { pending.count }

  private func waitForOutcome(requestID: String) async throws -> VoiceRemoteWhisperOutcome {
    if let settled = pending[requestID]?.settledOutcome { return settled }
    return try await withCheckedThrowingContinuation { continuation in
      guard var holder = pending[requestID] else {
        continuation.resume(throwing: VoiceRemoteWhisperClientError.invalidRequest)
        return
      }
      if let settled = holder.settledOutcome {
        continuation.resume(returning: settled)
        return
      }
      holder.continuation = continuation
      pending[requestID] = holder
    }
  }

  private func settle(
    requestID: String,
    outcome: VoiceRemoteWhisperOutcome,
    requestRemoteCancellation: Bool = false
  ) {
    guard var holder = pending[requestID], holder.settledOutcome == nil else { return }
    holder.settledOutcome = outcome
    let continuation = holder.continuation
    holder.continuation = nil
    pending[requestID] = holder
    rememberCompleted(requestID)
    if requestRemoteCancellation {
      let cancellation = VoiceRemoteWhisperProtocol.cancelPayload(for: holder.request)
      let publish = holder.publish
      let desktopID = holder.request.desktopID
      Task { _ = await publish(desktopID, cancellation) }
    }
    continuation?.resume(returning: outcome)
  }

  private func rememberCompleted(_ requestID: String) {
    guard !requestID.isEmpty else { return }
    completedRequestIDs.removeAll { $0 == requestID }
    completedRequestIDs.append(requestID)
    if completedRequestIDs.count > 96 {
      completedRequestIDs.removeFirst(completedRequestIDs.count - 96)
    }
  }
}
