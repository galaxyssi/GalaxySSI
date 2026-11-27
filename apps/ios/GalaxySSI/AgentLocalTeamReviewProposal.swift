import Combine
import Foundation

enum AgentLocalTeamReviewProposal {
  static let field = "propose_team_review"
  static let instruction = "For a self-contained complex textual objective where independent approaches would materially help, " +
    "you may add propose_team_review:true to the normal final answer object with empty tool_calls. " +
    "Answer normally even if the user declines. Never call a tool to propose a team. The phone alone offers review; nothing has started. " +
    "Omit for simple, personal, context-dependent or explicitly solo requests. Do not supply an objective, recipient or budget."
  static let plannerInstruction = "For a self-contained complex textual objective where independent approaches would materially help, " +
    "you may return exactly {\"disposition\":\"respond\",\"final_response\":\"normal complete answer\",\"propose_team_review\":true}. " +
    "This is only an optional phone confirmation proposal, not delegation. Answer fully if declined. " +
    "Omit for simple, personal, context-dependent or solo requests. No tools, destination, objective or budget in a proposal."
  static func envelope(_ raw: String) -> AgentMcpJSONObject? {
    guard raw.utf8.count <= 131_072 else { return nil }
    var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix("<think>") {
      guard let end = value.range(of: "</think>") else { return nil }
      value = String(value[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard value.hasPrefix("{") else { return nil }
    return try? JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(value.utf8))
  }
  static func proposed(_ root: AgentMcpJSONObject?, planner: Bool = false) -> Bool {
    guard let root, root[field] == .bool(true) else { return false }
    if planner {
      return Set(root.keys) == ["disposition", "final_response", field] && root["disposition"] == .string("respond") &&
        root["final_response"]?.strictStringValue?.isBlank == false
    }
    return Set(root.keys) == ["answer", "tool_calls", field] && root["answer"]?.strictStringValue?.isBlank == false &&
      root["tool_calls"] == .array([])
  }
}

struct AgentLocalTeamReviewSource: Codable, Equatable {
  let message: UUID
  let turn: String
  var valid: Bool { !turn.isBlank && turn.utf8.count <= 512 }
  @MainActor func matches(_ store: GalaxySSIStore, conversation: String, objective: String) -> Bool {
    guard let original = store.persistedMessage(id: message, contactId: "hermes") else { return false }
    return original.isMine && !original.readOnlyAnalysis && original.sourceConversationId.isBlank &&
      original.conversationId == conversation && original.turnId.ifBlank(original.id.uuidString) == turn && original.content == objective
  }
}

@MainActor
final class AgentLocalTeamReviewWindow: ObservableObject {
  struct Candidate: Equatable {
    let owner: String
    let conversation: String
    let source: AgentLocalTeamReviewSource
    let objective: String
    let revision: UUID
    let selection: AgentModelSelection
  }
  private final class WeakWindow {
    weak var value: AgentLocalTeamReviewWindow?
    init(_ value: AgentLocalTeamReviewWindow) { self.value = value }
  }
  private static var windows: [String: WeakWindow] = [:]
  @Published private(set) var proposal: Candidate?
  private var candidate: Candidate?
  private var usable: () -> Bool = { false }
  private var requested = false
  private var proposed = false
  private var key = ""
  func invalidate() {
    if Self.windows[key]?.value === self { Self.windows.removeValue(forKey: key) }
    candidate = nil; proposal = nil; requested = false; proposed = false; usable = { false }; key = ""
  }
  private static func key(owner: String, conversation: String, turn: String) -> String {
    AgentModelLoopRecoveryIdentity.sha256(["owner": owner, "conversation": conversation, "turn": turn])
  }
  func bind(_ value: Candidate, valid: @escaping () -> Bool) {
    invalidate(); Self.windows = Self.windows.filter { $0.value.value != nil }
    candidate = value; usable = valid
    key = Self.key(owner: value.owner, conversation: value.conversation, turn: value.source.turn)
    Self.windows[key] = WeakWindow(self)
  }
  static func request(owner: String, conversation: String, turn: String, objective: String, profile: String) -> Bool {
    let key = key(owner: owner, conversation: conversation, turn: turn)
    guard let window = windows[key]?.value, let candidate = window.candidate,
      !window.requested, window.usable(), candidate.objective == objective,
      candidate.selection.mode != .manual || (candidate.selection.targetId == "local-llm" &&
        (candidate.selection.modelId.isBlank || candidate.selection.modelId == profile)) else { return false }
    window.requested = true
    return true
  }
  static func mark(owner: String, conversation: String, turn: String) {
    let key = key(owner: owner, conversation: conversation, turn: turn)
    guard let window = windows[key]?.value, window.requested, window.usable() else { return }
    window.proposed = true
  }
  static func delivered(owner: String, conversation: String, turn: String) {
    let key = key(owner: owner, conversation: conversation, turn: turn)
    guard let window = windows[key]?.value, window.proposed, window.usable(), let candidate = window.candidate else { return }
    window.proposed = false; window.proposal = candidate
  }
  func claim() -> Candidate? {
    guard usable(), let proposal else { invalidate(); return nil }
    self.proposal = nil; candidate = nil
    if Self.windows[key]?.value === self { Self.windows.removeValue(forKey: key) }
    return proposal
  }
}
