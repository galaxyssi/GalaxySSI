import Foundation

final class AgentMcpClientManager {
  typealias RemoteSessionFactory = (AgentMcpConnection, [String: String]) throws -> AgentMcpRemoteSession

  private let registry: AgentMcpRegistry
  private let packageRepository: AgentMcpPackageRepository
  private let auditStore: AgentMcpAuditStore
  private let authCoordinator: AgentMcpAuthenticationCoordinator
  private let declarativeHTTPClient: AgentMcpDeclarativeHTTPClient
  private let localRuntimeClient: AgentMcpLocalRuntimeClient?
  private let remoteSessionFactory: RemoteSessionFactory
  private let nowMillis: () -> Int64
  private let lock = NSRecursiveLock()
  private var sessions: [String: AgentMcpRemoteSession] = [:]
  private var toolCache: [String: [String: AgentMcpTool]] = [:]

  init(
    registry: AgentMcpRegistry,
    packageRepository: AgentMcpPackageRepository,
    auditStore: AgentMcpAuditStore = InMemoryAgentMcpAuditStore(),
    authCoordinator: AgentMcpAuthenticationCoordinator? = nil,
    declarativeHTTPClient: AgentMcpDeclarativeHTTPClient? = nil,
    localRuntimeClient: AgentMcpLocalRuntimeClient? = nil,
    remoteSessionFactory: RemoteSessionFactory? = nil,
    nowMillis: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }
  ) {
    self.registry = registry
    self.packageRepository = packageRepository
    self.auditStore = auditStore
    self.authCoordinator = authCoordinator ?? AgentMcpAuthenticationCoordinator(registry: registry, nowMillis: nowMillis)
    self.declarativeHTTPClient = declarativeHTTPClient ?? AgentMcpDeclarativeHTTPClient(
      registry: registry,
      packageRepository: packageRepository,
      nowMillis: nowMillis
    )
    self.localRuntimeClient = localRuntimeClient
    self.remoteSessionFactory = remoteSessionFactory ?? { connection, headers in
      let transport = try AgentMcpStreamableHTTPTransport(endpoint: connection.endpoint, requestHeaders: headers)
      return AgentMcpRemoteSession(transport: transport)
    }
    self.nowMillis = nowMillis
  }

  func listTools(connectionId: String) async throws -> [AgentMcpTool] {
    let connection = try await prepareConnection(try requireConnection(connectionId))
    let tools: [AgentMcpTool]
    switch connection.transport {
    case .declarativeHTTP:
      tools = try declarativeHTTPClient.listTools(connection: connection)
    case .localStdio:
      guard let localRuntimeClient else {
        throw AgentRuntimeCapabilityError.invalid("Local MCP runtime client is unavailable on this device")
      }
      tools = try localRuntimeClient.listTools(connection: connection)
    case .streamableHTTP:
      tools = try await withRemoteSession(connection) { session in
        let page = try await session.listTools()
        return page.items
      }
    }
    cacheTools(connectionId: connection.id, tools: tools)
    return tools
  }

  func callTool(
    connectionId: String,
    toolName: String,
    arguments: AgentMcpJSONObject,
    context: AgentNativeToolInvocationContext = AgentNativeToolInvocationContext()
  ) async -> AgentNativeToolExecutionResult {
    let startedAt = nowMillis()
    let connection: AgentMcpConnection
    do {
      connection = try await prepareConnection(try requireConnection(connectionId))
    } catch {
      return AgentNativeToolExecutionResult.failure(
        code: "mcp_connection_unavailable",
        message: error.localizedDescription.nilIfEmpty ?? "MCP connection is not available",
        retryable: false,
        details: ["connection_id": .string(connectionId)]
      )
    }
    let listedTool: AgentMcpTool?
    if let cached = cachedTool(connectionId: connection.id, toolName: toolName) {
      listedTool = cached
    } else {
      listedTool = (try? await listTools(connectionId: connection.id))?.first { $0.name == toolName }
    }
    let tool = listedTool ?? AgentMcpTool(name: toolName, raw: ["name": .string(toolName)])
    let assessment = AgentMcpToolSecurityPolicy.assess(tool: tool, arguments: arguments, transport: connection.transport)
    let decision = AgentMcpToolSecurityPolicy.decide(
      mode: connection.permissionMode,
      assessment: assessment,
      explicitlyApproved: context.attributes["explicit_user_approval"] == "true"
    )
    if !decision.allowed {
      let audit = appendAudit(
        connection: connection,
        toolName: toolName,
        assessment: assessment,
        decision: decision,
        context: context,
        status: "denied",
        startedAtMillis: startedAt,
        errorCode: decision.code,
        errorMessage: decision.message
      )
      return withAuditMetadata(
        AgentNativeToolExecutionResult.failure(
          code: decision.code,
          message: decision.message,
          retryable: false,
          details: failureDetails(connectionId: connection.id, toolName: toolName, assessment: assessment, decision: decision)
        ),
        assessment: assessment,
        decision: decision,
        audit: audit
      )
    }

    do {
      let result: AgentNativeToolExecutionResult
      switch connection.transport {
      case .declarativeHTTP:
        result = try await declarativeHTTPClient.callTool(connection: connection, toolName: toolName, arguments: arguments)
      case .localStdio:
        guard let localRuntimeClient else {
          throw AgentRuntimeCapabilityError.invalid("Local MCP runtime client is unavailable on this device")
        }
        result = try localRuntimeClient.callTool(connection: connection, toolName: toolName, arguments: arguments)
        if result.isSuccess {
          _ = try? registry.markConnected(connection.id, toolIds: connection.toolIds.isEmpty ? [toolName] : connection.toolIds)
        }
      case .streamableHTTP:
        result = try await withRemoteSession(connection) { session in
          let call = try await session.callTool(name: toolName, arguments: arguments)
          return remoteToolResult(call, connection: connection, toolName: toolName)
        }
      }
      _ = try? registry.markConnected(connection.id, toolIds: knownToolIds(connection: connection, fallbackToolName: toolName))
      let audit = appendAudit(
        connection: connection,
        toolName: toolName,
        assessment: assessment,
        decision: decision,
        context: context,
        status: result.isSuccess ? "succeeded" : "failed",
        startedAtMillis: startedAt,
        outputSha256: AgentMcpJSONCodec.sha256(result.output),
        errorCode: result.error?.code ?? "",
        errorMessage: result.error?.message ?? ""
      )
      return withAuditMetadata(result, assessment: assessment, decision: decision, audit: audit)
    } catch {
      handleFailure(connection.id, error: error)
      let code = isAuthenticationFailure(error) ? "mcp_authentication_required" : "mcp_call_failed"
      let audit = appendAudit(
        connection: connection,
        toolName: toolName,
        assessment: assessment,
        decision: decision,
        context: context,
        status: "failed",
        startedAtMillis: startedAt,
        errorCode: code,
        errorMessage: error.localizedDescription.nilIfEmpty ?? "MCP tool call failed"
      )
      return withAuditMetadata(
        AgentNativeToolExecutionResult.failure(
          code: code,
          message: error.localizedDescription.nilIfEmpty ?? "MCP tool call failed",
          retryable: code != "mcp_authentication_required",
          details: failureDetails(connectionId: connection.id, toolName: toolName, assessment: assessment, decision: decision)
        ),
        assessment: assessment,
        decision: decision,
        audit: audit
      )
    }
  }

  func audit(connectionId: String = "", limit: Int = 100) -> [AgentMcpAuditRecord] {
    auditStore.list(connectionId: connectionId, limit: limit)
  }

  func close(connectionId: String) {
    synchronized {
      sessions.removeValue(forKey: connectionId)?.close()
      toolCache.removeValue(forKey: connectionId)
    }
  }

  func closeAll() {
    let current = synchronized { () -> [AgentMcpRemoteSession] in
      let values = Array(sessions.values)
      sessions.removeAll()
      toolCache.removeAll()
      return values
    }
    current.forEach { $0.close() }
  }

  private func withRemoteSession<T>(
    _ connection: AgentMcpConnection,
    block: (AgentMcpRemoteSession) async throws -> T
  ) async throws -> T {
    guard connection.isCallable(nowMillis: nowMillis()) else {
      throw AgentRuntimeCapabilityError.invalid("MCP connection requires authentication or setup")
    }
    _ = try registry.markConnecting(connection.id)
    let session = try await remoteSession(connection)
    do {
      return try await block(session)
    } catch {
      close(connectionId: connection.id)
      handleFailure(connection.id, error: error)
      throw error
    }
  }

  private func remoteSession(_ connection: AgentMcpConnection) async throws -> AgentMcpRemoteSession {
    if let existing = synchronized({ sessions[connection.id] }), existing.state == .active {
      return existing
    }
    let session = try remoteSessionFactory(connection, registry.requestHeaders(connection.id))
    _ = try await session.initialize(clientInfo: AgentMcpImplementationInfo(
      name: "galaxyssi-ios",
      version: "1.0.0",
      title: "GalaxySSI iOS"
    ))
    synchronized {
      sessions[connection.id] = session
    }
    return session
  }

  private func prepareConnection(_ connection: AgentMcpConnection) async throws -> AgentMcpConnection {
    if connection.effectiveAuthState(nowMillis: nowMillis()) == .refreshing,
       connection.authProfile.refreshExchange != nil {
      return try await authCoordinator.refreshIfNeeded(connectionId: connection.id)
    }
    return connection
  }

  private func requireConnection(_ id: String) throws -> AgentMcpConnection {
    guard let connection = registry.get(id), connection.enabled else {
      throw AgentRuntimeCapabilityError.invalid("MCP connection is not available: \(id)")
    }
    return connection
  }

  private func cachedTool(connectionId: String, toolName: String) -> AgentMcpTool? {
    synchronized { toolCache[connectionId]?[toolName] }
  }

  private func knownToolIds(connection: AgentMcpConnection, fallbackToolName: String) -> [String] {
    if let cached = synchronized({ toolCache[connection.id] }), !cached.isEmpty {
      return cached.keys.sorted()
    }
    return connection.toolIds.isEmpty ? [fallbackToolName] : connection.toolIds
  }

  private func cacheTools(connectionId: String, tools: [AgentMcpTool]) {
    synchronized {
      toolCache[connectionId] = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
    }
    _ = try? registry.markConnected(connectionId, toolIds: tools.map(\.name))
  }

  private func appendAudit(
    connection: AgentMcpConnection,
    toolName: String,
    assessment: AgentMcpToolAssessment,
    decision: AgentMcpPermissionDecision,
    context: AgentNativeToolInvocationContext,
    status: String,
    startedAtMillis: Int64,
    outputSha256: String = "",
    errorCode: String = "",
    errorMessage: String = ""
  ) -> AgentMcpAuditRecord {
    let record = AgentMcpAuditRecord.toolCall(
      connection: connection,
      toolName: toolName,
      assessment: assessment,
      decision: decision,
      context: context,
      status: status,
      durationMillis: nowMillis() - startedAtMillis,
      outputSha256: outputSha256,
      errorCode: errorCode,
      errorMessage: errorMessage,
      timestampMillis: nowMillis()
    )
    auditStore.append(record)
    return record
  }

  private func remoteToolResult(
    _ call: AgentMcpToolCallResult,
    connection: AgentMcpConnection,
    toolName: String
  ) -> AgentNativeToolExecutionResult {
    let message = call.content
      .compactMap { $0.text?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
      .joined(separator: "\n")
      .nilIfEmpty ?? (call.isError ? "MCP tool returned an error" : "MCP tool completed")
    if call.isError {
      return AgentNativeToolExecutionResult.failure(code: "mcp_tool_error", message: message, retryable: false)
    }
    var output: AgentMcpJSONObject = [
      "connection_id": .string(connection.id),
      "tool_name": .string(toolName),
      "content": .array(call.content.map { .object(contentValue($0)) })
    ]
    if let structuredContent = call.structuredContent {
      output["structured_content"] = .object(structuredContent)
    }
    return AgentNativeToolExecutionResult.success(
      output: output,
      message: message,
      metadata: [
        "transport": .string(AgentMcpTransportKind.streamableHTTP.rawValue),
        "server": .string(connection.displayName)
      ]
    )
  }

  private func contentValue(_ content: AgentMcpContent) -> AgentMcpJSONObject {
    var object: AgentMcpJSONObject = ["type": .string(content.type)]
    if let text = content.text {
      object["text"] = .string(text)
    }
    if let data = content.data {
      object["data"] = .string(data)
    }
    if let mimeType = content.mimeType {
      object["mime_type"] = .string(mimeType)
    }
    if let uri = content.uri {
      object["uri"] = .string(uri)
    }
    if let name = content.name {
      object["name"] = .string(name)
    }
    return object
  }

  private func withAuditMetadata(
    _ result: AgentNativeToolExecutionResult,
    assessment: AgentMcpToolAssessment,
    decision: AgentMcpPermissionDecision,
    audit: AgentMcpAuditRecord
  ) -> AgentNativeToolExecutionResult {
    var metadata = result.metadata
    metadata["mcp_security"] = .object(assessment.publicValue())
    metadata["mcp_permission_decision"] = .string(decision.code)
    metadata["mcp_audit_id"] = .string(audit.auditId)
    return AgentNativeToolExecutionResult(
      output: result.output,
      message: result.message,
      metadata: metadata,
      error: result.error
    )
  }

  private func failureDetails(
    connectionId: String,
    toolName: String,
    assessment: AgentMcpToolAssessment,
    decision: AgentMcpPermissionDecision
  ) -> AgentMcpJSONObject {
    var details: AgentMcpJSONObject = [
      "connection_id": .string(connectionId),
      "tool_name": .string(toolName),
      "risk": .string(assessment.risk.rawValue),
      "permissions": .array(assessment.permissions.sorted().map { .string($0) }),
      "parameter_preview": .object(assessment.parameterPreview)
    ]
    if !decision.requiredUserAction.isEmpty {
      details["required_user_action"] = .string(decision.requiredUserAction)
    }
    return details
  }

  private func handleFailure(_ id: String, error: Error) {
    _ = try? registry.markFailure(
      id,
      message: error.localizedDescription.nilIfEmpty ?? String(describing: error),
      authenticationFailure: isAuthenticationFailure(error)
    )
  }

  private func isAuthenticationFailure(_ error: Error) -> Bool {
    if let declarative = error as? AgentMcpDeclarativeHTTPError {
      return declarative.authenticationFailure
    }
    if let streamable = error as? AgentMcpStreamableHTTPError {
      return streamable.authenticationFailure
    }
    return false
  }

  private func synchronized<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }
}
