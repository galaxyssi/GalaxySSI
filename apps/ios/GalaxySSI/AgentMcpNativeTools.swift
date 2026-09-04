import Foundation

enum AgentIOSMcpNativeToolOperation: String, Codable, CaseIterable, Identifiable {
  case listConnections = "connections.list"
  case listTools = "tools.list"
  case callTool = "tool.call"

  var id: String { rawValue }
}

protocol AgentIOSMcpNativeToolProviding {
  var implementationId: String { get }
  func availability(operation: AgentIOSMcpNativeToolOperation) -> AgentNativeToolAvailability
  func invoke(
    operation: AgentIOSMcpNativeToolOperation,
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult
}

struct AgentIOSUnavailableMcpNativeToolProvider: AgentIOSMcpNativeToolProviding {
  var implementationId: String = "galaxyssi.ios.mcp_host_unconfigured"

  func availability(operation: AgentIOSMcpNativeToolOperation) -> AgentNativeToolAvailability {
    AgentNativeToolAvailability(
      status: .requiresSetup,
      reason: "No authenticated MCP connection is ready"
    )
  }

  func invoke(
    operation: AgentIOSMcpNativeToolOperation,
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.failure(
      code: "mcp_provider_unavailable",
      message: "iOS MCP host provider is not connected",
      retryable: true
    )
  }
}

enum AgentMcpNativeTools {
  static let listConnections = "galaxyssi.mcp.connections.list"
  static let listTools = "galaxyssi.mcp.tools.list"
  static let callTool = "galaxyssi.mcp.tool.call"

  static let executorId = "galaxyssi.mcp.host"
  static let mcpHostPermission = "galaxyssi.scope.mcp_host"
  static let noAdditionalConsent = "galaxyssi.consent.none"
  static let toolIds: Set<String> = [listConnections, listTools, callTool]

  static func definitions(
    provider: AgentIOSMcpNativeToolProviding = AgentIOSUnavailableMcpNativeToolProvider()
  ) -> [AgentPhoneNativeToolDefinition] {
    AgentIOSMcpNativeToolOperation.allCases.map { operation in
      definition(provider: provider, operation: operation)
    }
  }

  static func operation(for toolId: String) -> AgentIOSMcpNativeToolOperation? {
    switch toolId {
    case listConnections:
      return .listConnections
    case listTools:
      return .listTools
    case callTool:
      return .callTool
    default:
      return nil
    }
  }

  static func toolId(_ operation: AgentIOSMcpNativeToolOperation) -> String {
    switch operation {
    case .listConnections:
      return listConnections
    case .listTools:
      return listTools
    case .callTool:
      return callTool
    }
  }

  static func title(_ operation: AgentIOSMcpNativeToolOperation) -> String {
    switch operation {
    case .listConnections:
      return "List MCP connections"
    case .listTools:
      return "List MCP tools"
    case .callTool:
      return "Call MCP tool"
    }
  }

  private static func definition(
    provider: AgentIOSMcpNativeToolProviding,
    operation: AgentIOSMcpNativeToolOperation
  ) -> AgentPhoneNativeToolDefinition {
    let descriptor = try! AgentNativeToolDescriptor(
      id: toolId(operation),
      version: AgentPhoneNativeToolCatalog.version,
      title: title(operation),
      description: description(operation),
      location: .application,
      inputSchema: inputSchema(operation),
      outputSchema: outputSchema(operation),
      risk: operation == .callTool ? .medium : .low,
      capabilities: ["mcp", "tool_use"],
      requiredPermissions: [
        AgentNativePermissionRequirement(
          id: mcpHostPermission,
          title: "MCP host access",
          description: "Limits calls to installed and authenticated MCP connections managed by GalaxySSI."
        )
      ],
      requiredConsents: [
        AgentNativeConsentRequirement(
          id: noAdditionalConsent,
          title: "No additional consent",
          description: "MCP permission decisions are enforced by the MCP connection policy and audit layer.",
          required: false
        )
      ],
      timeoutMillis: operation == .callTool ? 60_000 : 30_000,
      idempotency: .nonIdempotent,
      availability: provider.availability(operation: operation)
    )
    return AgentPhoneNativeToolDefinition(
      descriptor: descriptor,
      executorId: executorId,
      provenanceMetadata: [
        "implementation": provider.implementationId,
        "protocol": "mcp",
        "host": "ios",
        "compatibility_source": "AgentMcpNativeTools",
        "permission_enforcement": "mcp_security_policy"
      ],
      availabilityProvider: AgentNativeToolAvailabilityProvider { _ in
        provider.availability(operation: operation)
      }
    )
  }

  private static func description(_ operation: AgentIOSMcpNativeToolOperation) -> String {
    switch operation {
    case .listConnections:
      return "Lists installed MCP connections and their authentication and availability state."
    case .listTools:
      return "Discovers tools exposed by one installed and authenticated MCP connection."
    case .callTool:
      return "Calls a named tool on an installed and authenticated MCP connection."
    }
  }

  private static func inputSchema(_ operation: AgentIOSMcpNativeToolOperation) -> AgentMcpJSONObject {
    switch operation {
    case .listConnections:
      return objectSchema()
    case .listTools:
      return objectSchema([
        "connection_id": stringSchema(maxLength: 128)
      ], required: ["connection_id"])
    case .callTool:
      return objectSchema([
        "connection_id": stringSchema(maxLength: 128),
        "tool_name": stringSchema(maxLength: 192),
        "arguments": objectSchema(additionalProperties: true)
      ], required: ["connection_id", "tool_name", "arguments"])
    }
  }

  private static func outputSchema(_ operation: AgentIOSMcpNativeToolOperation) -> AgentMcpJSONObject {
    switch operation {
    case .listConnections:
      return objectSchema([
        "connections": arraySchema(itemSchema: objectSchema(additionalProperties: true), maxItems: 500)
      ], required: ["connections"], additionalProperties: true)
    case .listTools:
      return objectSchema([
        "connection_id": stringSchema(maxLength: 128),
        "tools": arraySchema(itemSchema: objectSchema(additionalProperties: true), maxItems: 1_000)
      ], required: ["connection_id", "tools"], additionalProperties: true)
    case .callTool:
      return objectSchema([
        "connection_id": stringSchema(maxLength: 128),
        "tool_name": stringSchema(maxLength: 192),
        "content": arraySchema(itemSchema: objectSchema(additionalProperties: true), maxItems: 1_000),
        "structured_content": objectSchema(additionalProperties: true)
      ], additionalProperties: true)
    }
  }

  private static func objectSchema(
    _ properties: [String: AgentMcpJSONObject] = [:],
    required: [String] = [],
    additionalProperties: Bool = false
  ) -> AgentMcpJSONObject {
    [
      "type": .string("object"),
      "properties": .object(properties.mapValues { .object($0) }),
      "required": .array(required.map(AgentMcpJSONValue.string)),
      "additionalProperties": .bool(additionalProperties)
    ]
  }

  private static func stringSchema(maxLength: Int64) -> AgentMcpJSONObject {
    [
      "type": .string("string"),
      "maxLength": .int(maxLength)
    ]
  }

  private static func arraySchema(itemSchema: AgentMcpJSONObject, maxItems: Int64) -> AgentMcpJSONObject {
    [
      "type": .string("array"),
      "items": .object(itemSchema),
      "maxItems": .int(maxItems)
    ]
  }
}

struct AgentIOSMcpNativeToolExecutor {
  var provider: AgentIOSMcpNativeToolProviding

  func executableDefinition(_ definition: AgentPhoneNativeToolDefinition) -> AgentNativeToolExecutableDefinition {
    AgentNativeToolExecutableDefinition(
      definition: definition,
      executor: { invocation in
        try invocation.checkpoint()
        let result = try self.execute(invocation)
        try invocation.checkpoint()
        return result
      }
    )
  }

  private func execute(_ invocation: AgentNativeToolInvocation) throws -> AgentNativeToolExecutionResult {
    guard let operation = AgentMcpNativeTools.operation(for: invocation.descriptor.id) else {
      return AgentNativeToolExecutionResult.failure(
        code: "mcp_unknown_tool",
        message: "Unknown MCP native tool."
      )
    }
    try invocation.reportProgress(
      stage: "mcp",
      message: AgentMcpNativeTools.title(operation),
      percent: 10
    )
    let execution = provider.invoke(operation: operation, input: invocation.input, invocation: invocation)
    guard execution.isSuccess else { return execution }
    var output = execution.output
    switch operation {
    case .listConnections:
      output["connections"] = output["connections"] ?? .array([])
    case .listTools:
      output["connection_id"] = output["connection_id"] ?? invocation.input["connection_id"] ?? .string("")
      output["tools"] = output["tools"] ?? .array([])
    case .callTool:
      output["connection_id"] = output["connection_id"] ?? invocation.input["connection_id"] ?? .string("")
      output["tool_name"] = output["tool_name"] ?? invocation.input["tool_name"] ?? .string("")
    }
    var metadata = execution.metadata
    metadata["protocol"] = metadata["protocol"] ?? .string("mcp")
    metadata["host"] = metadata["host"] ?? .string("ios")
    metadata["implementation"] = metadata["implementation"] ?? .string(provider.implementationId)
    return AgentNativeToolExecutionResult.success(
      output: output,
      message: execution.message.isEmpty ? "\(AgentMcpNativeTools.title(operation)) completed" : execution.message,
      metadata: metadata
    )
  }
}
