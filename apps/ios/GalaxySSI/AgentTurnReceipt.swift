import Foundation

struct AgentTurnReceipt: Codable, Equatable {
  var files: [String: AgentFileReceipt]?
  var fileReadSource: AgentFileReadSource?
  var sent: Int64?, body: Int64?, bodyMillis: Int64?, desktopReceived: Int64?, resultAt: Int64?
  var mode: String?, requested: String?, effort: String?, wire: String?, wireEffort: String?, taskSHA: String?
  var generation: Int64?, attempt: Int?, provider: String?, submitted: String?, submittedEffort: String?
  var cloudAttempt: String?, cloudRequested: String?, cloudActual: String?, cloudEffort: String?, localProfile: String?
  var phoneExecuted: Bool?, desktopExecuted: Bool?

  mutating func clearSubmission() {
    attempt = nil; provider = nil; submitted = nil; submittedEffort = nil; resultAt = nil
  }
}

enum AgentTurnReceiptEvidence {
  static func identifier(_ value: Any?) -> String {
    guard let text = value as? String,
          let range = text.range(of: #"^[A-Za-z0-9][A-Za-z0-9_./:+@-]{0,119}$"#, options: .regularExpression),
          range.lowerBound == text.startIndex, range.upperBound == text.endIndex else { return "" }
    return text
  }
  static func hash(_ value: String) -> String { AgentMcpJSONCodec.sha256(["value": .string(value)]) }
  static func integer(_ value: Any?, minimum: Int64 = 0) -> Int64? {
    AgentDesktopReplyRecovery.integer(value, minimum: minimum)
  }
  struct Desktop {
    let generation: Int64
    let received: Int64?
    let attempt: Int
    let provider: String
    let model: String
    let effort: String
    let terminal: Bool
  }
  static func desktop(_ payload: [String: Any]) -> Desktop? {
    guard let task = payload["task_id"] as? String, !task.isBlank,
          let generation = integer(payload["execution_generation"] ?? NSNumber(value: 1), minimum: 1) else { return nil }
    var received = (payload["delivery_trace"] as? [[String: Any]] ?? []).prefix(128).compactMap { event -> Int64? in
      event["stage"] as? String == "desktop_mqtt_received" ? integer(event["at"], minimum: 1) : nil
    }.min()
    let receipt = (payload["turn_receipt"] as? [String: Any]).flatMap {
      integer($0["generation"], minimum: 1) == generation ? $0 : nil
    }
    if received == nil { received = integer(receipt?["desktop_received_at"], minimum: 1) }
    var events = Array((payload["events"] as? [[String: Any]] ?? []).prefix(256))
    if let event = payload["progress_event"] as? [String: Any] { events.append(event) }
    var best = 0, provider = "", model = "", effort = ""
    for event in events {
      guard let kind = event["kind"] as? String, ["agent", "model"].contains(kind),
            let meta = event["metadata"] as? [String: Any], let attempt = integer(meta["attempt"], minimum: 1), attempt <= 10_000,
            event["event_id"] as? String == "provider:\(task):\(attempt - 1)",
            integer(meta["execution_generation"] ?? NSNumber(value: 1), minimum: 1) == generation,
            !identifier(meta["provider"]).isEmpty, attempt >= Int64(best) else { continue }
      best = Int(attempt); provider = identifier(meta["provider"])
      model = identifier(meta["model"]); effort = identifier(meta["reasoning_effort"])
    }
    if let replay = receipt?["submission"] as? [String: Any], let attempt = integer(replay["attempt"], minimum: 1),
       attempt <= 10_000, attempt >= Int64(best), !identifier(replay["provider"]).isEmpty {
      best = Int(attempt); provider = identifier(replay["provider"])
      model = identifier(replay["model"]); effort = identifier(replay["effort"])
    }
    return Desktop(generation: generation, received: received, attempt: best, provider: provider,
      model: model, effort: effort, terminal: payload["type"] as? String == "text")
  }
}
