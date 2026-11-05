import Foundation

struct VoiceAppCaptureAnchor: Equatable {
  enum Surface: String { case agent, voice, contact, news }
  let owner: UUID
  let conversationID: String
  let contactID: String
  let articleID: String
  let surface: Surface
  let playbackState: String
  let expiresAt: TimeInterval
}

@MainActor
final class VoiceAppContextStore {
  private struct TurnKey: Hashable {
    let conversation: String
    let turn: String
  }

  private let now: () -> TimeInterval
  private var activeOwner: UUID?
  private var turns: [TurnKey: VoiceAppCaptureAnchor] = [:]
  private var order: [TurnKey] = []

  init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
    self.now = now
  }

  func capture(
    conversationID: String, contactID: String = "", articleID: String = "",
    surface: VoiceAppCaptureAnchor.Surface, playbackState: String = "stopped"
  ) -> VoiceAppCaptureAnchor? {
    guard !conversationID.isBlank else { return nil }
    let owner = UUID()
    activeOwner = owner
    return VoiceAppCaptureAnchor(owner: owner, conversationID: conversationID, contactID: contactID,
      articleID: PublicNewsSpeechBookmark.isKey(articleID) ? articleID : "",
      surface: surface, playbackState: playbackState, expiresAt: now() + 600)
  }

  func bind(_ anchor: VoiceAppCaptureAnchor, conversationID: String, turnID: String) {
    prune()
    guard isForegroundOwner(anchor), anchor.conversationID == conversationID, !turnID.isBlank else { return }
    let key = TurnKey(conversation: conversationID, turn: turnID)
    guard turns[key] == nil, !turns.values.contains(where: { $0.owner == anchor.owner }) else { return }
    turns[key] = anchor
    order.append(key)
    prune()
  }

  func context(conversationID: String, turnID: String) -> VoiceAppCaptureAnchor? {
    prune()
    return turns[TurnKey(conversation: conversationID, turn: turnID)]
  }

  func isForegroundOwner(_ anchor: VoiceAppCaptureAnchor) -> Bool {
    anchor.owner == activeOwner && anchor.expiresAt > now()
  }

  func invalidate(_ anchor: VoiceAppCaptureAnchor?) {
    guard let anchor, anchor.owner == activeOwner else { return }
    activeOwner = nil
  }

  func clear() {
    activeOwner = nil
    turns.removeAll()
    order.removeAll()
  }

  private func prune() {
    let time = now()
    order.removeAll {
      if let anchor = turns[$0], anchor.expiresAt > time { return false }
      turns.removeValue(forKey: $0)
      return true
    }
    if order.count > 64 {
      let excess = order.count - 64
      for key in order.prefix(excess) { turns.removeValue(forKey: key) }
      order.removeFirst(excess)
    }
  }
}
