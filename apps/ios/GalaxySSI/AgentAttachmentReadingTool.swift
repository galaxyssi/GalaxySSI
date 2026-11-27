import UIKit

enum AgentAttachmentReadingTool {
  static let id = "galaxyssi.app.attachment_reading"
  static func executable(invoke: @escaping (AgentNativeToolInvocation) -> AgentNativeToolExecutionResult)
    throws -> AgentNativeToolExecutableDefinition {
    let descriptor = try AgentNativeToolDescriptor(id: id, version: AgentPhoneNativeToolCatalog.version,
      title: "Report attachment interpretation",
      description: "Report whether you could interpret one original attachment in this turn by its 1-based ordinal. This records a model-reported interpretation, never delivery or objective proof. Do not infer recognition from a transport receipt or ordinary prose.",
      location: .application,
      inputSchema: ["type": .string("object"), "properties": .object([
        "ordinal": .object(["type": .string("integer"), "minimum": .int(1), "maximum": .int(10)]),
        "result": .object(["type": .string("string"), "enum": .array([.string("recognized"), .string("unreadable")])])]),
        "required": .array([.string("ordinal"), .string("result")]), "additionalProperties": .bool(false)],
      outputSchema: AgentNativeToolDescriptor.objectSchema(), risk: .low,
      capabilities: ["attachment_reading"], timeoutMillis: 5_000,
      idempotency: .idempotencyKeyRequired, effect: .mutation)
    return .init(definition: .init(descriptor: descriptor, executorId: "ios.attachment_reading"), executor: { invocation in
      try invocation.checkpoint()
      return invoke(invocation)
    })
  }
}

extension GalaxySSIStore {
  func reportAttachmentReading(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    let context = invocation.context
    guard UIApplication.shared.applicationState == .active, activeAgentConversationId == context.conversationId, canReadAgentTranscript,
      let session = agentSession(id: context.conversationId), session.status == .active,
      !session.privateMode, !session.trackingPaused,
      let sourceID = UUID(uuidString: context.turnId), let source = persistedMessage(id: sourceID, contactId: "hermes"),
      source.conversationId == context.conversationId, source.turnId == context.turnId,
      let ordinal = invocation.input["ordinal"]?.intValue, (1...10).contains(ordinal),
      let result = invocation.input["result"]?.stringValue, ["recognized", "unreadable"].contains(result),
      let childKey = turnReceiptKey(conversation: context.conversationId, turn: context.turnId) else {
      return .failure(code: "attachment_reading_scope_missing", message: "The original local attachment turn is unavailable.")
    }
    let blocks = AgentFileReceipt.originals(source)
    guard ordinal <= Int64(blocks.count) else { return .failure(code: "invalid_attachment_ordinal", message: "Choose an original file ordinal.") }
    let block = blocks[Int(ordinal) - 1]
    let parent = turnReceiptStore.read(childKey)?.fileReadSource
    let parentTurn = parent?.turn ?? context.turnId
    if let parent {
      guard blocks.count == 1, parent.digest == AgentTurnReceiptEvidence.hash(block.id),
        let parentID = UUID(uuidString: parentTurn), let original = persistedMessage(id: parentID, contactId: "hermes"),
        original.conversationId == context.conversationId, original.turnId == parentTurn,
        AgentFileReceipt.originals(original).count >= 2,
        AgentFileReceipt.originals(original).contains(where: { $0.id == block.id }) else {
        return .failure(code: "attachment_reading_source_changed", message: "The original batch no longer matches this read attempt.")
      }
    } else if blocks.count < 2 {
      return .failure(code: "attachment_reading_batch_required", message: "No original batch or scoped single-file read is bound.")
    }
    guard let key = turnReceiptKey(conversation: context.conversationId, turn: parentTurn),
      turnReceiptStore.changeFile(key, item: block.id, { $0.report(turn: context.turnId, original: parentTurn, recognized: result == "recognized") }) else {
      return .failure(code: "attachment_reading_stale", message: "A newer read attempt exists or the receipt could not be saved.")
    }
    return .success(output: ["model_reported": .string(result), "observation_accepted": .bool(true), "delivery_verified": .bool(false)])
  }
}
