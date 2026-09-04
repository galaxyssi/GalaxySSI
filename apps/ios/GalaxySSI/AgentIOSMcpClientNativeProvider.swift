import Foundation

struct AgentIOSMcpClientNativeProvider: AgentIOSMcpNativeToolProviding {
  var implementationId: String = "galaxyssi.ios.mcp_client_manager"

  private let registry: AgentMcpRegistry
  private let clientManager: AgentMcpClientManager
  private let auditStore: AgentMcpAuditStore
  private let nowMillis: () -> Int64

  init(
    registry: AgentMcpRegistry = AgentMcpRegistry(InMemoryAgentMcpStore()),
    clientManager: AgentMcpClientManager? = nil,
    packageRepository: AgentMcpPackageRepository? = nil,
    auditStore: AgentMcpAuditStore = InMemoryAgentMcpAuditStore(),
    packageRootURL: URL? = nil,
    fileManager: FileManager = .default,
    nowMillis: @escaping () -> Int64 = {
      Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    }
  ) {
    let repository = packageRepository ?? AgentMcpPackageRepository(
      rootDirectory: packageRootURL ?? Self.defaultPackageRootURL(fileManager: fileManager),
      fileManager: fileManager
    )
    self.registry = registry
    self.auditStore = auditStore
    self.nowMillis = nowMillis
    self.clientManager = clientManager ?? AgentMcpClientManager(
      registry: registry,
      packageRepository: repository,
      auditStore: auditStore,
      nowMillis: nowMillis
    )
  }

  func availability(operation: AgentIOSMcpNativeToolOperation) -> AgentNativeToolAvailability {
    switch operation {
    case .listConnections:
      return AgentNativeToolAvailability(
        status: .available,
        checkedAtEpochMillis: nowMillis()
      )
    case .listTools, .callTool:
      guard registry.readyConnections().isEmpty else {
        return AgentNativeToolAvailability(
          status: .available,
          checkedAtEpochMillis: nowMillis()
        )
      }
      return AgentNativeToolAvailability(
        status: .requiresSetup,
        reason: "No authenticated MCP connection is ready",
        checkedAtEpochMillis: nowMillis()
      )
    }
  }

  func invoke(
    operation: AgentIOSMcpNativeToolOperation,
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    switch operation {
    case .listConnections:
      return listConnections()
    case .listTools:
      return listTools(input)
    case .callTool:
      return callTool(input, context: invocation.context)
    }
  }

  static func defaultPackageRootURL(
    storageRootURL: URL? = nil,
    fileManager: FileManager = .default
  ) -> URL {
    let root = storageRootURL ?? AgentNativeToolDefaultStorePaths.applicationSupportRootURL(fileManager: fileManager)
    return root
      .appendingPathComponent("mcp", isDirectory: true)
  }

  static func defaultAuditFileURL(
    storageRootURL: URL = AgentNativeToolDefaultStorePaths.applicationSupportRootURL()
  ) -> URL {
    storageRootURL
      .appendingPathComponent("mcp", isDirectory: true)
      .appendingPathComponent("agent-mcp-audit.json", isDirectory: false)
  }

  private func listConnections() -> AgentNativeToolExecutionResult {
    let connections = registry.list()
    let readyCount = registry.readyConnections().count
    return AgentNativeToolExecutionResult.success(
      output: [
        "connections": .array(connections.map { .object(connectionValue($0)) }),
        "count": .int(Int64(connections.count)),
        "ready_connection_count": .int(Int64(readyCount))
      ],
      message: connections.isEmpty ? "No MCP connections installed" : "MCP connections listed",
      metadata: baseMetadata()
    )
  }

  private func listTools(_ input: AgentMcpJSONObject) -> AgentNativeToolExecutionResult {
    let parsed = requiredString(input, key: "connection_id", maxLength: 128)
    guard parsed.isValid else {
      return invalidInput(parsed.errorMessage)
    }
    let connectionId = parsed.value
    guard registry.get(connectionId)?.isCallable(nowMillis: nowMillis()) == true else {
      return connectionUnavailable(connectionId)
    }
    do {
      let tools = try Self.awaitBlocking {
        try await clientManager.listTools(connectionId: connectionId)
      }
      return AgentNativeToolExecutionResult.success(
        output: [
          "connection_id": .string(connectionId),
          "tools": .array(tools.map { .object(toolValue($0)) }),
          "tool_count": .int(Int64(tools.count))
        ],
        message: tools.isEmpty ? "No MCP tools exposed" : "MCP tools discovered",
        metadata: baseMetadata(extra: [
          "connection_id": .string(connectionId)
        ])
      )
    } catch {
      return AgentNativeToolExecutionResult.failure(
        code: "mcp_tools_unavailable",
        message: error.localizedDescription.nilIfEmpty ?? "MCP tools are unavailable",
        retryable: true,
        details: [
          "connection_id": .string(connectionId)
        ]
      )
    }
  }

  private func callTool(
    _ input: AgentMcpJSONObject,
    context: AgentNativeToolInvocationContext
  ) -> AgentNativeToolExecutionResult {
    let parsedConnection = requiredString(input, key: "connection_id", maxLength: 128)
    guard parsedConnection.isValid else {
      return invalidInput(parsedConnection.errorMessage)
    }
    let parsedTool = requiredString(input, key: "tool_name", maxLength: 192)
    guard parsedTool.isValid else {
      return invalidInput(parsedTool.errorMessage)
    }
    guard let arguments = input["arguments"]?.objectValue else {
      return invalidInput("MCP tool arguments must be an object")
    }
    let connectionId = parsedConnection.value
    let toolName = parsedTool.value
    guard registry.get(connectionId)?.isCallable(nowMillis: nowMillis()) == true else {
      return connectionUnavailable(connectionId)
    }
    do {
      let result = try Self.awaitBlocking {
        await clientManager.callTool(
          connectionId: connectionId,
          toolName: toolName,
          arguments: arguments,
          context: context
        )
      }
      var metadata = result.metadata
      baseMetadata(extra: [
        "connection_id": .string(connectionId),
        "tool_name": .string(toolName)
      ]).forEach { metadata[$0.key] = metadata[$0.key] ?? $0.value }
      return AgentNativeToolExecutionResult(
        output: result.output,
        message: result.message,
        metadata: metadata,
        error: result.error
      )
    } catch {
      return AgentNativeToolExecutionResult.failure(
        code: "mcp_tool_call_failed",
        message: error.localizedDescription.nilIfEmpty ?? "MCP tool call failed",
        retryable: true,
        details: [
          "connection_id": .string(connectionId),
          "tool_name": .string(toolName)
        ]
      )
    }
  }

  private func connectionValue(_ connection: AgentMcpConnection) -> AgentMcpJSONObject {
    let authState = connection.effectiveAuthState(nowMillis: nowMillis())
    var value: AgentMcpJSONObject = [
      "id": .string(connection.id),
      "catalog_id": .string(connection.catalogId),
      "name": .string(connection.displayName),
      "distribution": .string(connection.distribution.rawValue),
      "transport": .string(connection.transport.rawValue),
      "auth_state": .string(authState.rawValue),
      "state": .string(connection.state.rawValue),
      "enabled": .bool(connection.enabled),
      "permission_mode": .string(connection.permissionMode.rawValue),
      "callable": .bool(connection.isCallable(nowMillis: nowMillis())),
      "tools": .array(connection.toolIds.map(AgentMcpJSONValue.string)),
      "tool_count": .int(Int64(connection.toolIds.count)),
      "installed_at": .int(connection.installedAtMillis),
      "updated_at": .int(connection.updatedAtMillis),
      "last_validated_at": .int(connection.lastValidatedAtMillis)
    ]
    if let endpoint = endpointPreview(connection.endpoint) {
      value["endpoint"] = .object(endpoint)
    }
    if !connection.packageVersion.isEmpty {
      value["package_version"] = .string(connection.packageVersion)
    }
    if !connection.lastError.isEmpty {
      value["last_error"] = .string(Self.bounded(connection.lastError, limit: 1_000))
    }
    let recentActivity = auditStore.list(connectionId: connection.id, limit: Self.recentActivityLimit)
    value["recent_activity"] = .array(recentActivity.map { .object(auditValue($0)) })
    value["recent_activity_count"] = .int(Int64(recentActivity.count))
    return value
  }

  private func auditValue(_ record: AgentMcpAuditRecord) -> AgentMcpJSONObject {
    var value: AgentMcpJSONObject = [
      "audit_id": .string(record.auditId),
      "timestamp_ms": .int(record.timestampMillis),
      "tool_name": .string(record.toolName),
      "status": .string(record.status),
      "risk": .string(record.risk),
      "permission_decision": .string(record.permissionDecision),
      "duration_ms": .int(record.durationMillis),
      "source": .string(record.source)
    ]
    if !record.errorCode.isEmpty {
      value["error_code"] = .string(record.errorCode)
    }
    return value
  }

  private func toolValue(_ tool: AgentMcpTool) -> AgentMcpJSONObject {
    var value: AgentMcpJSONObject = [
      "name": .string(tool.name),
      "input_schema": .object(tool.inputSchema)
    ]
    if let title = tool.title?.nilIfEmpty {
      value["title"] = .string(title)
    }
    if let description = tool.description?.nilIfEmpty {
      value["description"] = .string(description)
    }
    if let outputSchema = tool.outputSchema {
      value["output_schema"] = .object(outputSchema)
    }
    if let annotations = tool.annotations {
      value["annotations"] = .object(annotations)
    }
    if !tool.raw.isEmpty {
      value["raw"] = .object(tool.raw)
    }
    return value
  }

  private func endpointPreview(_ endpoint: String) -> AgentMcpJSONObject? {
    guard let components = URLComponents(string: endpoint),
          let host = components.host?.nilIfEmpty else {
      return nil
    }
    var value: AgentMcpJSONObject = [
      "scheme": .string(components.scheme?.lowercased() ?? ""),
      "host": .string(host)
    ]
    if let port = components.port {
      value["port"] = .int(Int64(port))
    }
    return value
  }

  private func requiredString(
    _ input: AgentMcpJSONObject,
    key: String,
    maxLength: Int
  ) -> (isValid: Bool, value: String, errorMessage: String) {
    let value = input[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !value.isEmpty else {
      return (false, "", "\(key) is required")
    }
    guard value.count <= maxLength else {
      return (false, "", "\(key) is too long")
    }
    return (true, value, "")
  }

  private func invalidInput(_ message: String) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.failure(
      code: "mcp_invalid_input",
      message: message,
      retryable: false
    )
  }

  private func connectionUnavailable(_ connectionId: String) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.failure(
      code: "mcp_connection_unavailable",
      message: "MCP connection is not ready: \(connectionId)",
      retryable: false,
      details: [
        "connection_id": .string(connectionId)
      ]
    )
  }

  private func baseMetadata(extra: AgentMcpJSONObject = [:]) -> AgentMcpJSONObject {
    var metadata: AgentMcpJSONObject = [
      "implementation": .string(implementationId),
      "protocol": .string("mcp"),
      "host": .string("ios"),
      "permission_enforcement": .string("mcp_security_policy")
    ]
    extra.forEach { metadata[$0.key] = $0.value }
    return metadata
  }

  private static func bounded(_ value: String, limit: Int) -> String {
    String(value.prefix(limit))
  }

  private static let recentActivityLimit = 3

  private static func awaitBlocking<T>(_ operation: @escaping () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    let lock = NSLock()
    var result: Result<T, Error>?
    Task {
      do {
        let value = try await operation()
        lock.lock()
        result = .success(value)
        lock.unlock()
      } catch {
        lock.lock()
        result = .failure(error)
        lock.unlock()
      }
      semaphore.signal()
    }
    semaphore.wait()
    lock.lock()
    let captured = result
    lock.unlock()
    return try captured!.get()
  }
}
