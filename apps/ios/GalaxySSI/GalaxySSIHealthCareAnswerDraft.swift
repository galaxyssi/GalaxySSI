import Foundation

enum GalaxySSIHealthCareAnswerDraft {
  static let tool = "galaxyssi_health_answer_propose"
  static let textLimit = 2_000
  static let pageSize = 8
  static let limit = 120
  static let instruction = """
    Stage an answer only if the current user message explicitly answers an eligible question.
    Use the exact question_id and question_revision and copy a verbatim quote from the current user message,
    never from a prior turn, stored facts, or a model reply. The draft requires local user confirmation.
    If there is no supported answer, reply in plain text without calling the tool.
    """

  static var schema: [String: Any] {
    let text: [String: Any] = ["type": "string", "minLength": 1, "maxLength": textLimit]
    return ["type": "object", "additionalProperties": false,
      "required": ["question_id", "question_revision", "quote", "answer"],
      "properties": ["question_id": ["type": "string", "minLength": 36, "maxLength": 36],
        "question_revision": ["type": "integer", "minimum": 1], "quote": text, "answer": text]]
  }

  struct Input {
    let question: UUID
    let revision: Int
    let quote: String
    let answer: String

    init(_ args: AgentMcpJSONObject) throws {
      guard Set(args.keys) == ["question_id", "question_revision", "quote", "answer"],
            let rawID = args["question_id"]?.strictStringValue, rawID.utf8.count == 36,
            let id = UUID(uuidString: rawID),
            case .int(let revision)? = args["question_revision"], revision > 0,
            let number = Int(exactly: revision), let quote = args["quote"]?.strictStringValue,
            let answer = args["answer"]?.strictStringValue,
            GalaxySSIHealthCareAnswerDraft.valid(quote), GalaxySSIHealthCareAnswerDraft.valid(answer)
      else { throw GalaxySSIHealthRecords.Failure.invalid }
      self.question = id; self.revision = number; self.quote = quote; self.answer = answer
    }
  }

  enum State: String, Codable { case pending, accepted, dismissed }

  struct Item: Codable, Equatable, Identifiable {
    var id = UUID()
    let thread: UUID
    let turn: UUID
    let question: UUID
    let revision: Int
    let basis: String
    let questionText: String
    let scope: String
    let carePermission: UUID
    let onlinePermission: UUID
    let profileScopeEpoch: UUID?
    let sourceDigest: String
    let quote: String
    let answer: String
    let createdAt: Date
    var state = State.pending
    var reviewedAt: Date?
    var reviewedAnswer: String?
  }

  struct Page {
    let items: [Item]
    let next: UUID?
  }

  static func valid(_ text: String) -> Bool { !text.isBlank && text.utf8.count <= textLimit }

  static func digest(_ text: String) -> String {
    AgentModelLoopRecoveryIdentity.sha256(["health_answer_user_input": text])
  }

  static func matches(_ quote: String, in text: String) -> Bool {
    valid(quote) && Data(text.utf8).range(of: Data(quote.utf8)) != nil
  }

  static func eligible(_ page: GalaxySSIHealthCareQuestions.Page) -> [GalaxySSIHealthCareQuestions.Row] {
    page.rows.filter { page.state($0) == .open }
  }

  static func argumentsIfPresent(_ bytes: Data, style: GalaxySSICloudAPIStyle) throws -> AgentMcpJSONObject? {
    guard let call = try GalaxySSIHealthCareHistoryTool.call(bytes, style: style,
      proposesPlan: false, allowsAnswerDraft: true) else { return nil }
    guard call.name == tool else { throw GalaxySSIHealthRecords.Failure.invalid }
    return call.arguments
  }
}
