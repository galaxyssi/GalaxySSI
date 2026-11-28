import Foundation

struct CloudToolInvocationJournal {
  struct Outcome {
    var output: String
    var replayed: Bool
  }
  struct Binding: Codable, Equatable {
    var owner: String
    var contactID: String
    var conversationID: String
    var turnID: String
    var requestID: String
    var round: Int
    var slot: Int
    var requestSHA256: String
    var collaborationOwner: String?

    var scope: AgentModelLoopScope {
      AgentModelLoopScope(request: AgentModelToolLoopRequest(
        sessionId: AgentModelLoopRecoveryIdentity.sha256(["conversation": conversationID, "contact": contactID]),
        conversationId: AgentModelLoopRecoveryIdentity.sha256(conversationID),
        turnId: AgentModelLoopRecoveryIdentity.sha256(turnID), taskId: AgentModelLoopRecoveryIdentity.sha256(requestID),
        workspaceId: AgentModelLoopRecoveryIdentity.sha256(contactID),
        loopId: "cloud-tool-\(round)-\(slot)", messages: [.user("Cloud tool invocation")],
        callerId: "galaxyssi.cloud_tool_invocation." + AgentModelLoopRecoveryIdentity.sha256(owner)))
    }
  }

  private struct Input: Codable, Equatable {
    var binding: Binding
    var callID: String
    var name: String
    var arguments: AgentMcpJSONObject
  }

  private struct Result: Codable {
    var inputSHA256: String
    var output: String
  }

  let journal: AgentModelLoopJournal

  func execute(binding: Binding, call: AssembledToolCall,
               validateOwner: () async throws -> Void,
               restoreResult: (String) throws -> Void = { _ in },
               operation: () async throws -> String) async throws -> Outcome {
    guard !binding.owner.isBlank, !binding.contactID.isBlank, !binding.turnID.isBlank,
          !binding.requestID.isBlank, binding.round >= 0, binding.slot >= 0,
          binding.requestSHA256.count == 64, !call.callId.isBlank, !call.name.isBlank else {
      throw AgentModelLoopRecoveryError(code: "cloud_tool_binding_invalid")
    }
    let input = Input(binding: binding, callID: call.callId, name: call.name,
      arguments: try CloudModelStreamJSON.mcpObject(from: call.argumentsJson))
    let hash = AgentModelLoopRecoveryIdentity.sha256(input)
    try Task.checkCancellation()
    try await validateOwner()
    return try await journal.withLease(scope: binding.scope) { records in
      try await validateOwner()
      if let saved = try records.read("cloud-tool-input") {
        guard try JSONDecoder().decode(Input.self, from: saved) == input else {
          throw AgentModelLoopRecoveryError(code: "cloud_tool_input_changed")
        }
        guard let data = try records.read("cloud-tool-result") else {
          throw AgentModelLoopRecoveryError(code: "cloud_tool_outcome_unknown")
        }
        let result = try JSONDecoder().decode(Result.self, from: data)
        guard result.inputSHA256 == hash else {
          throw AgentModelLoopRecoveryError(code: "cloud_tool_result_changed")
        }
        try Task.checkCancellation()
        try await validateOwner()
        try restoreResult(result.output)
        return Outcome(output: result.output, replayed: true)
      }
      guard try records.read("cloud-tool-result") == nil else {
        throw AgentModelLoopRecoveryError(code: "cloud_tool_record_unreadable")
      }
      try Task.checkCancellation()
      try records.write("cloud-tool-input", data: JSONEncoder().encode(input))
      // The input itself is the durable claim; failure after this point never authorizes replay.
      let output: String
      do {
        try Task.checkCancellation()
        try await validateOwner()
        output = try await operation()
      } catch {
        throw AgentModelLoopRecoveryError(code: "cloud_tool_outcome_unknown")
      }
      try records.write("cloud-tool-result", data: JSONEncoder().encode(Result(inputSHA256: hash, output: output)))
      try Task.checkCancellation()
      try await validateOwner()
      return Outcome(output: output, replayed: false)
    }
  }
}
