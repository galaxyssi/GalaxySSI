import CryptoKit
import Foundation

struct AgentReplySpeechTarget: Equatable {
  var responseId: String
  var entryId: String
  var text: String
  var complete: Bool
}

struct AgentReplySpeechCommand: Equatable {
  var cancelSessionId = ""
  var beginSessionId = ""
  var appendedText = ""
  var finishSessionId = ""
  var scheduleCommitSessionId = ""
  var changedEntryIds: Set<String> = []
}

enum AgentReplySpeechPresentationPolicy {
  static func latestTarget(_ messages: [ChatMessage]) -> AgentReplySpeechTarget? {
    messages.reversed().compactMap(target).first
  }

  static func target(_ message: ChatMessage) -> AgentReplySpeechTarget? {
    guard !message.isMine,
          !message.isSystem,
          !excludedRemoteMessagePrefixes.contains(where: message.remoteMessageId.hasPrefix) else {
      return nil
    }
    let text = speakableText(message)
    guard !text.isBlank else { return nil }
    return AgentReplySpeechTarget(
      responseId: responseId(message),
      entryId: message.id.uuidString.lowercased(),
      text: text,
      complete: !message.remoteMessageId.hasPrefix("agent-stream-")
    )
  }

  static func speakableText(_ message: ChatMessage) -> String {
    let plain = CodexStyleResponsePolicy.sanitizeAssistantText(message.content)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if !plain.isEmpty { return plain }
    return AgentRichContentCodec.decode(message.richOutputJson)
      .compactMap { block -> String? in
        switch block.type {
        case .text, .heading, .quote:
          return block.text.ifBlank(block.title)
        case .list:
          return block.rows.map { $0.dropFirst().joined(separator: " ") }.joined(separator: "\n")
        default:
          return nil
        }
      }
      .filter { !$0.isBlank }
      .joined(separator: "\n\n")
  }

  private static func responseId(_ message: ChatMessage) -> String {
    [message.turnId, message.remoteMessageId, message.conversationId, message.id.uuidString]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty } ?? message.id.uuidString
  }

  private static let excludedRemoteMessagePrefixes = [
    "approval:",
    "remote-approval:",
    "agent-recovery:",
    "stale-connector:",
  ]
}

final class AgentReplySpeechController {
  private struct Session {
    var target: AgentReplySpeechTarget
    var playbackSessionId = ""
    var enabled = false
    var observedText: String
    var inputClosed = false
  }

  private var active: Session?
  private var playbackSequence: UInt64 = 0

  func observe(_ target: AgentReplySpeechTarget?) -> AgentReplySpeechCommand {
    guard let target else {
      let previous = active
      active = nil
      return AgentReplySpeechCommand(
        cancelSessionId: previous.flatMap { $0.enabled ? $0.playbackSessionId : nil } ?? "",
        changedEntryIds: changedEntryIds(previous?.target.entryId)
      )
    }
    guard var session = active, session.target.responseId == target.responseId else {
      let previous = active
      active = Session(
        target: target,
        observedText: target.text
      )
      return AgentReplySpeechCommand(
        cancelSessionId: previous.flatMap { $0.enabled ? $0.playbackSessionId : nil } ?? "",
        changedEntryIds: changedEntryIds(previous?.target.entryId, target.entryId)
      )
    }

    let oldEntryId = session.target.entryId
    let wasComplete = session.target.complete
    let delta = appendedText(previous: session.observedText, current: target.text)
    session.target = target
    session.observedText = target.text
    let shouldAppend = session.enabled && !session.inputClosed && !delta.isEmpty
    let shouldFinish = session.enabled && target.complete && !wasComplete && !session.inputClosed
    if shouldFinish { session.inputClosed = true }
    active = session
    return AgentReplySpeechCommand(
      appendedText: shouldAppend ? delta : "",
      finishSessionId: shouldFinish ? session.playbackSessionId : "",
      scheduleCommitSessionId: shouldAppend && !target.complete ? session.playbackSessionId : "",
      changedEntryIds: oldEntryId == target.entryId ? [] : [oldEntryId, target.entryId]
    )
  }

  func toggle(_ target: AgentReplySpeechTarget) -> AgentReplySpeechCommand {
    var session = session(for: target)
    if session.enabled {
      session.enabled = false
      session.inputClosed = false
      active = session
      return AgentReplySpeechCommand(
        cancelSessionId: session.playbackSessionId,
        changedEntryIds: [session.target.entryId]
      )
    }
    return begin(session: session, text: target.text, complete: target.complete)
  }

  func readParagraph(_ target: AgentReplySpeechTarget, paragraph: String) -> AgentReplySpeechCommand {
    let speech = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !speech.isEmpty else { return AgentReplySpeechCommand() }
    var session = session(for: target)
    session.observedText = target.text
    return begin(session: session, text: speech, complete: target.complete)
  }

  func disable(sessionId: String) -> Set<String> {
    guard var session = active, session.playbackSessionId == sessionId else { return [] }
    session.enabled = false
    session.inputClosed = false
    active = session
    return [session.target.entryId]
  }

  func isEnabled(_ target: AgentReplySpeechTarget) -> Bool {
    active?.target.responseId == target.responseId && active?.enabled == true
  }

  func isActive(_ target: AgentReplySpeechTarget) -> Bool {
    active?.target.responseId == target.responseId
  }

  private func session(for target: AgentReplySpeechTarget) -> Session {
    if var current = active, current.target.responseId == target.responseId {
      current.target = target
      current.observedText = target.text
      return current
    }
    return Session(
      target: target,
      observedText: target.text
    )
  }

  private func begin(
    session initialSession: Session,
    text: String,
    complete: Bool
  ) -> AgentReplySpeechCommand {
    var session = initialSession
    let previousPlaybackSessionId = session.enabled ? session.playbackSessionId : ""
    playbackSequence &+= 1
    session.playbackSessionId = Self.playbackSessionId(
      session.target.responseId,
      sequence: playbackSequence
    )
    session.enabled = true
    session.inputClosed = complete
    active = session
    return AgentReplySpeechCommand(
      cancelSessionId: previousPlaybackSessionId,
      beginSessionId: session.playbackSessionId,
      appendedText: text,
      finishSessionId: complete ? session.playbackSessionId : "",
      scheduleCommitSessionId: complete ? "" : session.playbackSessionId,
      changedEntryIds: [session.target.entryId]
    )
  }

  private func appendedText(previous: String, current: String) -> String {
    guard current != previous, current.hasPrefix(previous) else { return "" }
    return String(current.dropFirst(previous.count))
  }

  private func changedEntryIds(_ values: String?...) -> Set<String> {
    Set(values.compactMap { $0 }.filter { !$0.isEmpty })
  }

  private static func playbackSessionId(_ responseId: String, sequence: UInt64) -> String {
    let digest = SHA256.hash(data: Data(responseId.utf8))
    let suffix = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    return "agent-reply-\(suffix)-\(sequence)"
  }
}
