import Foundation

final class AgentMcpAuthenticationCoordinator {
  private let registry: AgentMcpRegistry
  private let transport: AgentMcpDeclarativeHTTPTransport
  private let nowMillis: () -> Int64

  init(
    registry: AgentMcpRegistry,
    transport: AgentMcpDeclarativeHTTPTransport = URLSessionAgentMcpDeclarativeHTTPTransport(),
    nowMillis: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }
  ) {
    self.registry = registry
    self.transport = transport
    self.nowMillis = nowMillis
  }

  func submitStep(connectionId: String, values: [String: String]) async throws -> AgentMcpConnection {
    let connection = try requireConnection(connectionId)
    guard let step = connection.currentAuthStep else {
      throw AgentRuntimeCapabilityError.invalid("No authentication step is pending")
    }
    guard let exchange = step.exchange else {
      return try registry.submitAuthenticationStep(connectionId, values: values)
    }
    let mapped = try await executeExchange(connection: connection, exchange: exchange, fields: values)
    return try registry.submitAuthenticationStep(connectionId, values: values.merging(mapped) { _, new in new })
  }

  func refreshIfNeeded(connectionId: String) async throws -> AgentMcpConnection {
    let connection = try requireConnection(connectionId)
    guard connection.effectiveAuthState(nowMillis: nowMillis()) == .refreshing else {
      return connection
    }
    guard let exchange = connection.authProfile.refreshExchange else {
      return connection
    }
    let mapped = try await executeExchange(connection: connection, exchange: exchange, fields: [:])
    return try registry.markAuthenticationRefreshed(connectionId, values: mapped)
  }

  private func executeExchange(
    connection: AgentMcpConnection,
    exchange: AgentMcpAuthExchangeSpec,
    fields: [String: String]
  ) async throws -> [String: String] {
    do {
      let request = try makeRequest(connection: connection, exchange: exchange, fields: fields)
      let response = try await transport.execute(request)
      return try mappedResponse(response, exchange: exchange)
    } catch {
      let message = error.localizedDescription.nilIfEmpty ?? "MCP sign-in failed"
      _ = try? registry.markFailure(connection.id, message: message, authenticationFailure: true)
      throw error
    }
  }

  private func makeRequest(
    connection: AgentMcpConnection,
    exchange: AgentMcpAuthExchangeSpec,
    fields: [String: String]
  ) throws -> AgentMcpDeclarativeHTTPRequest {
    let url = try resolveURL(connection: connection, pathTemplate: exchange.pathTemplate, fields: fields)
    let secrets = registry.secrets(connection.id)
    var headers = ["Accept": "application/json"]
    for (key, value) in try registry.requestHeaders(connection.id) {
      if let sanitized = sanitizedHeader(name: key, value: value) {
        headers[sanitized.name] = sanitized.value
      }
    }
    for (key, template) in exchange.headerTemplates {
      let value = render(template, fields: fields, secrets: secrets, encodeForPath: false)
      if let sanitized = sanitizedHeader(name: key, value: value) {
        headers[sanitized.name] = sanitized.value
      }
    }
    return AgentMcpDeclarativeHTTPRequest(
      method: exchange.method,
      url: url.absoluteString,
      headers: headers,
      body: Self.bodyMethods.contains(exchange.method) ? renderBody(exchange.bodyTemplate, fields: fields, secrets: secrets) : nil
    )
  }

  private func mappedResponse(
    _ response: AgentMcpDeclarativeHTTPResponse,
    exchange: AgentMcpAuthExchangeSpec
  ) throws -> [String: String] {
    guard exchange.acceptedStatusCodes.contains(response.statusCode) else {
      throw AgentMcpDeclarativeHTTPError(
        statusCode: response.statusCode,
        message: "MCP sign-in returned HTTP \(response.statusCode)",
        authenticationFailure: true
      )
    }
    let responseText = String(response.body.prefix(Self.maxAuthResponseCharacters))
    let parsed = parseResponse(responseText)
    return try exchange.responseMappings.reduce(into: [String: String]()) { result, item in
      let selected = selectJsonPath(item.value, from: parsed)
      let value: String
      if let scalar = selected.stringValue {
        value = scalar
      } else if selected != .null {
        value = AgentMcpJSONCodec.stringify(selected)
      } else {
        value = ""
      }
      let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !clean.isEmpty else {
        throw AgentRuntimeCapabilityError.invalid("MCP sign-in response did not provide \(item.key)")
      }
      result[item.key] = String(clean.prefix(Self.maxMappedSecretCharacters))
    }
  }

  private func resolveURL(
    connection: AgentMcpConnection,
    pathTemplate: String,
    fields: [String: String]
  ) throws -> URL {
    guard let base = URL(string: connection.endpoint) else {
      throw AgentRuntimeCapabilityError.invalid("MCP authentication endpoint is invalid")
    }
    let renderedPath = render(
      pathTemplate,
      fields: fields,
      secrets: registry.secrets(connection.id),
      encodeForPath: true
    )
    guard let target = URL(string: renderedPath, relativeTo: base)?.absoluteURL,
          sameOrigin(base, target) else {
      throw AgentRuntimeCapabilityError.invalid("MCP authentication cannot leave its configured server")
    }
    return target
  }

  private func render(
    _ template: String,
    fields: [String: String],
    secrets: [String: String],
    encodeForPath: Bool
  ) -> String {
    let fieldRendered = replace(Self.fieldPattern, in: template) { key in
      encode(fields[key] ?? "", enabled: encodeForPath)
    }
    return replace(Self.authPattern, in: fieldRendered) { key in
      encode(secrets[key] ?? "", enabled: encodeForPath)
    }
  }

  private func renderBody(_ template: String, fields: [String: String], secrets: [String: String]) -> String {
    guard !template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return AgentMcpJSONCodec.stringify(fields.reduce(into: AgentMcpJSONObject()) { object, item in
        object[item.key] = .string(item.value)
      })
    }
    let fieldRendered = replace(Self.fieldPattern, in: template) { key in
      AgentMcpJSONCodec.stringify(.string(fields[key] ?? ""))
    }
    return replace(Self.authPattern, in: fieldRendered) { key in
      AgentMcpJSONCodec.stringify(.string(secrets[key] ?? ""))
    }
  }

  private func replace(
    _ pattern: NSRegularExpression,
    in template: String,
    replacement: (String) -> String
  ) -> String {
    let source = template as NSString
    var rendered = ""
    var cursor = 0
    for match in pattern.matches(in: template, range: NSRange(location: 0, length: source.length)) {
      rendered += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
      rendered += replacement(source.substring(with: match.range(at: 1)))
      cursor = match.range.location + match.range.length
    }
    rendered += source.substring(from: cursor)
    return rendered
  }

  private func encode(_ value: String, enabled: Bool) -> String {
    guard enabled else {
      return value
    }
    return value.addingPercentEncoding(withAllowedCharacters: Self.pathArgumentAllowedCharacters) ?? ""
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
      return .string("")
    }
    if let data = trimmed.data(using: .utf8),
       let decoded = try? JSONDecoder().decode(AgentMcpJSONValue.self, from: data) {
      return decoded
    }
    return .string(trimmed)
  }

  private func selectJsonPath(_ path: String, from value: AgentMcpJSONValue) -> AgentMcpJSONValue {
    var current = value
    for component in path
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: #"^\$\."#, with: "", options: .regularExpression)
      .split(separator: ".")
      .filter({ !$0.isEmpty })
      .map(String.init) {
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
    return url.scheme?.lowercased() == "https" ? 443 : 80
  }

  private func requireConnection(_ id: String) throws -> AgentMcpConnection {
    guard let connection = registry.get(id) else {
      throw AgentRuntimeCapabilityError.invalid("MCP connection not found: \(id)")
    }
    return connection
  }

  private static let maxAuthResponseCharacters = 256 * 1_024
  private static let maxHeaderValueCharacters = 8_192
  private static let maxMappedSecretCharacters = 8_192
  private static let bodyMethods: Set<String> = ["POST", "PUT", "PATCH"]
  private static let pathArgumentAllowedCharacters = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
  )
  private static let fieldPattern = try! NSRegularExpression(pattern: #"\{\{field\.([A-Za-z0-9_.-]+)\}\}"#)
  private static let authPattern = try! NSRegularExpression(pattern: #"\{\{auth\.([A-Za-z0-9_.-]+)\}\}"#)
}
