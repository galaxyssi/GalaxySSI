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

struct VoiceAppNavigationRequest {
  enum Destination: String, CaseIterable {
    case agent, newConversation = "new_conversation", contact, news, phone
  }
  let destination: Destination
  let conversationID: String
  let contactID: String
  let message: String
}

struct VoiceAppEntryContext: Equatable {
  let surface: VoiceAppCaptureAnchor.Surface
  var contactID = ""
  var articleID = ""
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
  private var observedContacts: [UUID: Set<String>] = [:]
  private var navigationOwner: UUID?
  private var navigation: ((VoiceAppNavigationRequest) -> AgentNativeToolExecutionResult)?
  private var voiceEntry: ((VoiceAppEntryContext) -> Void)?

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

  func recordObservedContacts(_ ids: [String], anchor: VoiceAppCaptureAnchor) {
    guard anchor.expiresAt > now() else { return }
    var known = observedContacts[anchor.owner] ?? []
    for id in ids where !id.isBlank && known.count < 64 { known.insert(id) }
    observedContacts[anchor.owner] = known
  }

  func hasObservedContact(_ id: String, anchor: VoiceAppCaptureAnchor) -> Bool {
    !id.isBlank && (anchor.contactID == id || observedContacts[anchor.owner]?.contains(id) == true)
  }

  func installNavigation(owner: UUID, handle: @escaping (VoiceAppNavigationRequest) -> AgentNativeToolExecutionResult,
                         openVoice: ((VoiceAppEntryContext) -> Void)? = nil) {
    navigationOwner = owner
    navigation = handle
    voiceEntry = openVoice
  }

  func removeNavigation(owner: UUID) {
    guard navigationOwner == owner else { return }
    navigationOwner = nil
    navigation = nil
    voiceEntry = nil
  }

  func openVoice(_ entry: VoiceAppEntryContext) { voiceEntry?(entry) }

  func navigate(_ request: VoiceAppNavigationRequest, anchor: VoiceAppCaptureAnchor) -> AgentNativeToolExecutionResult {
    guard isForegroundOwner(anchor), request.conversationID == anchor.conversationID, let navigation else {
      return .failure(code: "navigation_unavailable", message: "The original voice window is no longer available.")
    }
    return navigation(request)
  }

  func clear() {
    activeOwner = nil
    turns.removeAll()
    order.removeAll()
    observedContacts.removeAll()
  }

  private func prune() {
    let time = now()
    order.removeAll {
      if let anchor = turns[$0], anchor.expiresAt > time { return false }
      if let anchor = turns.removeValue(forKey: $0) { observedContacts.removeValue(forKey: anchor.owner) }
      return true
    }
    if order.count > 64 {
      let excess = order.count - 64
      for key in order.prefix(excess) {
        if let anchor = turns.removeValue(forKey: key) { observedContacts.removeValue(forKey: anchor.owner) }
      }
      order.removeFirst(excess)
    }
  }
}
