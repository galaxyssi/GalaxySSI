import Foundation

enum AgentLocalModelToolCatalog {
  static let discoveryID = "galaxyssi.tools.local_availability"

  static func fingerprint(_ registry: AgentNativeToolRegistry,
                          binding: AgentManagedBrowserLoopInput.CatalogBinding) -> String {
    switch binding {
    case .registeredContracts:
      return registry.registeredContractFingerprint()
    case .availableSnapshot:
      return AgentModelToolProtocolJSON.sha256(
        registry.catalogJson(additionalDescriptors: [AgentModelObservationHistory.descriptor]))
    }
  }

  static func installDiscovery(in registry: AgentNativeToolRegistry,
                               authorize: ((AgentNativeToolInvocation) throws -> Void)? = nil) throws {
    let descriptor = try AgentNativeToolDescriptor(id: discoveryID, version: "1.0.0",
      title: "Inspect current local tool readiness",
      description: "Lists scoped tools including setup blockers, or reads one exact tool's current readiness and input contract. Does not install tools or grant permissions.",
      location: .application, inputSchema: [
        "type": .string("object"), "additionalProperties": .bool(false),
        "properties": .object([
          "tool_id": .object(["type": .string("string"), "minLength": .int(1), "maxLength": .int(160)]),
          "after": .object(["type": .string("string"), "minLength": .int(1), "maxLength": .int(160)])
        ])
      ], risk: .low, idempotency: .idempotent, effect: .readOnly)
    let definition = AgentPhoneNativeToolDefinition(descriptor: descriptor, executorId: "ios.local_tool_availability")
    guard let authorize else { try registry.register(definition); return }
    try registry.registerExecutable(.init(definition: definition, executor: { [weak registry] invocation in
      try authorize(invocation)
      guard let registry else { return .failure(code: "catalog_unavailable", message: "Local catalog is unavailable.") }
      let tool = invocation.input.string("tool_id")
      let after = invocation.input.string("after")
      guard tool.isEmpty || after.isEmpty else {
        return .failure(code: "invalid_catalog_selector", message: "Use either tool_id or after.")
      }
      registry.refreshAvailability()
      if !tool.isEmpty {
        guard let match = registry.lookup(tool)?.descriptor else {
          return .failure(code: "unknown_tool", message: "That tool is not in this local assignment.")
        }
        var result = row(match)
        if AgentMcpJSONCodec.stringify(match.inputSchema).utf8.count <= 8_192 {
          result["input_schema"] = .object(match.inputSchema)
        }
        return .success(output: result)
      }
      let page = Array(registry.descriptors().lazy.filter { $0.id > after }.prefix(17))
      let entries = page.prefix(16)
      let next = page.count > 16 ? entries.last?.id : nil
      return .success(output: [
        "tools": .array(entries.map { .object(row($0)) }),
        "next_cursor": next.map(AgentMcpJSONValue.string) ?? .null,
        "grants_permissions": .bool(false)
      ])
    }))
  }

  private static func row(_ descriptor: AgentNativeToolDescriptor) -> AgentMcpJSONObject {
    ["id": .string(descriptor.id), "version": .string(descriptor.version),
     "status": .string(descriptor.availability.status.rawValue),
     "reason": .string(String(descriptor.availability.reason.prefix(256))),
     "grants_permissions": .bool(false)]
  }
}
