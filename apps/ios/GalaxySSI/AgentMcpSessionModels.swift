import CryptoKit
import Foundation

enum AgentMcpRemoteSessionState: String, Codable, CaseIterable, Identifiable {
  case new
  case connecting
  case initializing
  case active
  case closing
  case closed
  case failed

  var id: String { rawValue }
}

enum AgentMcpRemoteSessionErrorKind: String, Codable, CaseIterable, Identifiable {
  case invalidState = "invalid_state"
  case malformedJSON = "malformed_json"
  case invalidJSONRPC = "invalid_json_rpc"
  case versionNegotiation = "version_negotiation"
  case capabilityNotNegotiated = "capability_not_negotiated"
  case remote
  case invalidResult = "invalid_result"
  case resourceLimit = "resource_limit"

  var id: String { rawValue }
}

struct AgentMcpRemoteSessionError: LocalizedError, Equatable {
  var kind: AgentMcpRemoteSessionErrorKind
  var message: String
  var requestId: Int64?
  var method: String?
  var rpcCode: Int64?
  var data: AgentMcpJSONValue?

  var errorDescription: String? { message }
}

struct AgentMcpRemoteSessionConfig: Codable, Equatable {
  static let protocolVersion2025_11_25 = "2025-11-25"
  static let protocolVersion2025_06_18 = "2025-06-18"
  static let protocolVersion2025_03_26 = "2025-03-26"
  static let protocolVersion2024_11_05 = "2024-11-05"

  var requestedProtocolVersion: String
  var supportedProtocolVersions: Set<String>
  var maxMessagesPerRequest: Int

  init(
    requestedProtocolVersion: String = AgentMcpRemoteSessionConfig.protocolVersion2025_11_25,
    supportedProtocolVersions: Set<String> = [
      AgentMcpRemoteSessionConfig.protocolVersion2025_11_25,
      AgentMcpRemoteSessionConfig.protocolVersion2025_06_18,
      AgentMcpRemoteSessionConfig.protocolVersion2025_03_26,
      AgentMcpRemoteSessionConfig.protocolVersion2024_11_05
    ],
    maxMessagesPerRequest: Int = 128
  ) {
    self.requestedProtocolVersion = requestedProtocolVersion
    self.supportedProtocolVersions = supportedProtocolVersions
    self.maxMessagesPerRequest = max(1, maxMessagesPerRequest)
  }
}

struct AgentMcpImplementationInfo: Codable, Equatable {
  var name: String
  var version: String
  var title: String?
  var description: String?
  var websiteUrl: String?

  func toJSONObject() -> AgentMcpJSONObject {
    var object: AgentMcpJSONObject = [
      "name": .string(name),
      "version": .string(version)
    ]
    if let title {
      object["title"] = .string(title)
    }
    if let description {
      object["description"] = .string(description)
    }
    if let websiteUrl {
      object["websiteUrl"] = .string(websiteUrl)
    }
    return object
  }
}

struct AgentMcpServerCapabilities: Codable, Equatable {
  var raw: AgentMcpJSONObject

  func has(_ name: String) -> Bool {
    raw[name]?.objectValue != nil
  }

  var tools: Bool { has("tools") }
  var resources: Bool { has("resources") }
  var prompts: Bool { has("prompts") }
}

struct AgentMcpInitializeResult: Codable, Equatable {
  var requestId: Int64
  var protocolVersion: String
  var serverInfo: AgentMcpImplementationInfo
  var capabilities: AgentMcpServerCapabilities
  var instructions: String?
  var raw: AgentMcpJSONObject
}

struct AgentMcpPage<Element: Equatable>: Equatable {
  var requestId: Int64
  var items: [Element]
  var nextCursor: String?
  var raw: AgentMcpJSONObject
}

struct AgentMcpResource: Codable, Equatable {
  var uri: String
  var name: String
  var title: String?
  var description: String?
  var mimeType: String?
  var size: Int64?
  var annotations: AgentMcpJSONObject?
  var raw: AgentMcpJSONObject
}

struct AgentMcpResourceContent: Codable, Equatable {
  var uri: String
  var mimeType: String?
  var text: String?
  var blob: String?
  var annotations: AgentMcpJSONObject?
  var raw: AgentMcpJSONObject
}

struct AgentMcpResourceReadResult: Codable, Equatable {
  var requestId: Int64
  var contents: [AgentMcpResourceContent]
  var raw: AgentMcpJSONObject
}

struct AgentMcpPromptArgument: Codable, Equatable {
  var name: String
  var title: String?
  var description: String?
  var required: Bool
  var raw: AgentMcpJSONObject
}

struct AgentMcpPrompt: Codable, Equatable {
  var name: String
  var title: String?
  var description: String?
  var arguments: [AgentMcpPromptArgument]
  var raw: AgentMcpJSONObject
}

struct AgentMcpContent: Codable, Equatable {
  var type: String
  var text: String?
  var data: String?
  var mimeType: String?
  var uri: String?
  var name: String?
  var resource: AgentMcpResourceContent?
  var raw: AgentMcpJSONObject
}

struct AgentMcpToolCallResult: Codable, Equatable {
  var requestId: Int64
  var content: [AgentMcpContent]
  var structuredContent: AgentMcpJSONObject?
  var isError: Bool
  var raw: AgentMcpJSONObject
}

struct AgentMcpPromptMessage: Codable, Equatable {
  var role: String
  var content: AgentMcpContent
  var raw: AgentMcpJSONObject
}

struct AgentMcpPromptGetResult: Codable, Equatable {
  var requestId: Int64
  var description: String?
  var messages: [AgentMcpPromptMessage]
  var raw: AgentMcpJSONObject
}

struct AgentMcpNotification: Codable, Equatable {
  var method: String
  var params: AgentMcpJSONObject?
  var raw: AgentMcpJSONObject
}

protocol AgentMcpRemoteSessionListener {
  func onNotification(_ notification: AgentMcpNotification)
  func onProtocolIssue(_ error: AgentMcpRemoteSessionError)
}

extension AgentMcpRemoteSessionListener {
  func onNotification(_ notification: AgentMcpNotification) {}
  func onProtocolIssue(_ error: AgentMcpRemoteSessionError) {}
}

final class NoopAgentMcpRemoteSessionListener: AgentMcpRemoteSessionListener {}

final class AgentMcpRemoteSession {
  private let transport: AgentMcpStreamableHTTPTransport
  private let config: AgentMcpRemoteSessionConfig
  private let listener: AgentMcpRemoteSessionListener
  private let lock = NSRecursiveLock()
  private var nextRequestId: Int64 = 1
  private(set) var state: AgentMcpRemoteSessionState = .new
  private(set) var initialization: AgentMcpInitializeResult?

  init(
    transport: AgentMcpStreamableHTTPTransport,
    config: AgentMcpRemoteSessionConfig = AgentMcpRemoteSessionConfig(),
    listener: AgentMcpRemoteSessionListener = NoopAgentMcpRemoteSessionListener()
  ) {
    self.transport = transport
    self.config = config
    self.listener = listener
  }

  func initialize(
    clientInfo: AgentMcpImplementationInfo,
    clientCapabilities: AgentMcpJSONObject = [:]
  ) async throws -> AgentMcpInitializeResult {
    try synchronized {
      guard state == .new else {
        throw sessionError(.invalidState, "MCP session cannot initialize from \(state.rawValue)", method: "initialize")
      }
      state = .connecting
    }
    do {
      try transport.open()
      synchronized { state = .initializing }
      let response = try await requestInternal(
        method: "initialize",
        params: [
          "protocolVersion": .string(config.requestedProtocolVersion),
          "capabilities": .object(clientCapabilities),
          "clientInfo": .object(clientInfo.toJSONObject())
        ],
        allowInitializing: true
      )
      let parsed = try parseInitializeResult(response)
      guard config.supportedProtocolVersions.contains(parsed.protocolVersion) else {
        throw sessionError(
          .versionNegotiation,
          "Server selected unsupported MCP version \(parsed.protocolVersion)",
          requestId: response.requestId,
          method: "initialize"
        )
      }
      transport.onProtocolVersionNegotiated(parsed.protocolVersion)
      try await sendNotification("notifications/initialized")
      try synchronized {
        guard state == .initializing else {
          throw sessionError(.invalidState, "MCP session closed during initialization", method: "initialize")
        }
        initialization = parsed
        state = .active
      }
      return parsed
    } catch {
      synchronized { state = .failed }
      transport.close()
      throw error
    }
  }

  func listTools(cursor: String? = nil) async throws -> AgentMcpPage<AgentMcpTool> {
    try requireCapability("tools", method: "tools/list")
    let params = try cursorParams(cursor, method: "tools/list")
    let response = try await request(method: "tools/list", params: params)
    let result = try resultObject(response, method: "tools/list")
    let tools = try requiredArray(result, "tools", method: "tools/list").enumerated().map { index, value in
      try parseTool(try requiredObject(value, "tools[\(index)]", method: "tools/list"))
    }
    return AgentMcpPage(
      requestId: response.requestId,
      items: tools,
      nextCursor: result["nextCursor"]?.stringValue?.nilIfEmpty,
      raw: result
    )
  }

  func callTool(name: String, arguments: AgentMcpJSONObject = [:]) async throws -> AgentMcpToolCallResult {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw sessionError(.invalidResult, "Tool name must not be blank", method: "tools/call")
    }
    try requireCapability("tools", method: "tools/call")
    let response = try await request(
      method: "tools/call",
      params: [
        "name": .string(name),
        "arguments": .object(arguments)
      ]
    )
    let result = try resultObject(response, method: "tools/call")
    let content = try requiredArray(result, "content", method: "tools/call").enumerated().map { index, value in
      try parseContent(
        try requiredObject(value, "content[\(index)]", method: "tools/call"),
        context: "content[\(index)]",
        method: "tools/call"
      )
    }
    let structured: AgentMcpJSONObject?
    if let value = result["structuredContent"] {
      guard let object = value.objectValue else {
        throw sessionError(.invalidResult, "tools/call structuredContent must be an object", requestId: response.requestId, method: "tools/call")
      }
      structured = object
    } else {
      structured = nil
    }
    return AgentMcpToolCallResult(
      requestId: response.requestId,
      content: content,
      structuredContent: structured,
      isError: result["isError"]?.boolValue ?? false,
      raw: result
    )
  }

  func listResources(cursor: String? = nil) async throws -> AgentMcpPage<AgentMcpResource> {
    try requireCapability("resources", method: "resources/list")
    let params = try cursorParams(cursor, method: "resources/list")
    let response = try await request(method: "resources/list", params: params)
    let result = try resultObject(response, method: "resources/list")
    let resources = try requiredArray(result, "resources", method: "resources/list").enumerated().map { index, value in
      try parseResource(try requiredObject(value, "resources[\(index)]", method: "resources/list"))
    }
    return AgentMcpPage(
      requestId: response.requestId,
      items: resources,
      nextCursor: result["nextCursor"]?.stringValue?.nilIfEmpty,
      raw: result
    )
  }

  func readResource(uri: String) async throws -> AgentMcpResourceReadResult {
    guard !uri.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw sessionError(.invalidResult, "Resource URI must not be blank", method: "resources/read")
    }
    try requireCapability("resources", method: "resources/read")
    let response = try await request(method: "resources/read", params: ["uri": .string(uri)])
    let result = try resultObject(response, method: "resources/read")
    let contents = try requiredArray(result, "contents", method: "resources/read").enumerated().map { index, value in
      try parseResourceContent(
        try requiredObject(value, "contents[\(index)]", method: "resources/read"),
        context: "contents[\(index)]",
        method: "resources/read"
      )
    }
    return AgentMcpResourceReadResult(requestId: response.requestId, contents: contents, raw: result)
  }

  func listPrompts(cursor: String? = nil) async throws -> AgentMcpPage<AgentMcpPrompt> {
    try requireCapability("prompts", method: "prompts/list")
    let params = try cursorParams(cursor, method: "prompts/list")
    let response = try await request(method: "prompts/list", params: params)
    let result = try resultObject(response, method: "prompts/list")
    let prompts = try requiredArray(result, "prompts", method: "prompts/list").enumerated().map { index, value in
      try parsePrompt(try requiredObject(value, "prompts[\(index)]", method: "prompts/list"))
    }
    return AgentMcpPage(
      requestId: response.requestId,
      items: prompts,
      nextCursor: result["nextCursor"]?.stringValue?.nilIfEmpty,
      raw: result
    )
  }

  func getPrompt(name: String, arguments: [String: String] = [:]) async throws -> AgentMcpPromptGetResult {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw sessionError(.invalidResult, "Prompt name must not be blank", method: "prompts/get")
    }
    try requireCapability("prompts", method: "prompts/get")
    let response = try await request(
      method: "prompts/get",
      params: [
        "name": .string(name),
        "arguments": .object(arguments.mapValues { .string($0) })
      ]
    )
    let result = try resultObject(response, method: "prompts/get")
    let messages = try requiredArray(result, "messages", method: "prompts/get").enumerated().map { index, value in
      let raw = try requiredObject(value, "messages[\(index)]", method: "prompts/get")
      let role = try requiredString(raw, "role", requestId: response.requestId, method: "prompts/get")
      guard role == "user" || role == "assistant" else {
        throw sessionError(.invalidResult, "messages[\(index)].role must be user or assistant", requestId: response.requestId, method: "prompts/get")
      }
      return AgentMcpPromptMessage(
        role: role,
        content: try parseContent(
          try requiredObject(raw["content"], "messages[\(index)].content", method: "prompts/get"),
          context: "messages[\(index)].content",
          method: "prompts/get"
        ),
        raw: raw
      )
    }
    return AgentMcpPromptGetResult(
      requestId: response.requestId,
      description: result["description"]?.stringValue,
      messages: messages,
      raw: result
    )
  }

  func close() {
    synchronized {
      guard state != .closed else {
        return
      }
      state = .closing
      transport.close()
      state = .closed
    }
  }

  private func request(method: String, params: AgentMcpJSONObject = [:]) async throws -> AgentMcpRpcEnvelope {
    try await requestInternal(method: method, params: params, allowInitializing: false)
  }

  private func requestInternal(
    method: String,
    params: AgentMcpJSONObject,
    allowInitializing: Bool
  ) async throws -> AgentMcpRpcEnvelope {
    let requestId = try synchronized { () -> Int64 in
      let allowed = state == .active || (allowInitializing && state == .initializing)
      guard allowed else {
        throw sessionError(.invalidState, "MCP session is not active", method: method)
      }
      let id = nextRequestId
      nextRequestId += 1
      return id
    }
    var payload: AgentMcpJSONObject = [
      "jsonrpc": .string("2.0"),
      "id": .int(requestId),
      "method": .string(method)
    ]
    if !params.isEmpty {
      payload["params"] = .object(params)
    }
    try await transport.send(AgentMcpJSONCodec.stringify(payload))
    return try await receiveResponse(requestId: requestId, method: method)
  }

  private func sendNotification(_ method: String, params: AgentMcpJSONObject = [:]) async throws {
    var payload: AgentMcpJSONObject = [
      "jsonrpc": .string("2.0"),
      "method": .string(method)
    ]
    if !params.isEmpty {
      payload["params"] = .object(params)
    }
    try await transport.send(AgentMcpJSONCodec.stringify(payload))
  }

  private func receiveResponse(requestId: Int64, method: String) async throws -> AgentMcpRpcEnvelope {
    for _ in 0..<config.maxMessagesPerRequest {
      guard let message = transport.receive() else {
        break
      }
      guard let envelope = try await parseEnvelope(message, method: method) else {
        continue
      }
      guard envelope.requestId == requestId else {
        listener.onProtocolIssue(
          sessionError(
            .invalidJSONRPC,
            "Response references an unknown request ID",
            requestId: envelope.requestId
          )
        )
        continue
      }
      if let error = envelope.error {
        guard case .some(.int(let code)) = error["code"] else {
          throw sessionError(.invalidJSONRPC, "JSON-RPC error code must be an integer", requestId: requestId, method: method)
        }
        guard let message = error["message"]?.stringValue?.nilIfEmpty else {
          throw sessionError(.invalidJSONRPC, "JSON-RPC error message must be a non-empty string", requestId: requestId, method: method)
        }
        throw sessionError(
          .remote,
          message,
          requestId: requestId,
          method: method,
          rpcCode: code,
          data: error["data"]
        )
      }
      guard envelope.result != nil else {
        throw sessionError(.invalidJSONRPC, "MCP response is missing result", requestId: requestId, method: method)
      }
      return envelope
    }
    throw sessionError(.resourceLimit, "MCP response was not received", requestId: requestId, method: method)
  }

  private func parseEnvelope(_ message: String, method: String) async throws -> AgentMcpRpcEnvelope? {
    guard let data = message.data(using: .utf8),
          let object = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: data) else {
      throw sessionError(.malformedJSON, "MCP message is not valid JSON", method: method)
    }
    guard object["jsonrpc"]?.stringValue == "2.0" else {
      throw sessionError(.invalidJSONRPC, "MCP message is not JSON-RPC 2.0", method: method)
    }
    if let methodValue = object["method"] {
      guard let incomingMethod = methodValue.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
        throw sessionError(.invalidJSONRPC, "JSON-RPC method must be a non-empty string", method: method)
      }
      guard object["result"] == nil, object["error"] == nil else {
        throw sessionError(.invalidJSONRPC, "JSON-RPC request or notification cannot contain result or error", method: incomingMethod)
      }
      let params: AgentMcpJSONObject?
      if let paramsValue = object["params"] {
        guard let paramsObject = paramsValue.objectValue else {
          throw sessionError(.invalidJSONRPC, "JSON-RPC params must be an object", method: incomingMethod)
        }
        params = paramsObject
      } else {
        params = nil
      }
      guard let rawId = object["id"] else {
        listener.onNotification(AgentMcpNotification(method: incomingMethod, params: params, raw: object))
        return nil
      }
      let requestId = try incomingRequestId(rawId, method: incomingMethod)
      try await respondToServerRequest(id: requestId, method: incomingMethod)
      return nil
    }
    guard let rawResponseId = object["id"] else {
      throw sessionError(.invalidJSONRPC, "JSON-RPC response is missing id", method: method)
    }
    guard let id = responseId(rawResponseId) else {
      listener.onProtocolIssue(
        sessionError(.invalidJSONRPC, "Response references an unknown request ID", method: method)
      )
      return nil
    }
    let hasResult = object["result"] != nil
    let hasError = object["error"] != nil
    guard hasResult != hasError else {
      throw sessionError(.invalidJSONRPC, "JSON-RPC response must contain exactly one of result or error", requestId: id, method: method)
    }
    if hasError, object["error"]?.objectValue == nil {
      throw sessionError(.invalidJSONRPC, "JSON-RPC error must be an object", requestId: id, method: method)
    }
    return AgentMcpRpcEnvelope(
      requestId: id,
      result: object["result"],
      error: object["error"]?.objectValue,
      raw: object
    )
  }

  private func respondToServerRequest(id: AgentMcpJSONValue, method: String) async throws {
    let response: AgentMcpJSONObject
    if method == "ping" {
      response = [
        "jsonrpc": .string("2.0"),
        "id": id,
        "result": .object([:])
      ]
    } else {
      response = [
        "jsonrpc": .string("2.0"),
        "id": id,
        "error": .object([
          "code": .int(-32601),
          "message": .string("Method not found: \(method)")
        ])
      ]
    }
    try await transport.send(AgentMcpJSONCodec.stringify(response))
  }

  private func incomingRequestId(_ value: AgentMcpJSONValue, method: String) throws -> AgentMcpJSONValue {
    switch value {
    case .int:
      return value
    case .string(let raw) where !raw.isEmpty:
      return value
    default:
      throw sessionError(.invalidJSONRPC, "JSON-RPC id must be a string or integer", method: method)
    }
  }

  private func responseId(_ value: AgentMcpJSONValue?) -> Int64? {
    guard case .int(let id) = value else {
      return nil
    }
    return id
  }

  private func parseInitializeResult(_ response: AgentMcpRpcEnvelope) throws -> AgentMcpInitializeResult {
    let result = try resultObject(response, method: "initialize")
    let protocolVersion = try requiredString(result, "protocolVersion", requestId: response.requestId, method: "initialize")
    let serverInfoJson = try requiredObject(result["serverInfo"], "serverInfo", method: "initialize")
    let serverInfo = AgentMcpImplementationInfo(
      name: try requiredString(serverInfoJson, "name", requestId: response.requestId, method: "initialize"),
      version: try requiredString(serverInfoJson, "version", requestId: response.requestId, method: "initialize"),
      title: serverInfoJson["title"]?.stringValue,
      description: serverInfoJson["description"]?.stringValue,
      websiteUrl: serverInfoJson["websiteUrl"]?.stringValue
    )
    let capabilitiesJson = try requiredObject(result["capabilities"], "capabilities", method: "initialize")
    for (name, value) in capabilitiesJson where value.objectValue == nil {
      throw sessionError(.invalidResult, "Server capability \(name) must be an object", requestId: response.requestId, method: "initialize")
    }
    return AgentMcpInitializeResult(
      requestId: response.requestId,
      protocolVersion: protocolVersion,
      serverInfo: serverInfo,
      capabilities: AgentMcpServerCapabilities(raw: capabilitiesJson),
      instructions: result["instructions"]?.stringValue,
      raw: result
    )
  }

  private func parseTool(_ raw: AgentMcpJSONObject) throws -> AgentMcpTool {
    AgentMcpTool(
      name: try requiredString(raw, "name", method: "tools/list"),
      title: raw["title"]?.stringValue,
      description: raw["description"]?.stringValue,
      inputSchema: try requiredObject(raw["inputSchema"], "tool.inputSchema", method: "tools/list"),
      outputSchema: try optionalObject(raw, "outputSchema", method: "tools/list"),
      annotations: try optionalObject(raw, "annotations", method: "tools/list"),
      raw: raw
    )
  }

  private func parseContent(_ raw: AgentMcpJSONObject, context: String, method: String) throws -> AgentMcpContent {
    let type = try requiredString(raw, "type", method: method)
    let text = raw["text"]?.stringValue
    let data = raw["data"]?.stringValue
    let mimeType = raw["mimeType"]?.stringValue
    var resource: AgentMcpResourceContent?
    switch type {
    case "text":
      guard text != nil else {
        throw sessionError(.invalidResult, "\(context).text is required for text content", method: method)
      }
    case "image", "audio":
      guard data != nil, mimeType != nil else {
        throw sessionError(.invalidResult, "\(context) requires data and mimeType for \(type) content", method: method)
      }
    case "resource":
      resource = try parseResourceContent(
        try requiredObject(raw["resource"], "\(context).resource", method: method),
        context: "\(context).resource",
        method: method
      )
    case "resource_link":
      _ = try requiredString(raw, "uri", method: method)
      _ = try requiredString(raw, "name", method: method)
    default:
      break
    }
    return AgentMcpContent(
      type: type,
      text: raw["text"]?.stringValue,
      data: raw["data"]?.stringValue,
      mimeType: raw["mimeType"]?.stringValue,
      uri: raw["uri"]?.stringValue,
      name: raw["name"]?.stringValue,
      resource: resource,
      raw: raw
    )
  }

  private func parseResource(_ raw: AgentMcpJSONObject) throws -> AgentMcpResource {
    let size: Int64?
    if let value = raw["size"] {
      guard let parsed = value.intValue, parsed >= 0 else {
        throw sessionError(.invalidResult, "resource.size must be a non-negative integer", method: "resources/list")
      }
      size = parsed
    } else {
      size = nil
    }
    return AgentMcpResource(
      uri: try requiredString(raw, "uri", method: "resources/list"),
      name: try requiredString(raw, "name", method: "resources/list"),
      title: raw["title"]?.stringValue,
      description: raw["description"]?.stringValue,
      mimeType: raw["mimeType"]?.stringValue,
      size: size,
      annotations: try optionalObject(raw, "annotations", method: "resources/list"),
      raw: raw
    )
  }

  private func parseResourceContent(
    _ raw: AgentMcpJSONObject,
    context: String,
    method: String
  ) throws -> AgentMcpResourceContent {
    let text = raw["text"]?.stringValue
    let blob = raw["blob"]?.stringValue
    guard (text == nil) != (blob == nil) else {
      throw sessionError(.invalidResult, "\(context) must contain exactly one of text or blob", method: method)
    }
    return AgentMcpResourceContent(
      uri: try requiredString(raw, "uri", method: method),
      mimeType: raw["mimeType"]?.stringValue,
      text: text,
      blob: blob,
      annotations: try optionalObject(raw, "annotations", method: method),
      raw: raw
    )
  }

  private func parsePrompt(_ raw: AgentMcpJSONObject) throws -> AgentMcpPrompt {
    let arguments: [AgentMcpPromptArgument]
    if let value = raw["arguments"] {
      guard let array = value.arrayValue else {
        throw sessionError(.invalidResult, "prompt.arguments must be an array", method: "prompts/list")
      }
      arguments = try array.enumerated().map { index, value in
        let item = try requiredObject(value, "prompt.arguments[\(index)]", method: "prompts/list")
        return AgentMcpPromptArgument(
          name: try requiredString(item, "name", method: "prompts/list"),
          title: item["title"]?.stringValue,
          description: item["description"]?.stringValue,
          required: try optionalBoolean(item, "required", defaultValue: false, method: "prompts/list"),
          raw: item
        )
      }
    } else {
      arguments = []
    }
    return AgentMcpPrompt(
      name: try requiredString(raw, "name", method: "prompts/list"),
      title: raw["title"]?.stringValue,
      description: raw["description"]?.stringValue,
      arguments: arguments,
      raw: raw
    )
  }

  private func resultObject(_ response: AgentMcpRpcEnvelope, method: String) throws -> AgentMcpJSONObject {
    guard let object = response.result?.objectValue else {
      throw sessionError(.invalidResult, "\(method) result must be an object", requestId: response.requestId, method: method)
    }
    return object
  }

  private func requiredObject(_ value: AgentMcpJSONValue?, _ label: String, method: String) throws -> AgentMcpJSONObject {
    guard let object = value?.objectValue else {
      throw sessionError(.invalidResult, "\(label) must be an object", method: method)
    }
    return object
  }

  private func requiredArray(_ object: AgentMcpJSONObject, _ key: String, method: String) throws -> [AgentMcpJSONValue] {
    guard let array = object[key]?.arrayValue else {
      throw sessionError(.invalidResult, "\(key) must be an array", method: method)
    }
    return array
  }

  private func optionalObject(_ object: AgentMcpJSONObject, _ key: String, method: String) throws -> AgentMcpJSONObject? {
    guard let value = object[key] else {
      return nil
    }
    guard let raw = value.objectValue else {
      throw sessionError(.invalidResult, "\(key) must be an object", method: method)
    }
    return raw
  }

  private func optionalBoolean(
    _ object: AgentMcpJSONObject,
    _ key: String,
    defaultValue: Bool,
    method: String
  ) throws -> Bool {
    guard let value = object[key] else {
      return defaultValue
    }
    guard let raw = value.boolValue else {
      throw sessionError(.invalidResult, "\(key) must be a boolean", method: method)
    }
    return raw
  }

  private func requiredString(
    _ object: AgentMcpJSONObject,
    _ key: String,
    requestId: Int64? = nil,
    method: String
  ) throws -> String {
    guard let value = object[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
      throw sessionError(.invalidResult, "\(key) must be a non-empty string", requestId: requestId, method: method)
    }
    return value
  }

  private func cursorParams(_ cursor: String?, method: String) throws -> AgentMcpJSONObject {
    guard let cursor else {
      return [:]
    }
    let cleanCursor = cursor.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanCursor.isEmpty else {
      throw sessionError(.invalidResult, "Cursor must not be blank", method: method)
    }
    return ["cursor": .string(cursor)]
  }

  private func requireCapability(_ capability: String, method: String) throws {
    try synchronized {
      guard state == .active else {
        throw sessionError(.invalidState, "MCP session is not active", method: method)
      }
      guard initialization?.capabilities.has(capability) == true else {
        throw sessionError(.capabilityNotNegotiated, "MCP server did not negotiate \(capability)", method: method)
      }
    }
  }

  private func sessionError(
    _ kind: AgentMcpRemoteSessionErrorKind,
    _ message: String,
    requestId: Int64? = nil,
    method: String? = nil,
    rpcCode: Int64? = nil,
    data: AgentMcpJSONValue? = nil
  ) -> AgentMcpRemoteSessionError {
    AgentMcpRemoteSessionError(
      kind: kind,
      message: message,
      requestId: requestId,
      method: method,
      rpcCode: rpcCode,
      data: data
    )
  }

  private func synchronized<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }

  private struct AgentMcpRpcEnvelope {
    var requestId: Int64
    var result: AgentMcpJSONValue?
    var error: AgentMcpJSONObject?
    var raw: AgentMcpJSONObject
  }
}
