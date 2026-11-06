import CryptoKit
import Foundation

struct AgentReplySpeechTarget: Equatable {
  var responseId: String
  var entryId: String
  var text: String
  var complete: Bool
}

struct AgentCompletedReplyPlaybackSelection: Equatable, Sendable {
  let conversationID: String
  let messageID: UUID
  let startOffset: Int

  init?(message: ChatMessage, paragraph: AgentReplyParagraphSpeechSelection? = nil) {
    guard !message.conversationId.isBlank,
          message.contactId == "hermes",
          let target = AgentReplySpeechPresentationPolicy.target(message), target.complete else { return nil }
    let offset: Int
    if let paragraph {
      if paragraph.startOffset >= 0, paragraph.startOffset < paragraph.sourceText.count,
         let source = target.text.range(of: paragraph.sourceText) {
        offset = target.text.distance(from: target.text.startIndex, to: source.lowerBound) + paragraph.startOffset
      } else if !paragraph.paragraph.isEmpty, let range = target.text.range(of: paragraph.paragraph) {
        offset = target.text.distance(from: target.text.startIndex, to: range.lowerBound)
      } else {
        return nil
      }
    } else {
      offset = 0
    }
    guard offset < target.text.count else { return nil }
    conversationID = message.conversationId
    messageID = message.id
    startOffset = offset
  }

  func resolve(_ persisted: ChatMessage?) -> String? {
    guard let persisted, persisted.id == messageID, persisted.conversationId == conversationID,
          persisted.contactId == "hermes", [.local, .delivered, .read].contains(persisted.deliveryStatus),
          let target = AgentReplySpeechPresentationPolicy.target(persisted), target.complete,
          startOffset < target.text.count else { return nil }
    let suffix = String(target.text.dropFirst(startOffset)).trimmingCharacters(in: .whitespacesAndNewlines)
    return suffix.isEmpty ? nil : suffix
  }
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
    let blocks = AgentRichContentCodec.presentationBlocks(content: message.content, richOutputJson: message.richOutputJson)
    let prose = Prose(blocks)
    if !prose.text.isEmpty { return prose.text }
    // Older connectors can provide a structured action card alongside a plain reply.
    return Prose(AgentRichContentCodec.fromText(message.content)).text
  }

  struct Prose {
    private struct Paragraph {
      let text: String
      let startOffset: Int
    }
    private var paragraphs: [String: Paragraph] = [:]
    private(set) var text = ""

    init(_ blocks: [AgentRichBlock]) {
      var duplicateIDs = Set<String>()
      var offset = 0
      for block in blocks {
        let paragraph = AgentReplySpeechPresentationPolicy.paragraphText(block)
        guard !paragraph.isEmpty else { continue }
        if !text.isEmpty { text += "\n\n"; offset += 2 }
        if paragraphs[block.id] == nil, !duplicateIDs.contains(block.id) {
          paragraphs[block.id] = Paragraph(text: paragraph, startOffset: offset)
        } else {
          // An ambiguous connector ID must not jump to a different paragraph.
          paragraphs.removeValue(forKey: block.id)
          duplicateIDs.insert(block.id)
        }
        text += paragraph
        offset += paragraph.count
      }
    }

    func selection(for block: AgentRichBlock, listRow: Int? = nil) -> AgentReplyParagraphSpeechSelection? {
      guard let entry = paragraphs[block.id], entry.text == AgentReplySpeechPresentationPolicy.paragraphText(block)
      else { return nil }
      if let listRow, block.type == .list, block.rows.indices.contains(listRow) {
        let rows = AgentReplySpeechPresentationPolicy.listText(block)
        let row = rows[listRow]
        guard !row.isEmpty else { return nil }
        let preceding = rows.prefix(listRow).filter { !$0.isEmpty }
        let offset = preceding.reduce(0) { $0 + $1.count + 1 }
        return .init(paragraph: row, sourceText: text, startOffset: entry.startOffset + offset)
      }
      return .init(paragraph: entry.text, sourceText: text, startOffset: entry.startOffset)
    }
  }

  static func paragraphText(_ block: AgentRichBlock) -> String {
    let raw: String
    switch block.type {
    case .text, .heading, .quote:
      raw = block.text.ifBlank(block.title)
    case .list:
      return listText(block).filter { !$0.isEmpty }.joined(separator: "\n")
    default:
      return ""
    }
    return normalizedProse(raw)
  }

  private static func listText(_ block: AgentRichBlock) -> [String] {
    block.rows.map { normalizedProse($0.dropFirst().joined(separator: " ")) }
  }

  private static func normalizedProse(_ raw: String) -> String {
    let visible = AgentInlineMarkdown.parse(raw).map { $0.style == .code ? " " : $0.text }.joined()
    return CodexStyleResponsePolicy.sanitizeAssistantText(visible)
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
    "agent-stream-preview-",
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
  private let sessionPrefix: String

  init(sessionPrefix: String = "agent-reply") {
    let normalized = sessionPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
    self.sessionPrefix = normalized.isEmpty ? "agent-reply" : normalized
  }

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

  func readFromParagraph(
    _ target: AgentReplySpeechTarget,
    paragraph: String,
    sourceText: String? = nil,
    startOffset: Int? = nil
  ) -> AgentReplySpeechCommand {
    let speech = continuationFromParagraph(
      targetText: target.text,
      paragraph: paragraph,
      sourceText: sourceText ?? target.text,
      requestedStartOffset: startOffset
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !speech.isEmpty else { return AgentReplySpeechCommand() }
    var session = session(for: target)
    session.observedText = target.text
    return begin(session: session, text: speech, complete: target.complete)
  }

  func stop() -> AgentReplySpeechCommand {
    guard var session = active, session.enabled else { return AgentReplySpeechCommand() }
    session.enabled = false
    session.inputClosed = false
    active = session
    return AgentReplySpeechCommand(
      cancelSessionId: session.playbackSessionId,
      changedEntryIds: [session.target.entryId]
    )
  }

  var isPlaying: Bool {
    active?.enabled == true
  }

  var footerEntryId: String? { active?.target.entryId }

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

  private func session(for target: AgentReplySpeechTarget) -> Session {
    if var current = active, current.target.responseId == target.responseId, current.target.entryId == target.entryId {
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
    let previousPlaybackSessionId = active.flatMap { $0.enabled ? $0.playbackSessionId : nil } ?? ""
    playbackSequence &+= 1
    session.playbackSessionId = playbackSessionId(
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

  private func continuationFromParagraph(
    targetText: String,
    paragraph: String,
    sourceText: String,
    requestedStartOffset: Int?
  ) -> String {
    if let requestedStartOffset,
       requestedStartOffset >= 0,
       requestedStartOffset <= sourceText.count {
      let sourceStart: String.Index?
      if sourceText == targetText {
        sourceStart = targetText.startIndex
      } else {
        sourceStart = targetText.range(of: sourceText)?.lowerBound
      }
      if let sourceStart,
         let targetStart = targetText.index(
           sourceStart,
           offsetBy: requestedStartOffset,
           limitedBy: targetText.endIndex
         ) {
        return String(targetText[targetStart...])
      }
    }
    if let range = targetText.range(of: paragraph) {
      return String(targetText[range.lowerBound...])
    }
    return paragraph
  }

  private func changedEntryIds(_ values: String?...) -> Set<String> {
    Set(values.compactMap { $0 }.filter { !$0.isEmpty })
  }

  private func playbackSessionId(_ responseId: String, sequence: UInt64) -> String {
    let digest = SHA256.hash(data: Data(responseId.utf8))
    let suffix = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    return "\(sessionPrefix)-\(suffix)-\(sequence)"
  }
}
