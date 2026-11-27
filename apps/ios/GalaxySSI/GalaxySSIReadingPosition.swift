import Foundation

enum GalaxySSIReadingPosition {
  struct Entry: Equatable {
    let id: String
    let turn: String
    let at: Date
    let reply: Bool
    let request: Bool
  }
  struct Snapshot: Equatable {
    let scope: String
    let entries: [Entry]
    init(scope: String, entries: [Entry]) { self.scope = scope; self.entries = entries }
    init(scope: String, messages: [ChatMessage]) {
      self.scope = scope
      entries = messages.map { message in
        let approval = AgentRichContentCodec.decode(message.richOutputJson).contains { $0.type == .approval }
        let body = !message.content.isBlank || !message.richOutputJson.isBlank
        return Entry(id: message.id.uuidString, turn: message.turnId.ifBlank(message.id.uuidString), at: message.createdAt,
          reply: !message.isMine && !message.isSystem && body && message.deliveryStatus != .failed && !approval &&
            !CloudSupervisedResearch.isTranscriptControlReply(message) &&
            !AgentModelPlanParser.containsUnexecutedControlReply(message.content) &&
            !message.remoteMessageId.hasPrefix("agent-stream-preview-") &&
            !message.remoteMessageId.hasPrefix(AgentReplyWaitingIndicatorPolicy.dedupePrefix) &&
            !message.deliveryTrace.contains { $0.stage.hasPrefix("delivery-failed:") },
          request: message.isMine && !message.isSystem && !message.turnId.isBlank)
      }
    }
  }

  static func newReply(previous: Snapshot?, current: Snapshot) -> Bool {
    guard let previous, previous.scope == current.scope, !current.scope.isBlank,
          !previous.entries.isEmpty, !current.entries.isEmpty,
          let last = previous.entries.map(\.at).max() else { return false }
    let seen = Set(previous.entries.filter(\.reply).map(\.turn))
    let open = Set(previous.entries.filter(\.request).map(\.turn)).subtracting(seen)
    let ids = Set(previous.entries.map(\.id))
    let boundary = current.entries.lastIndex { ids.contains($0.id) }
    return current.entries.enumerated().contains { index, row in
      row.reply && !seen.contains(row.turn) && (open.contains(row.turn) || row.at > last ||
        (row.at == last && boundary.map { index > $0 } == true))
    }
  }

  static func nearestKeys(_ keys: [String], index: Int) -> [String] {
    guard keys.indices.contains(index) else { return [] }
    return keys.indices.sorted {
      abs($0 - index) == abs($1 - index) ? $0 > $1 : abs($0 - index) < abs($1 - index)
    }.map { keys[$0] }
  }
}
