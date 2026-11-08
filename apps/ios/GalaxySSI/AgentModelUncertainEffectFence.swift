import Foundation

struct AgentModelUncertainEffectFence {
  private struct Pending {
    let toolID: String
    let invocationID: String
    let address: String?
  }

  private var pending: [String: Pending] = [:]

  func blocks(_ call: AgentModelToolCall, descriptor: AgentNativeToolDescriptor) -> Bool {
    descriptor.requiresEffectClaim && pending[identity(call, version: descriptor.version)] != nil
  }

  mutating func record(_ call: AgentModelToolCall, descriptor: AgentNativeToolDescriptor, result: AgentNativeToolResult) {
    if descriptor.requiresEffectClaim {
      guard result.error?.code == "effect_outcome_unknown" || result.error?.details["outcome_unknown"] == .bool(true) ||
        result.output["outcome_unknown"] == .bool(true) || result.status == .verificationFailed else { return }
      let id = result.receipt.originalInvocationId ?? result.receipt.invocationId
      let address = AgentEffectRecoveryRecord.browserMutationTools.contains(call.toolId)
        ? Self.canonicalAddress(call.arguments.string("url")) : nil
      pending[identity(call, version: descriptor.version)] = Pending(toolID: call.toolId, invocationID: id, address: address)
      return
    }
    guard result.isSuccess, !result.receipt.replayed, !pending.isEmpty,
          call.toolId != AgentIOSLocalModelWebToolProtocol.collaborationRecallId,
          call.toolId != AgentIOSWebMediaNativeToolCatalog.browserSessionOperationStatus,
          !call.toolId.hasPrefix("galaxyssi.tools.") else { return }

    // Tool discovery, transport receipts, and unrelated reads do not observe an earlier write.
    let verifiedInvocation = result.verification.flatMap { proof in
      proof.status == .passed && proof.evidence["external_state_observed"] == .bool(true)
        ? proof.evidence["observed_invocation_id"]?.strictStringValue : nil
    }
    let page = Self.observedPublicPage(toolID: call.toolId, output: result.output)
    pending = pending.filter { _, effect in
      let matchedProof = !effect.invocationID.isEmpty && effect.invocationID == verifiedInvocation
      let matchedPage = AgentEffectRecoveryRecord.browserMutationTools.contains(effect.toolID) &&
        effect.address != nil && effect.address == page
      return !matchedProof && !matchedPage
    }
  }

  private func identity(_ call: AgentModelToolCall, version: String) -> String {
    AgentMcpJSONCodec.sha256([
      "id": .string(call.toolId), "version": .string(version), "input": .object(call.arguments)
    ])
  }

  private static func observedPublicPage(toolID: String, output: AgentMcpJSONObject) -> String? {
    guard [AgentIOSWebMediaNativeToolCatalog.webOpen, AgentIOSWebMediaNativeToolCatalog.browserRender,
           AgentIOSWebMediaNativeToolCatalog.webFetch].contains(toolID),
          output.string("method") == "get",
          let status = output["status_code"]?.intValue, (200...299).contains(status),
          !output.string("text").isBlank, let source = output["source"]?.objectValue,
          let requested = canonicalAddress(source.string("requested_url")),
          requested == canonicalAddress(source.string("final_url")) else { return nil }
    return requested
  }

  private static func canonicalAddress(_ address: String) -> String? {
    guard let url = AgentManagedBrowserHandoff.url(address),
          var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
    components.scheme = components.scheme?.lowercased()
    components.host = components.host?.lowercased()
    components.fragment = nil
    if components.port == 443 { components.port = nil }
    if components.path.isEmpty { components.path = "/" }
    return components.string
  }
}
