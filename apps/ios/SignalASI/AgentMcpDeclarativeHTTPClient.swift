import Foundation

final class AgentMcpDeclarativeHTTPClient {
  private let registry: AgentMcpRegistry
  private let packageRepository: AgentMcpPackageRepository
  private let transport: AgentMcpDeclarativeHTTPTransport
  private let nowMillis: () -> Int64

  init(
    registry: AgentMcpRegistry,
    packageRepository: AgentMcpPackageRepository,
    transport: AgentMcpDeclarativeHTTPTransport = URLSessionAgentMcpDeclarativeHTTPTransport(),
    nowMillis: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }
  ) {
    self.registry = registry
    self.packageRepository = packageRepository
    self.transport = transport
    self.nowMillis = nowMillis
  }

  func listTools(connection: AgentMcpConnection) throws -> [AgentMcpTool] {
    guard connection.transport == .declarativeHTTP else {
      throw AgentRuntimeCapabilityError.invalid("MCP connection is not a declarative HTTP server")
    }
    guard connection.isCallable(nowMillis: nowMillis()) else {
      throw AgentRuntimeCapabilityError.invalid("MCP connection requires authentication or setup")
    }
    guard let manifest = packageRepository.get(connection.id) else {
      throw AgentRuntimeCapabilityError.invalid("Declarative MCP package metadata is missing")
    }
    let tools = manifest.tools.map { tool in
      AgentMcpTool(
        name: tool.name,
        title: tool.title,
        description: tool.description,
        inputSchema: tool.inputSchema,
        outputSchema: nil,
        annotations: ["readOnlyHint": .bool(!tool.mutating)],
        raw: ["name": .string(tool.name)]
      )
    }
    _ = try registry.markConnected(connection.id, toolIds: tools.map(\.name))
    return tools
  }

  func callTool(
    connection: AgentMcpConnection,
    toolName: String,
    arguments: AgentMcpJSONObject
  ) async throws -> AgentNativeToolExecutionResult {
    guard connection.transport == .declarativeHTTP else {
      throw AgentRuntimeCapabilityError.invalid("MCP connection is not a declarative HTTP server")
    }
    guard connection.isCallable(nowMillis: nowMillis()) else {
      throw AgentRuntimeCapabilityError.invalid("MCP connection requires authentication or setup")
    }
    guard let manifest = packageRepository.get(connection.id) else {
      return AgentNativeToolExecutionResult.failure(
        code: "mcp_package_missing",
        message: "Declarative MCP package metadata is missing",
        details: ["connection_id": .string(connection.id)]
      )
    }
    guard let tool = manifest.tools.first(where: { $0.name == toolName }) else {
      return AgentNativeToolExecutionResult.failure(
        code: "mcp_tool_missing",
        message: "Declarative MCP tool is not installed: \(toolName)",
        details: [
          "connection_id": .string(connection.id),
          "tool_name": .string(toolName)
        ]
      )
    }

    do {
      _ = try registry.markConnecting(connection.id)
      let request = try makeRequest(connection: connection, tool: tool, arguments: arguments)
      let response = try await transport.execute(request)
      let result = try makeResult(
        response: response,
        connection: connection,
        toolName: toolName,
        resultJsonPath: tool.resultJsonPath
      )
      _ = try registry.markConnected(connection.id, toolIds: manifest.tools.map(\.name))
      return result
    } catch {
      let authFailure = (error as? AgentMcpDeclarativeHTTPError)?.authenticationFailure == true
      let message = error.localizedDescription.nilIfEmpty ?? String(describing: error)
      _ = try? registry.markFailure(connection.id, message: message, authenticationFailure: authFailure)
      throw error
    }
  }

  private func makeRequest(
    connection: AgentMcpConnection,
    tool: AgentMcpDeclarativeTool,
    arguments: AgentMcpJSONObject
  ) throws -> AgentMcpDeclarativeHTTPRequest {
    let url = try resolveURL(endpoint: connection.endpoint, pathTemplate: tool.pathTemplate, arguments: arguments)
    var headers: [String: String] = [
      "Accept": "application/json, text/plain"
    ]
    for (key, value) in try registry.requestHeaders(connection.id) {
      if let sanitized = sanitizedHeader(name: key, value: value) {
        headers[sanitized.name] = sanitized.value
      }
    }
    for (key, value) in tool.headerTemplates {
      let rendered = renderHeaderTemplate(value, arguments: arguments, secrets: registry.secrets(connection.id))
      if let sanitized = sanitizedHeader(name: key, value: rendered) {
        headers[sanitized.name] = sanitized.value
      }
    }
    return AgentMcpDeclarativeHTTPRequest(
      method: tool.method,
      url: url.absoluteString,
      headers: headers,
      body: body(for: tool, arguments: arguments)
    )
  }

  private func makeResult(
    response: AgentMcpDeclarativeHTTPResponse,
    connection: AgentMcpConnection,
    toolName: String,
    resultJsonPath: String
  ) throws -> AgentNativeToolExecutionResult {
    guard response.body.utf8.count <= Self.maxResponseBytes else {
      throw AgentRuntimeCapabilityError.invalid("Declarative MCP response is too large")
    }
    guard (200...299).contains(response.statusCode) else {
      throw AgentMcpDeclarativeHTTPError(
        statusCode: response.statusCode,
        message: [401, 403].contains(response.statusCode)
          ? "MCP authentication expired"
          : "MCP endpoint returned HTTP \(response.statusCode)",
        authenticationFailure: [401, 403].contains(response.statusCode)
      )
    }
    let parsed = parseResponse(response.body)
    let selected = selectJsonPath(resultJsonPath, from: parsed)
    return AgentNativeToolExecutionResult.success(
      output: [
        "connection_id": .string(connection.id),
        "tool_name": .string(toolName),
        "result": selected,
        "http_status": .int(Int64(response.statusCode))
      ],
      message: resultMessage(selected),
      metadata: [
        "transport": .string(AgentMcpTransportKind.declarativeHTTP.rawValue),
        "server": .string(connection.displayName)
      ]
    )
  }

  private func resolveURL(
    endpoint: String,
    pathTemplate: String,
    arguments: AgentMcpJSONObject
  ) throws -> URL {
    guard let base = URL(string: endpoint) else {
      throw AgentRuntimeCapabilityError.invalid("Declarative MCP endpoint is invalid")
    }
    let renderedPath = renderPathTemplate(pathTemplate, arguments: arguments)
    guard let target = URL(string: renderedPath, relativeTo: base)?.absoluteURL,
          sameOrigin(base, target) else {
      throw AgentRuntimeCapabilityError.invalid("Declarative MCP request cannot leave its configured server")
    }
    return target
  }

  private func renderPathTemplate(_ template: String, arguments: AgentMcpJSONObject) -> String {
    renderArgumentTemplate(template, arguments: arguments) { value in
      let text = value?.stringValue ?? ""
      return text.addingPercentEncoding(withAllowedCharacters: Self.pathArgumentAllowedCharacters) ?? ""
    }
  }

  private func renderHeaderTemplate(
    _ template: String,
    arguments: AgentMcpJSONObject,
    secrets: [String: String]
  ) -> String {
    let withArguments = renderArgumentTemplate(template, arguments: arguments) { value in
      if let scalar = value?.stringValue {
        return scalar
      }
      return value.map(AgentMcpJSONCodec.stringify) ?? ""
    }
    let source = withArguments as NSString
    var rendered = ""
    var cursor = 0
    for match in Self.authPattern.matches(in: withArguments, range: NSRange(location: 0, length: source.length)) {
      rendered += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
      rendered += secrets[source.substring(with: match.range(at: 1))] ?? ""
      cursor = match.range.location + match.range.length
    }
    rendered += source.substring(from: cursor)
    return rendered
  }

  private func body(for tool: AgentMcpDeclarativeTool, arguments: AgentMcpJSONObject) -> String? {
    guard Self.bodyMethods.contains(tool.method) else {
      return nil
    }
    let template = tool.bodyTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !template.isEmpty, template != "{{args}}" else {
      return AgentMcpJSONCodec.stringify(arguments)
    }
    return renderArgumentTemplate(tool.bodyTemplate, arguments: arguments) { value in
      AgentMcpJSONCodec.stringify(value ?? .null)
    }
  }

  private func renderArgumentTemplate(
    _ template: String,
    arguments: AgentMcpJSONObject,
    replacement: (AgentMcpJSONValue?) -> String
  ) -> String {
    let source = template as NSString
    var rendered = ""
    var cursor = 0
    for match in Self.argumentPattern.matches(in: template, range: NSRange(location: 0, length: source.length)) {
      rendered += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
      rendered += replacement(argumentValue(source.substring(with: match.range(at: 1)), in: arguments))
      cursor = match.range.location + match.range.length
    }
    rendered += source.substring(from: cursor)
    return rendered
  }

  private func argumentValue(_ path: String, in arguments: AgentMcpJSONObject) -> AgentMcpJSONValue? {
    var current: AgentMcpJSONValue? = .object(arguments)
    for component in path.split(separator: ".").map(String.init) {
      guard let value = current, case .object(let object) = value else {
        return nil
      }
      current = object[component]
    }
    return current
  }

  private func sanitizedHeader(name: String, value: String) -> (name: String, value: String)? {
    let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty,
          !key.contains("\r"),
          !key.contains("\n"),
          !cleanValue.contains("\r"),
          !cleanValue.contains("\n") else {
      return nil
    }
    return (key, String(cleanValue.prefix(Self.maxHeaderValueCharacters)))
  }

  private func parseResponse(_ body: String) -> AgentMcpJSONValue {
    let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return .object([:])
    }
    if let data = trimmed.data(using: .utf8),
       let decoded = try? JSONDecoder().decode(AgentMcpJSONValue.self, from: data) {
      return decoded
    }
    return .string(trimmed)
  }

  private func selectJsonPath(_ path: String, from value: AgentMcpJSONValue) -> AgentMcpJSONValue {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed != "$" else {
      return value
    }
    guard trimmed.hasPrefix("$.") else {
      return value
    }
    var current = value
    for component in trimmed.dropFirst(2).split(separator: ".").map(String.init) {
      switch current {
      case .object(let object):
        guard let next = object[component] else {
          return .null
        }
        current = next
      case .array(let values):
        guard let index = Int(component), values.indices.contains(index) else {
          return .null
        }
        current = values[index]
      case .string, .int, .double, .bool, .null:
        return .null
      }
    }
    return current
  }

  private func sameOrigin(_ left: URL, _ right: URL) -> Bool {
    left.scheme?.lowercased() == right.scheme?.lowercased() &&
      left.host?.lowercased() == right.host?.lowercased() &&
      effectivePort(left) == effectivePort(right)
  }

  private func effectivePort(_ url: URL) -> Int {
    if let port = url.port {
      return port
    }
    switch url.scheme?.lowercased() {
    case "http":
      return 80
    case "https":
      return 443
    default:
      return -1
    }
  }

  private func resultMessage(_ value: AgentMcpJSONValue) -> String {
    if case .string(let text) = value {
      return String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4_000)).nilIfEmpty ?? "MCP tool completed"
    }
    return "MCP tool completed"
  }

  private static let maxResponseBytes = 1_024 * 1_024
  private static let maxHeaderValueCharacters = 8_192
  private static let bodyMethods: Set<String> = ["POST", "PUT", "PATCH", "DELETE"]
  private static let pathArgumentAllowedCharacters = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
  )
  private static let argumentPattern = try! NSRegularExpression(pattern: #"\{\{args\.([A-Za-z0-9_.-]+)\}\}"#)
  private static let authPattern = try! NSRegularExpression(pattern: #"\{\{auth\.([A-Za-z0-9_.-]+)\}\}"#)
}
