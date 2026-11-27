import Foundation

struct AgentFileReceipt: Codable, Equatable {
  enum Wire: String, Codable { case uploading, retrying, failed, stored, closed }
  enum Reading: String, Codable { case recognized, unreadable }
  var transfer: String?
  var peer: String?
  var wire: Wire?
  var generation = 0
  var readTurn: String?
  var readStarted: Int64?
  var reading: Reading?

  static func originals(_ message: ChatMessage) -> [AgentRichBlock] {
    guard message.isMine, !message.isSystem, message.sourceConversationId.isBlank,
      !message.conversationId.isBlank, !message.turnId.isBlank else { return [] }
    let blocks = AgentRichContentCodec.decode(message.richOutputJson).filter {
      $0.metadata["source"] == "user_attachment" && !$0.id.isBlank && [.image, .file].contains($0.type)
    }
    guard (1...10).contains(blocks.count), Set(blocks.map(\.id)).count == blocks.count else { return [] }
    return blocks
  }

  mutating func fold(transfer: String, state: Wire, fingerprint: String = "", generation: Int = 0) -> Bool {
    guard MqttRouteProtocol.hex(transfer, count: 64), (0...3).contains(generation),
      self.transfer == nil || self.transfer == transfer else { return false }
    if self.transfer == transfer, self.generation == generation, wire == state { return true }
    if state == .uploading {
      guard wire == nil, !fingerprint.isBlank else { return false }
      peer = fingerprint
    } else {
      guard self.transfer == transfer, self.generation == generation, wire != .stored, wire != .closed else { return false }
      if state == .retrying { guard wire == .failed else { return false } }
    }
    self.transfer = transfer; self.generation = generation; wire = state
    return true
  }

  mutating func restart(transfer: String, fingerprint: String, generation: Int) -> Bool {
    guard wire == .failed, self.transfer == transfer, peer == fingerprint, !fingerprint.isBlank,
      generation == self.generation + 1, generation <= 3 else { return false }
    self.generation = generation; wire = .retrying
    return true
  }

  mutating func beginRead(turn: String, now: Int64) -> Bool {
    guard !turn.isBlank, now > 0, reading != .recognized,
      readStarted.map({ now >= $0 && now - $0 >= 30_000 }) ?? true else { return false }
    readTurn = turn; readStarted = now; reading = nil
    return true
  }
  mutating func report(turn: String, original: String, recognized: Bool) -> Bool {
    guard turn == (readTurn ?? original) else { return false }
    reading = recognized ? .recognized : .unreadable
    return true
  }
}

struct AgentFileReadSource: Codable, Equatable {
  let turn: String
  let digest: String
}

extension Notification.Name {
  static let galaxySSIAgentFileReceiptChanged = Notification.Name("galaxyssi.agent.file-receipt.changed")
}
