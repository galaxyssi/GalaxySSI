import Foundation

struct ConversationContextBudget: Codable, Equatable {
  var contextWindowTokens: Int
  var reservedOutputTokens: Int
  var triggerRatio: Double
  var targetRatio: Double
  var minimumRecentGroups: Int
  var maximumSummaryTokens: Int
  var maximumMessageCharacters: Int

  var inputBudgetTokens: Int {
    max(contextWindowTokens - reservedOutputTokens, 2_048)
  }

  init(
    contextWindowTokens: Int = 64_000,
    reservedOutputTokens: Int = 4_096,
    triggerRatio: Double = 0.70,
    targetRatio: Double = 0.45,
    minimumRecentGroups: Int = 4,
    maximumSummaryTokens: Int = 4_096,
    maximumMessageCharacters: Int = 16_000
  ) {
    precondition(contextWindowTokens >= 4_096)
    precondition(reservedOutputTokens >= 0 && reservedOutputTokens < contextWindowTokens)
    precondition((0.25...0.95).contains(triggerRatio))
    precondition((0.20...triggerRatio).contains(targetRatio))
    precondition(minimumRecentGroups > 0)
    precondition(maximumSummaryTokens >= 256)
    precondition(maximumMessageCharacters >= 1_000)
    self.contextWindowTokens = contextWindowTokens
    self.reservedOutputTokens = reservedOutputTokens
    self.triggerRatio = triggerRatio
    self.targetRatio = targetRatio
    self.minimumRecentGroups = minimumRecentGroups
    self.maximumSummaryTokens = maximumSummaryTokens
    self.maximumMessageCharacters = maximumMessageCharacters
  }

  enum CodingKeys: String, CodingKey {
    case contextWindowTokens = "context_window_tokens"
    case reservedOutputTokens = "reserved_output_tokens"
    case triggerRatio = "trigger_ratio"
    case targetRatio = "target_ratio"
    case minimumRecentGroups = "minimum_recent_groups"
    case maximumSummaryTokens = "maximum_summary_tokens"
    case maximumMessageCharacters = "maximum_message_characters"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      contextWindowTokens: try container.decodeIfPresent(Int.self, forKey: .contextWindowTokens) ?? 64_000,
      reservedOutputTokens: try container.decodeIfPresent(Int.self, forKey: .reservedOutputTokens) ?? 4_096,
      triggerRatio: try container.decodeIfPresent(Double.self, forKey: .triggerRatio) ?? 0.70,
      targetRatio: try container.decodeIfPresent(Double.self, forKey: .targetRatio) ?? 0.45,
      minimumRecentGroups: try container.decodeIfPresent(Int.self, forKey: .minimumRecentGroups) ?? 4,
      maximumSummaryTokens: try container.decodeIfPresent(Int.self, forKey: .maximumSummaryTokens) ?? 4_096,
      maximumMessageCharacters: try container.decodeIfPresent(Int.self, forKey: .maximumMessageCharacters) ?? 16_000
    )
  }
}

enum AgentModelMessageRole: String, Codable, CaseIterable, Identifiable {
  case system = "SYSTEM"
  case user = "USER"
  case assistant = "ASSISTANT"
  case tool = "TOOL"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentModelMessageRole {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .user
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try? container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

struct AgentModelToolCall: Codable, Equatable, Identifiable {
  var callId: String
  var toolId: String
  var arguments: AgentMcpJSONObject
  var toolVersion: String?
  var idempotencyKey: String?
  var depth: Int

  var id: String { callId }

  init(
    callId: String,
    toolId: String,
    arguments: AgentMcpJSONObject = [:],
    toolVersion: String? = nil,
    idempotencyKey: String? = nil,
    depth: Int = 1
  ) {
    self.callId = String(callId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentSkillLimits.maxIdCharacters))
    self.toolId = String(toolId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentSkillLimits.maxIdCharacters))
    self.arguments = arguments
    self.toolVersion = toolVersion?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .nilIfEmpty
    self.idempotencyKey = idempotencyKey?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .nilIfEmpty
    self.depth = depth
  }

  enum CodingKeys: String, CodingKey {
    case callId = "call_id"
    case toolId = "tool_id"
    case arguments
    case toolVersion = "tool_version"
    case idempotencyKey = "idempotency_key"
    case depth
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      callId: try container.decodeIfPresent(String.self, forKey: .callId) ?? "",
      toolId: try container.decodeIfPresent(String.self, forKey: .toolId) ?? "",
      arguments: try container.decodeIfPresent(AgentMcpJSONObject.self, forKey: .arguments) ?? [:],
      toolVersion: try container.decodeIfPresent(String.self, forKey: .toolVersion),
      idempotencyKey: try container.decodeIfPresent(String.self, forKey: .idempotencyKey),
      depth: try container.decodeIfPresent(Int.self, forKey: .depth) ?? 1
    )
  }
}

struct AgentModelToolResultContent: Codable, Equatable, Identifiable {
  var callId: String
  var toolId: String
  var status: String
  var output: AgentMcpJSONObject
  var message: String
  var error: AgentNativeToolError?
  var errorMessage: String
  var invocationId: String?
  var retryCount: Int
  var receipt: AgentNativeToolReceipt?
  var nativeResult: AgentNativeToolResult?

  var id: String { callId }

  init(
    callId: String,
    toolId: String,
    status: String,
    output: AgentMcpJSONObject = [:],
    message: String = "",
    error: AgentNativeToolError? = nil,
    errorMessage: String = "",
    invocationId: String? = nil,
    retryCount: Int = 0,
    receipt: AgentNativeToolReceipt? = nil,
    nativeResult: AgentNativeToolResult? = nil
  ) {
    self.callId = String(callId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentSkillLimits.maxIdCharacters))
    self.toolId = String(toolId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentSkillLimits.maxIdCharacters))
    self.status = String(status.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64)).ifBlank("unknown")
    self.output = output
    self.message = String(message.prefix(AgentSkillLimits.maxFeedbackCharacters))
    self.error = error
    self.errorMessage = String((errorMessage.nilIfEmpty ?? error?.message ?? "").prefix(AgentSkillLimits.maxFeedbackCharacters))
    self.invocationId = invocationId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    self.retryCount = max(0, retryCount)
    self.receipt = receipt
    self.nativeResult = nativeResult
  }

  var jsonValue: AgentMcpJSONValue {
    var object: AgentMcpJSONObject = [
      "call_id": .string(callId),
      "tool_id": .string(toolId),
      "status": .string(status),
      "output": .object(output),
      "message": .string(message)
    ]
    if let error {
      object["error"] = .object([
        "code": .string(error.code),
        "message": .string(error.message),
        "retryable": .bool(error.retryable),
        "details": .object(error.details)
      ])
    } else if !errorMessage.isBlank {
      object["error"] = .string(errorMessage)
    }
    if let invocationId {
      object["invocation_id"] = .string(invocationId)
    }
    object["retry_count"] = .int(Int64(retryCount))
    if !errorMessage.isBlank {
      object["error_message"] = .string(errorMessage)
    }
    return .object(object)
  }

  enum CodingKeys: String, CodingKey {
    case callId = "call_id"
    case toolId = "tool_id"
    case status
    case output
    case message
    case error
    case errorMessage = "error_message"
    case invocationId = "invocation_id"
    case retryCount = "retry_count"
    case receipt
    case nativeResult = "native_result"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let decodedError: AgentNativeToolError?
    do {
      decodedError = try container.decodeIfPresent(AgentNativeToolError.self, forKey: .error)
    } catch {
      decodedError = nil
    }
    let legacyErrorMessage: String
    do {
      legacyErrorMessage = try container.decodeIfPresent(String.self, forKey: .error) ?? ""
    } catch {
      legacyErrorMessage = ""
    }
    self.init(
      callId: try container.decodeIfPresent(String.self, forKey: .callId) ?? "",
      toolId: try container.decodeIfPresent(String.self, forKey: .toolId) ?? "",
      status: try container.decodeIfPresent(String.self, forKey: .status) ?? "unknown",
      output: try container.decodeIfPresent(AgentMcpJSONObject.self, forKey: .output) ?? [:],
      message: try container.decodeIfPresent(String.self, forKey: .message) ?? "",
      error: decodedError,
      errorMessage: (try container.decodeIfPresent(String.self, forKey: .errorMessage)) ?? legacyErrorMessage,
      invocationId: try container.decodeIfPresent(String.self, forKey: .invocationId),
      retryCount: try container.decodeIfPresent(Int.self, forKey: .retryCount) ?? 0,
      receipt: try container.decodeIfPresent(AgentNativeToolReceipt.self, forKey: .receipt),
      nativeResult: try container.decodeIfPresent(AgentNativeToolResult.self, forKey: .nativeResult)
    )
  }
}

struct AgentModelMessage: Codable, Equatable, Identifiable {
  var id: String
  var role: AgentModelMessageRole
  var text: String
  var toolCalls: [AgentModelToolCall]
  var toolResult: AgentModelToolResultContent?

  init(
    id: String = UUID().uuidString,
    role: AgentModelMessageRole,
    text: String = "",
    toolCalls: [AgentModelToolCall] = [],
    toolResult: AgentModelToolResultContent? = nil
  ) {
    self.id = String(id.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentSkillLimits.maxIdCharacters)).ifBlank(UUID().uuidString)
    self.role = role
    self.text = String(text.prefix(AgentSkillLimits.maxInstructionsCharacters))
    self.toolCalls = Array(toolCalls.prefix(AgentSkillLimits.maxToolCalls))
    self.toolResult = toolResult
  }

  static func system(_ text: String) -> AgentModelMessage {
    AgentModelMessage(role: .system, text: text)
  }

  static func user(_ text: String) -> AgentModelMessage {
    AgentModelMessage(role: .user, text: text)
  }

  static func assistant(_ text: String = "", toolCalls: [AgentModelToolCall] = []) -> AgentModelMessage {
    AgentModelMessage(role: .assistant, text: text, toolCalls: toolCalls)
  }

  static func tool(_ result: AgentModelToolResultContent) -> AgentModelMessage {
    AgentModelMessage(role: .tool, toolResult: result)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case role
    case text
    case toolCalls = "tool_calls"
    case toolResult = "tool_result"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
      role: try container.decodeIfPresent(AgentModelMessageRole.self, forKey: .role) ?? .user,
      text: try container.decodeIfPresent(String.self, forKey: .text) ?? "",
      toolCalls: try container.decodeIfPresent([AgentModelToolCall].self, forKey: .toolCalls) ?? [],
      toolResult: try container.decodeIfPresent(AgentModelToolResultContent.self, forKey: .toolResult)
    )
  }
}

struct CompactedAgentModelContext: Codable, Equatable {
  var messages: [AgentModelMessage]
  var originalEstimatedTokens: Int
  var compactedEstimatedTokens: Int
  var compacted: Bool

  enum CodingKeys: String, CodingKey {
    case messages
    case originalEstimatedTokens = "original_estimated_tokens"
    case compactedEstimatedTokens = "compacted_estimated_tokens"
    case compacted
  }
}

enum ConversationContextCompactor {
  static func estimateTokens(_ text: String) -> Int {
    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return 0 }
    let wordCount = clean.split(whereSeparator: \.isWhitespace).count
    let characterEstimate = Int(ceil(Double(clean.count) / 4.0))
    return max(1, max(wordCount, characterEstimate))
  }

  static func fitTextToTokenBudget(_ text: String, _ maximumTokens: Int) -> String {
    guard maximumTokens > 0 else { return "" }
    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard estimateTokens(clean) > maximumTokens else { return clean }
    var low = 0
    var high = clean.count
    var best = ""
    while low <= high {
      let middle = (low + high) / 2
      let end = clean.index(clean.startIndex, offsetBy: middle)
      let candidate = String(clean[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "\n...[content compacted]..."
      if estimateTokens(candidate) <= maximumTokens {
        best = candidate
        low = middle + 1
      } else {
        high = middle - 1
      }
    }
    return best.isEmpty ? String(clean.prefix(max(1, maximumTokens * 2))) : best
  }
}

enum AgentModelContextCompactor {
  private static let summaryHeader = "[EARLIER TOOL ACTIVITY - REFERENCE ONLY]"

  static func compact(
    _ messages: [AgentModelMessage],
    budget: ConversationContextBudget
  ) -> CompactedAgentModelContext {
    let originalTokens = estimate(messages)
    let trigger = Int(Double(budget.inputBudgetTokens) * budget.triggerRatio)
    guard originalTokens > trigger else {
      return CompactedAgentModelContext(
        messages: messages,
        originalEstimatedTokens: originalTokens,
        compactedEstimatedTokens: originalTokens,
        compacted: false
      )
    }

    let systemMessages = messages.filter { $0.role == .system }
    let blocks = protocolBlocks(messages.filter { $0.role != .system })
    let targetTokens = Int(Double(budget.inputBudgetTokens) * budget.targetRatio)
    let summaryAllowance = min(budget.maximumSummaryTokens, Int(Double(budget.inputBudgetTokens) * 0.15))
    let fixedTokens = estimate(systemMessages)
    let tailAllowance = max(targetTokens - fixedTokens - summaryAllowance, 512)
    var retainedKeys: Set<Int> = []
    var retainedTokens = 0
    var retainedBlocks = 0
    for block in blocks.reversed() {
      let blockTokens = estimate(block.messages)
      let mustKeep = block.unresolvedToolCalls ||
        retainedBlocks < budget.minimumRecentGroups ||
        block.containsLatestUserRequest
      if mustKeep || retainedTokens + blockTokens <= tailAllowance {
        retainedKeys.insert(block.index)
        retainedTokens += blockTokens
        retainedBlocks += 1
      }
    }
    if retainedKeys.isEmpty, let last = blocks.last {
      retainedKeys.insert(last.index)
    }

    let olderBlocks = blocks.filter { !retainedKeys.contains($0.index) }
    let recent = blocks.filter { retainedKeys.contains($0.index) }.flatMap(\.messages)
    let summary = toolSummary(olderBlocks, maximumTokens: summaryAllowance)
    var assembled = systemMessages
    if !summary.isBlank {
      assembled.append(.system(summary))
    }
    assembled.append(contentsOf: recent)
    let bounded = estimate(assembled) <= budget.inputBudgetTokens
      ? assembled
      : shrinkOversizedMessages(assembled, maximumTokens: budget.inputBudgetTokens)
    return CompactedAgentModelContext(
      messages: bounded,
      originalEstimatedTokens: originalTokens,
      compactedEstimatedTokens: estimate(bounded),
      compacted: !olderBlocks.isEmpty || bounded != messages
    )
  }

  static func estimate(_ messages: [AgentModelMessage]) -> Int {
    messages.reduce(0) { total, message in
      var tokens = ConversationContextCompactor.estimateTokens(message.text) + 6
      for call in message.toolCalls {
        tokens += ConversationContextCompactor.estimateTokens(call.toolId)
        tokens += ConversationContextCompactor.estimateTokens(AgentMcpJSONCodec.stringify(call.arguments))
      }
      if let result = message.toolResult {
        tokens += ConversationContextCompactor.estimateTokens(AgentMcpJSONCodec.stringify(result.jsonValue))
      }
      return total + tokens
    }
  }

  private static func protocolBlocks(_ messages: [AgentModelMessage]) -> [ToolProtocolBlock] {
    guard !messages.isEmpty else { return [] }
    let latestUserIndex = messages.lastIndex { $0.role == .user }
    var blocks: [ToolProtocolBlock] = []
    var index = 0
    while index < messages.count {
      let message = messages[index]
      if message.role == .assistant, !message.toolCalls.isEmpty {
        let expected = Set(message.toolCalls.map(\.callId))
        var blockMessages = [message]
        var cursor = index + 1
        var resolved: Set<String> = []
        while cursor < messages.count,
              messages[cursor].role == .tool,
              let result = messages[cursor].toolResult,
              expected.contains(result.callId) {
          blockMessages.append(messages[cursor])
          resolved.insert(result.callId)
          cursor += 1
        }
        blocks.append(ToolProtocolBlock(
          index: blocks.count,
          messages: blockMessages,
          unresolvedToolCalls: resolved != expected,
          containsLatestUserRequest: latestUserIndex.map { (index..<cursor).contains($0) } ?? false
        ))
        index = cursor
      } else {
        blocks.append(ToolProtocolBlock(
          index: blocks.count,
          messages: [message],
          unresolvedToolCalls: false,
          containsLatestUserRequest: index == latestUserIndex
        ))
        index += 1
      }
    }
    return blocks
  }

  private static func toolSummary(_ blocks: [ToolProtocolBlock], maximumTokens: Int) -> String {
    guard !blocks.isEmpty, maximumTokens > 0 else { return "" }
    let candidates = blocks.flatMap(\.messages).compactMap { message -> String? in
      switch message.role {
      case .system:
        return nil
      case .user:
        return cleanLine(message.text).nilIfEmpty.map { "User goal: \($0)" }
      case .assistant:
        if !message.toolCalls.isEmpty {
          return "Requested tools: " + message.toolCalls.map(\.toolId).joined(separator: ", ")
        }
        return cleanLine(message.text).nilIfEmpty.map { "Assistant outcome: \($0)" }
      case .tool:
        guard let result = message.toolResult else { return nil }
        let detail = cleanLine(result.message.ifBlank(result.errorMessage))
        return detail.isBlank
          ? "Tool \(result.toolId): \(result.status)"
          : "Tool \(result.toolId): \(result.status) - \(detail)"
      }
    }.stableDistinctForModelContext()
    var lines: [String] = []
    var usedTokens = 0
    for candidate in candidates.reversed() {
      let tokens = ConversationContextCompactor.estimateTokens(candidate) + 2
      if lines.isEmpty || usedTokens + tokens <= maximumTokens {
        lines.append(candidate)
        usedTokens += tokens
      }
    }
    guard !lines.isEmpty else { return "" }
    lines.reverse()
    let summary = ([summaryHeader, "Completed earlier activity only; do not repeat it unless the current result requires it."] +
      lines.map { "- \($0)" }).joined(separator: "\n")
    return ConversationContextCompactor.fitTextToTokenBudget(summary, maximumTokens)
  }

  private static func shrinkOversizedMessages(_ messages: [AgentModelMessage], maximumTokens: Int) -> [AgentModelMessage] {
    var current = messages
    guard estimate(current) > maximumTokens else { return current }
    for index in current.indices where current[index].role == .tool || current[index].role == .assistant {
      let message = current[index]
      switch message.role {
      case .tool:
        if let result = message.toolResult {
          let summary = [result.message, result.errorMessage, AgentMcpJSONCodec.stringify(result.output)]
            .first { !$0.isBlank } ?? ""
          let compactedResult = AgentModelToolResultContent(
            callId: result.callId,
            toolId: result.toolId,
            status: result.status,
            output: [
              "compacted": .bool(true),
              "summary": .string(ConversationContextCompactor.fitTextToTokenBudget(summary, 160))
            ],
            message: ConversationContextCompactor.fitTextToTokenBudget(result.message.ifBlank(summary), 160),
            error: result.error,
            errorMessage: result.errorMessage,
            invocationId: result.invocationId,
            retryCount: result.retryCount,
            receipt: result.receipt,
            nativeResult: result.nativeResult
          )
          current[index] = AgentModelMessage(id: message.id, role: .tool, toolResult: compactedResult)
        }
      case .assistant:
        current[index] = AgentModelMessage(
          id: message.id,
          role: .assistant,
          text: ConversationContextCompactor.fitTextToTokenBudget(message.text, 256),
          toolCalls: message.toolCalls.map {
            AgentModelToolCall(
              callId: $0.callId,
              toolId: $0.toolId,
              arguments: compactObject($0.arguments, tokenLimit: 80),
              toolVersion: $0.toolVersion,
              idempotencyKey: $0.idempotencyKey,
              depth: $0.depth
            )
          }
        )
      case .system, .user:
        break
      }
      if estimate(current) <= maximumTokens {
        return current
      }
    }
    return current
  }

  private static func compactObject(_ object: AgentMcpJSONObject, tokenLimit: Int) -> AgentMcpJSONObject {
    object.mapValues { compactValue($0, tokenLimit: tokenLimit) }
  }

  private static func compactValue(_ value: AgentMcpJSONValue, tokenLimit: Int) -> AgentMcpJSONValue {
    switch value {
    case .string(let text):
      return .string(ConversationContextCompactor.fitTextToTokenBudget(text, tokenLimit))
    case .object(let object):
      return .object(compactObject(object, tokenLimit: tokenLimit))
    case .array(let values):
      return .array(values.prefix(12).map { compactValue($0, tokenLimit: tokenLimit) })
    case .int, .double, .bool, .null:
      return value
    }
  }

  private static func cleanLine(_ value: String) -> String {
    let clean = value
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return clean.count <= 420 ? clean : String(clean.prefix(419)) + "..."
  }

  private struct ToolProtocolBlock {
    var index: Int
    var messages: [AgentModelMessage]
    var unresolvedToolCalls: Bool
    var containsLatestUserRequest: Bool
  }
}

private extension Array where Element: Hashable {
  func stableDistinctForModelContext() -> [Element] {
    var seen: Set<Element> = []
    var values: [Element] = []
    for item in self where seen.insert(item).inserted {
      values.append(item)
    }
    return values
  }
}
