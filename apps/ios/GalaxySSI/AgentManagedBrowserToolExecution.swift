import Foundation

struct AgentManagedBrowserToolExecution {
  static let toolID = "browser.user.handoff"

  let store: AgentManagedBrowserContinuationStore
  let binding: AgentManagedBrowserDispatchBinding
  let lease: AgentManagedBrowserContinuationStore.Lease

  static func descriptor() throws -> AgentNativeToolDescriptor {
    try AgentNativeToolDescriptor(id: toolID, version: "1.0.0", title: "Browser user handoff",
      description: "Ask the user to take control of a public HTTPS page. The original member waits for explicit return.",
      location: .phone, inputSchema: [
        "type": .string("object"),
        "properties": .object(["url": .object(["type": .string("string"), "maxLength": .int(4_096)])]),
        "required": .array([.string("url")]), "additionalProperties": .bool(false)
      ], risk: .low, idempotency: .idempotencyKeyRequired, effect: .mutation)
  }

  func executable() throws -> AgentNativeToolExecutableDefinition {
    AgentNativeToolExecutableDefinition(
      definition: .init(descriptor: try Self.descriptor(), executorId: "ios.managed_browser_handoff")
    ) { invocation in
      guard invocation.context.collaborationOwner == binding.owner,
            let callID = invocation.context.attributes["tool_call_id"],
            let address = invocation.input["url"]?.strictStringValue else {
        return .failure(code: "browser_owner_changed", message: "The handoff does not belong to this member.")
      }
      do {
        let handoff = try store.requestControl(lease: lease, binding: binding, callID: callID,
          invocationID: invocation.context.invocationId, address: address)
        return .success(output: Self.pendingOutput(handoff),
                        message: "Browser control was requested, not completed.")
      } catch {
        return .failure(code: "browser_handoff_unavailable", message: "The browser handoff could not be saved.")
      }
    }
  }

  func restoreCommittedRequest(call: AgentModelToolCall, invocationID: String) throws -> AgentMcpJSONObject? {
    guard call.toolId == Self.toolID, let address = call.arguments["url"]?.strictStringValue else {
      throw AgentManagedBrowserContinuationStore.Failure.invalidInput
    }
    return try store.savedRequest(lease: lease, binding: binding, callID: call.callId,
      invocationID: invocationID, address: address).map(Self.pendingOutput)
  }

  private static func pendingOutput(_ handoff: AgentManagedBrowserHandoff) -> AgentMcpJSONObject {
    ["handoff_id": .string(handoff.id.uuidString), "state": .string("awaiting_user"),
     "business_success_verified": .bool(false)]
  }

  func resolve(call: AgentModelToolCall, result: AgentNativeToolResult) throws -> AgentManagedBrowserHandoff {
    guard call.toolId == Self.toolID, result.isSuccess, let generation = UUID(uuidString: result.output.string("handoff_id")) else {
      throw AgentManagedBrowserContinuationStore.Failure.staleTicket
    }
    let handoff = try store.handoff(.init(dispatchKey: binding.key, callID: call.callId, generation: generation),
                                   binding: binding)
    guard handoff.invocationID == (result.receipt.originalInvocationId ?? result.receipt.invocationId) else {
      throw AgentManagedBrowserContinuationStore.Failure.scopeChanged
    }
    return handoff
  }
}
