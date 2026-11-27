import Foundation

@MainActor
final class VoiceMessageDraft {
  struct Speaker: Equatable {
    let owner: String
    let session: UUID
    let conversation: String
    let turn: String
  }
  struct Person: Equatable { let id: String; let name: String; let route: String }
  struct Claim: Equatable { let revision: String; let recipient: Person; let text: String }
  enum Phase: String { case chooseRecipient = "choose_recipient", awaitingConfirmation = "awaiting_confirmation", dispatching, queued, published, uncertain = "dispatch_uncertain" }
  private struct Draft {
    let speaker: Speaker
    var text: String
    var people: [Person]
    let selected: Person?
    let revision: String
    let expires: TimeInterval
    var phase: Phase
    var message = ""
  }
  private let now: () -> TimeInterval
  private var current: Draft?
  init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) { self.now = now }
  func clear() { current = nil }
  private func observed(_ speaker: Speaker) -> Draft? {
    guard !speaker.owner.isBlank, !speaker.conversation.isBlank, !speaker.turn.isBlank else { return nil }
    guard let draft = current else { return nil }
    guard now() < draft.expires else { clear(); return nil }
    guard draft.speaker.owner == speaker.owner, draft.speaker.session == speaker.session,
      draft.speaker.conversation == speaker.conversation else { return nil }
    return draft
  }
  private func editable(_ value: Draft) -> Bool { [.chooseRecipient, .awaitingConfirmation].contains(value.phase) }
  private func info(_ value: Draft) -> AgentMcpJSONObject {
    var output: AgentMcpJSONObject = ["state": .string(value.phase.rawValue), "revision": .string(value.revision),
      "delivery_verified": .bool(false), "send_claimed": .bool(!editable(value)), "recall_supported": .bool(false)]
    if let person = value.selected { output["recipient"] = .string(person.name); output["contact_id"] = .string(person.id) }
    if editable(value) { output["text"] = .string(value.text) }
    if value.phase == .chooseRecipient {
      output["choices"] = .array(value.people.enumerated().map { index, person in
        .object(["option": .int(Int64(index + 1)), "name": .string(person.name), "contact_id": .string(person.id),
          "id_suffix": .string(String(person.id.suffix(4)))])
      })
    }
    if !value.message.isEmpty { output["message_id"] = .string(value.message) }
    return output
  }
  func status(_ speaker: Speaker) -> AgentMcpJSONObject {
    observed(speaker).map(info) ?? ["state": .string("no_active_draft"), "delivery_verified": .bool(false)]
  }
  private func install(_ speaker: Speaker, text: String, people: [Person]) -> AgentNativeToolExecutionResult {
    guard !speaker.owner.isBlank, !speaker.conversation.isBlank, !speaker.turn.isBlank,
      !text.isBlank, text.utf16.count <= 10_000, text.utf8.count <= 40_000, people.count <= 64 else {
      return .failure(code: "invalid_voice_draft", message: "A live voice turn, bounded text and unambiguous contact scope are required.")
    }
    var seen: Set<String> = []
    let unique = people.filter { !$0.id.isBlank && seen.insert($0.id).inserted }
    let selected = unique.count == 1 ? unique.first : nil
    let value = Draft(speaker: speaker, text: text, people: unique, selected: selected, revision: UUID().uuidString,
      expires: now() + 180, phase: selected == nil ? .chooseRecipient : .awaitingConfirmation)
    current = value
    return .success(output: info(value))
  }
  func begin(_ speaker: Speaker, text: String, people: [Person]) -> AgentNativeToolExecutionResult {
    if let existing = observed(speaker), editable(existing) || existing.phase == .dispatching || existing.speaker.turn == speaker.turn {
      return .success(output: info(existing))
    }
    return install(speaker, text: text, people: people)
  }
  func change(_ speaker: Speaker, revision: String, people: [Person]) -> AgentNativeToolExecutionResult {
    guard let value = observed(speaker), value.revision == revision else { return stale() }
    guard editable(value) else { return .success(output: info(value)) }
    return install(speaker, text: value.text, people: people)
  }
  func choose(_ speaker: Speaker, revision: String, id: String, spokenOption: Int) -> AgentNativeToolExecutionResult {
    guard let value = observed(speaker), value.revision == revision else { return stale() }
    guard value.phase == .chooseRecipient else { return .success(output: info(value)) }
    guard speaker.turn != value.speaker.turn, spokenOption > 0, spokenOption <= value.people.count,
      value.people[spokenOption - 1].id == id else {
      return .failure(code: "clarify_recipient", message: "Read the numbered choices and wait for a new spoken selection.")
    }
    return install(speaker, text: value.text, people: [value.people[spokenOption - 1]])
  }
  func claim(_ speaker: Speaker, revision: String, confirmed: Bool) -> Claim? {
    guard let value = observed(speaker), value.revision == revision, value.phase == .awaitingConfirmation,
      let recipient = value.selected, confirmed, speaker.turn != value.speaker.turn, !speaker.turn.isBlank else { return nil }
    // Bind terminal replay protection to the confirming utterance, not the original preparation.
    current = Draft(speaker: speaker, text: value.text, people: value.people, selected: recipient,
      revision: value.revision, expires: value.expires, phase: .dispatching)
    return Claim(revision: revision, recipient: recipient, text: value.text)
  }
  func finish(_ claim: Claim, result: AgentNativeToolExecutionResult) -> AgentNativeToolExecutionResult {
    let reported = result.output["status"]?.stringValue ?? ""
    let phase: Phase = result.isSuccess && reported == "queued" ? .queued : result.isSuccess && reported == "published" ? .published : .uncertain
    guard var value = current, value.revision == claim.revision, value.phase == .dispatching else {
      return .success(output: ["state": .string(phase.rawValue), "delivery_verified": .bool(false), "recall_supported": .bool(false)])
    }
    value.phase = phase; value.text = ""; value.people = []
    value.message = result.output["message_id"]?.stringValue ?? ""
    current = value
    return .success(output: info(value))
  }
  func cancel(_ speaker: Speaker, revision: String) -> AgentNativeToolExecutionResult {
    guard let value = observed(speaker), value.revision == revision else { return stale() }
    guard editable(value) else { return .success(output: info(value)) }
    clear()
    return .success(output: ["state": .string("cancelled_before_send"), "delivery_verified": .bool(false)])
  }
  private func stale() -> AgentNativeToolExecutionResult {
    .failure(code: "stale_voice_draft", message: "The draft changed or expired. No new message was sent.")
  }
}
