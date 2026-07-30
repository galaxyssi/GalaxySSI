import XCTest
@testable import SignalASI

extension SignalASIStoreTests {
  func testAgentMcpNativeToolsExposeAndroidWireIdsAndProviderBackedExecution() throws {
    final class FakeMcpNativeProvider: AgentIOSMcpNativeToolProviding {
      var implementationId = "fake.ios.mcp"
      var currentAvailability: AgentNativeToolAvailability = .available
      var invokedOperations: [AgentIOSMcpNativeToolOperation] = []
      var capturedInputs: [AgentMcpJSONObject] = []

      func availability(operation: AgentIOSMcpNativeToolOperation) -> AgentNativeToolAvailability {
        currentAvailability
      }

      func invoke(
        operation: AgentIOSMcpNativeToolOperation,
        input: AgentMcpJSONObject,
        invocation: AgentNativeToolInvocation
      ) -> AgentNativeToolExecutionResult {
        invokedOperations.append(operation)
        capturedInputs.append(input)
        switch operation {
        case .listConnections:
          return AgentNativeToolExecutionResult.success(
            output: [
              "connections": .array([
                .object([
                  "id": .string("github"),
                  "name": .string("GitHub"),
                  "state": .string("connected"),
                  "auth_state": .string("authenticated"),
                  "enabled": .bool(true),
                  "permission_mode": .string("ask_for_changes"),
                  "tools": .array([.string("github.repositories")])
                ])
              ])
            ],
            message: "MCP connections listed"
          )
        case .listTools:
          return AgentNativeToolExecutionResult.success(
            output: [
              "connection_id": input["connection_id"] ?? .string("github"),
              "tools": .array([
                .object([
                  "name": .string("github.repositories"),
                  "title": .string("List repositories"),
                  "description": .string("Lists repositories"),
                  "security": .object(["risk": .string("low")])
                ])
              ])
            ],
            message: "MCP tools discovered"
          )
        case .callTool:
          return AgentNativeToolExecutionResult.success(
            output: [
              "content": .array([.object(["type": .string("text"), "text": .string("ok")])]),
              "structured_content": .object(["ok": .bool(true)])
            ],
            message: "MCP tool called",
            metadata: ["mcp_audit_id": .string("audit-1")]
          )
        }
      }
    }

    let provider = FakeMcpNativeProvider()
    let definitions = AgentMcpNativeTools.definitions(provider: provider)
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.mcpExecutableDefinitions(provider: provider)
    )
    let context = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentMcpNativeTools.mcpHostPermission]
    )

    XCTAssertEqual(Set(definitions.map(\.id)), AgentMcpNativeTools.toolIds)
    XCTAssertEqual(registry.ids(), AgentMcpNativeTools.toolIds)
    XCTAssertTrue(AgentMcpNativeTools.toolIds.contains("signalasi.mcp.connections.list"))
    XCTAssertTrue(AgentMcpNativeTools.toolIds.contains("signalasi.mcp.tools.list"))
    XCTAssertTrue(AgentMcpNativeTools.toolIds.contains("signalasi.mcp.tool.call"))
    XCTAssertFalse(AgentMcpNativeTools.toolIds.contains("signalasi.mcp.call_tool"))
    definitions.forEach { definition in
      XCTAssertEqual(definition.executorId, AgentMcpNativeTools.executorId)
      XCTAssertEqual(definition.descriptor.location, .application)
      XCTAssertTrue(definition.descriptor.capabilities.contains("mcp"))
      XCTAssertEqual(definition.descriptor.requiredPermissions.map(\.id), [AgentMcpNativeTools.mcpHostPermission])
      XCTAssertEqual(definition.descriptor.requiredConsents.first?.required, false)
      XCTAssertEqual(definition.provenanceMetadata["protocol"], "mcp")
      XCTAssertEqual(definition.provenanceMetadata["host"], "ios")
    }
    let callDescriptor = try XCTUnwrap(definitions.first { $0.id == AgentMcpNativeTools.callTool })
    XCTAssertEqual(callDescriptor.descriptor.risk, .medium)
    XCTAssertEqual(callDescriptor.descriptor.timeoutMillis, 60_000)
    XCTAssertEqual(callDescriptor.descriptor.idempotency, .nonIdempotent)

    let connections = registry.invoke(AgentMcpNativeTools.listConnections, input: [:], context: context)
    let tools = registry.invoke(
      AgentMcpNativeTools.listTools,
      input: ["connection_id": .string("github")],
      context: context
    )
    let denied = registry.invoke(
      AgentMcpNativeTools.callTool,
      input: [
        "connection_id": .string("github"),
        "tool_name": .string("github.repositories"),
        "arguments": .object([:])
      ],
      context: AgentNativeToolInvocationContext()
    )
    let call = registry.invoke(
      AgentMcpNativeTools.callTool,
      input: [
        "connection_id": .string("github"),
        "tool_name": .string("github.repositories"),
        "arguments": .object(["limit": .int(1)])
      ],
      context: context
    )
    let unavailableProvider = FakeMcpNativeProvider()
    unavailableProvider.currentAvailability = AgentNativeToolAvailability(
      status: .requiresSetup,
      reason: "No authenticated MCP connection is ready"
    )
    let unavailableRegistry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.mcpExecutableDefinitions(provider: unavailableProvider)
    )
    let unavailable = unavailableRegistry.invoke(AgentMcpNativeTools.listConnections, input: [:], context: context)

    XCTAssertTrue(connections.isSuccess)
    if case .array(let listedConnections)? = connections.output["connections"] {
      XCTAssertEqual(listedConnections.count, 1)
    } else {
      XCTFail("Expected MCP connections array")
    }
    XCTAssertTrue(tools.isSuccess)
    XCTAssertEqual(provider.capturedInputs[1]["connection_id"], .string("github"))
    XCTAssertEqual(denied.status, .rejected)
    XCTAssertEqual(denied.error?.code, "missing_permissions")
    XCTAssertTrue(call.isSuccess)
    XCTAssertEqual(call.output["connection_id"], .string("github"))
    XCTAssertEqual(call.output["tool_name"], .string("github.repositories"))
    XCTAssertEqual(call.metadata["protocol"], .string("mcp"))
    XCTAssertEqual(call.metadata["mcp_audit_id"], .string("audit-1"))
    XCTAssertEqual(provider.invokedOperations, [.listConnections, .listTools, .callTool])
    XCTAssertEqual(unavailable.status, .unavailable)
    XCTAssertEqual(unavailable.error?.code, "tool_unavailable")
    XCTAssertTrue(unavailableProvider.invokedOperations.isEmpty)
  }

}
