import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
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
    XCTAssertTrue(AgentMcpNativeTools.toolIds.contains("galaxyssi.mcp.connections.list"))
    XCTAssertTrue(AgentMcpNativeTools.toolIds.contains("galaxyssi.mcp.tools.list"))
    XCTAssertTrue(AgentMcpNativeTools.toolIds.contains("galaxyssi.mcp.tool.call"))
    XCTAssertFalse(AgentMcpNativeTools.toolIds.contains("galaxyssi.mcp.call_tool"))
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

  func testAgentIOSMcpClientNativeProviderListsConnectionsAndGatesReadyTools() throws {
    let root = try temporaryDirectory("ios-mcp-native-provider")
    defer { try? FileManager.default.removeItem(at: root) }
    let now: () -> Int64 = { 20_000 }
    let mcpRegistry = AgentMcpRegistry(InMemoryAgentMcpStore(), nowMillis: now)
    let connection = try mcpRegistry.addRemote(
      displayName: "Relay MCP",
      endpoint: "https://mcp.example/rpc",
      authProfile: try AgentMcpAuthProfile(.none),
      catalogId: "galaxyssi.mcp.relay",
      id: "relay-remote"
    )
    _ = try mcpRegistry.markConnected(connection.id, toolIds: ["relay.status", "relay.switch"])
    let provider = AgentIOSMcpClientNativeProvider(
      registry: mcpRegistry,
      packageRootURL: root.appendingPathComponent("mcp", isDirectory: true),
      nowMillis: now
    )
    let definitions = AgentMcpNativeTools.definitions(provider: provider)
    let listTools = try XCTUnwrap(definitions.first { $0.id == AgentMcpNativeTools.listTools })
    let nativeRegistry = try AgentNativeToolRegistry(nowMillis: now).registerExecutables(
      AgentPhoneNativeToolCatalog.mcpExecutableDefinitions(provider: provider)
    )
    let context = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentMcpNativeTools.mcpHostPermission]
    )

    let connections = nativeRegistry.invoke(
      AgentMcpNativeTools.listConnections,
      input: [:],
      context: context
    )

    XCTAssertEqual(listTools.availabilityProvider.current().status, .available)
    XCTAssertTrue(connections.isSuccess)
    XCTAssertEqual(connections.output["count"], .int(1))
    XCTAssertEqual(connections.output["ready_connection_count"], .int(1))
    let listed = try XCTUnwrap(connections.output["connections"]?.arrayValue?.first?.objectValue)
    XCTAssertEqual(listed["id"], .string("relay-remote"))
    XCTAssertEqual(listed["catalog_id"], .string("galaxyssi.mcp.relay"))
    XCTAssertEqual(listed["auth_state"], .string("not_required"))
    XCTAssertEqual(listed["state"], .string("connected"))
    XCTAssertEqual(listed["callable"], .bool(true))
    XCTAssertEqual(listed["endpoint"]?.objectValue?["host"], .string("mcp.example"))
    XCTAssertNil(listed["endpoint"]?.objectValue?["path"])
    XCTAssertEqual(listed["tools"]?.arrayValue, [.string("relay.status"), .string("relay.switch")])

    let emptyProvider = AgentIOSMcpClientNativeProvider(nowMillis: now)
    let emptyDefinitions = AgentMcpNativeTools.definitions(provider: emptyProvider)
    let emptyConnections = try XCTUnwrap(emptyDefinitions.first { $0.id == AgentMcpNativeTools.listConnections })
    let emptyListTools = try XCTUnwrap(emptyDefinitions.first { $0.id == AgentMcpNativeTools.listTools })
    let emptyRegistry = try AgentNativeToolRegistry(nowMillis: now).registerExecutables(
      AgentPhoneNativeToolCatalog.mcpExecutableDefinitions(provider: emptyProvider)
    )
    let emptyListResult = emptyRegistry.invoke(
      AgentMcpNativeTools.listConnections,
      input: [:],
      context: context
    )
    let gatedTools = emptyRegistry.invoke(
      AgentMcpNativeTools.listTools,
      input: ["connection_id": .string("missing")],
      context: context
    )

    XCTAssertEqual(emptyConnections.availabilityProvider.current().status, .available)
    XCTAssertEqual(emptyListTools.availabilityProvider.current().status, .requiresSetup)
    XCTAssertTrue(emptyListResult.isSuccess)
    XCTAssertEqual(emptyListResult.output["connections"]?.arrayValue, [])
    XCTAssertEqual(gatedTools.status, .unavailable)
    XCTAssertEqual(gatedTools.error?.code, "tool_unavailable")
    XCTAssertEqual(gatedTools.error?.retryable, true)
  }

  func testAgentIOSMcpClientNativeProviderInvokesClientManagerToolsAndCalls() throws {
    let root = try temporaryDirectory("ios-mcp-native-provider-call")
    defer { try? FileManager.default.removeItem(at: root) }
    let now: () -> Int64 = { 30_000 }
    let repository = AgentMcpPackageRepository(rootDirectory: root)
    let auditStore = InMemoryAgentMcpAuditStore()
    let mcpRegistry = AgentMcpRegistry(InMemoryAgentMcpStore(), nowMillis: now)
    let connection = try mcpRegistry.addRemote(
      displayName: "Relay MCP",
      endpoint: "https://mcp.example/rpc",
      authProfile: try AgentMcpAuthProfile(.none),
      id: "relay-remote-call"
    )
    let networking = FakeMcpStreamableHTTPNetworking([
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: #"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","serverInfo":{"name":"relay-mcp","version":"1.0.0"},"capabilities":{"tools":{}}}}"#
      ),
      AgentMcpStreamableHTTPResponse(statusCode: 200, headers: [:], body: ""),
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: #"{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"relay.status","title":"Relay status","inputSchema":{"type":"object"},"annotations":{"readOnlyHint":true}}]}}"#
      ),
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: #"{"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"online"}],"structuredContent":{"online":true}}}"#
      )
    ])
    let manager = AgentMcpClientManager(
      registry: mcpRegistry,
      packageRepository: repository,
      auditStore: auditStore,
      remoteSessionFactory: { sessionConnection, headers in
        XCTAssertEqual(sessionConnection.id, connection.id)
        XCTAssertTrue(headers.isEmpty)
        let transport = try AgentMcpStreamableHTTPTransport(
          endpoint: sessionConnection.endpoint,
          requestHeaders: headers,
          networking: networking
        )
        return AgentMcpRemoteSession(transport: transport)
      },
      nowMillis: now
    )
    let provider = AgentIOSMcpClientNativeProvider(
      registry: mcpRegistry,
      clientManager: manager,
      packageRepository: repository,
      auditStore: auditStore,
      nowMillis: now
    )
    let nativeRegistry = try AgentNativeToolRegistry(nowMillis: now).registerExecutables(
      AgentPhoneNativeToolCatalog.mcpExecutableDefinitions(provider: provider)
    )
    let context = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentMcpNativeTools.mcpHostPermission]
    )

    let tools = nativeRegistry.invoke(
      AgentMcpNativeTools.listTools,
      input: ["connection_id": .string(connection.id)],
      context: context
    )
    let call = nativeRegistry.invoke(
      AgentMcpNativeTools.callTool,
      input: [
        "connection_id": .string(connection.id),
        "tool_name": .string("relay.status"),
        "arguments": .object([:])
      ],
      context: context
    )
    let activity = nativeRegistry.invoke(
      AgentMcpNativeTools.listConnections,
      input: [:],
      context: context
    )

    XCTAssertTrue(tools.isSuccess)
    XCTAssertEqual(tools.output["tool_count"], .int(1))
    XCTAssertEqual(tools.output["tools"]?.arrayValue?.first?.objectValue?["name"], .string("relay.status"))
    XCTAssertTrue(call.isSuccess)
    XCTAssertEqual(call.output["connection_id"], .string(connection.id))
    XCTAssertEqual(call.output["tool_name"], .string("relay.status"))
    XCTAssertEqual(call.output["structured_content"]?.objectValue?["online"], .bool(true))
    XCTAssertEqual(call.metadata["protocol"], .string("mcp"))
    XCTAssertEqual(call.metadata["implementation"], .string("galaxyssi.ios.mcp_client_manager"))
    XCTAssertEqual(call.metadata["mcp_permission_decision"], .string("allowed_low_risk"))
    XCTAssertTrue(activity.isSuccess)
    let listed = try XCTUnwrap(activity.output["connections"]?.arrayValue?.first?.objectValue)
    XCTAssertEqual(listed["recent_activity_count"], .int(1))
    let recent = try XCTUnwrap(listed["recent_activity"]?.arrayValue?.first?.objectValue)
    XCTAssertEqual(recent["tool_name"], .string("relay.status"))
    XCTAssertEqual(recent["status"], .string("succeeded"))
    XCTAssertEqual(recent["permission_decision"], .string("allowed_low_risk"))
    XCTAssertEqual(networking.requests.count, 4)
  }

  func testAgentIOSDefaultRegistryLoadsPersistentMcpConnections() throws {
    let root = try temporaryDirectory("ios-default-mcp-store")
    defer { try? FileManager.default.removeItem(at: root) }
    let now: () -> Int64 = { 40_000 }
    let mcpRoot = AgentIOSMcpClientNativeProvider.defaultPackageRootURL(storageRootURL: root)
    let mcpRegistry = AgentMcpRegistry(
      FileAgentMcpStore(rootURL: mcpRoot),
      nowMillis: now
    )
    let connection = try mcpRegistry.addRemote(
      displayName: "Persisted Relay",
      endpoint: "https://persisted.example/rpc",
      authProfile: try AgentMcpAuthProfile(.none),
      catalogId: "galaxyssi.mcp.persisted",
      id: "persisted-relay"
    )
    _ = try mcpRegistry.markConnected(connection.id, toolIds: ["persisted.status"])
    let nativeRegistry = try AgentPhoneNativeToolCatalog.defaultRegistry(
      actionExecutor: TestAgentActionExecutor { action, _ in
        AgentActionResult(actionId: action.id, success: true, message: "Executed")
      },
      screenProvider: { _ in AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent") },
      capabilityStatusProvider: { readyPhoneCapabilityStatuses() },
      storageRootURL: root,
      nowMillis: now
    )

    let result = nativeRegistry.invoke(
      AgentMcpNativeTools.listConnections,
      input: [:],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [AgentMcpNativeTools.mcpHostPermission]
      )
    )

    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(result.output["ready_connection_count"], .int(1))
    let listed = try XCTUnwrap(result.output["connections"]?.arrayValue?.first?.objectValue)
    XCTAssertEqual(listed["id"], .string("persisted-relay"))
    XCTAssertEqual(listed["tools"]?.arrayValue, [.string("persisted.status")])
    XCTAssertEqual(listed["endpoint"]?.objectValue?["host"], .string("persisted.example"))
  }

}
