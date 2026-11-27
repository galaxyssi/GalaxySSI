import Foundation

struct AgentTurnReceiptCloudCapture {
  let store: AgentTurnReceiptStore
  let key: AgentTurnReceiptStore.Key
  let requestedModel: String
  func started(_ request: ModelStreamRequest) -> String {
    let body = (try? CloudModelStreamJSON.object(from: request.bodyJson)) ?? [:]
    return store.cloudStarted(key, model: (body["model"] as? String) ?? requestedModel)
  }
  func response(_ attempt: String, model: String?, effort: String? = nil) {
    store.cloudResponse(key, attempt: attempt, actual: model, effort: effort)
  }
}

struct AgentTurnReceiptStreamClient: CloudModelStreamClient {
  let base: CloudModelStreamClient
  let capture: AgentTurnReceiptCloudCapture?
  func stream(_ request: ModelStreamRequest) -> AsyncThrowingStream<ModelStreamEvent, Error> {
    guard let capture else { return base.stream(request) }
    return AsyncThrowingStream { continuation in
      let attempt = capture.started(request)
      let worker = Task {
        do {
          for try await event in base.stream(request) {
            try Task.checkCancellation()
            if case .completed(let completed) = event, completed.requestId == request.requestId {
              capture.response(attempt, model: completed.reportedModel)
            }
            continuation.yield(event)
          }
          continuation.finish()
        } catch { continuation.finish(throwing: error) }
      }
      continuation.onTermination = { _ in worker.cancel() }
    }
  }
  func cancel(requestId: String, reason: ModelStreamCancelReason) async {
    await base.cancel(requestId: requestId, reason: reason)
  }
}

extension GalaxySSIStore {
  func turnReceiptCloudCapture(conversation: String, turn: String, model: String) -> AgentTurnReceiptCloudCapture? {
    guard let key = turnReceiptKey(conversation: conversation, turn: turn) else { return nil }
    return AgentTurnReceiptCloudCapture(store: turnReceiptStore, key: key, requestedModel: model)
  }
}
