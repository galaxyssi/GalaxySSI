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
      name: "signalasi-ios",
      version: "1.0.0",
      title: "SignalASI iOS"
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
