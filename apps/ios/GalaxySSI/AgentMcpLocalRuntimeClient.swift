import Foundation

final class AgentMcpLocalRuntimeClient {
  private let registry: AgentMcpRegistry
  private let packageRepository: AgentMcpPackageRepository
  private let executor: AgentMcpLocalRuntimeExecuting
  private let nowMillis: () -> Int64
  private let lock = NSLock()

  init(
    registry: AgentMcpRegistry,
    packageRepository: AgentMcpPackageRepository,
    executor: AgentMcpLocalRuntimeExecuting,
    nowMillis: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }
  ) {
    self.registry = registry
    self.packageRepository = packageRepository
    self.executor = executor
    self.nowMillis = nowMillis
  }

  func listTools(connection: AgentMcpConnection) throws -> [AgentMcpTool] {
    let response = try invoke(connection: connection, operation: "list_tools", toolName: "", arguments: [:])
    guard let rawTools = response["tools"]?.arrayValue else {
      throw AgentRuntimeCapabilityError.invalid("Local MCP server returned no tool list")
    }
    guard rawTools.count <= Self.maxTools else {
      throw AgentRuntimeCapabilityError.invalid("Local MCP server returned too many tools")
    }
    return try rawTools.map { value in
      guard let raw = value.objectValue else {
        throw AgentRuntimeCapabilityError.invalid("Local MCP server returned an invalid tool")
      }
      let name = (raw["name"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !name.isEmpty else {
        throw AgentRuntimeCapabilityError.invalid("Local MCP tool name is missing")
      }
      return AgentMcpTool(
        name: name,
        title: raw["title"]?.stringValue,
        description: raw["description"]?.stringValue,
        inputSchema: raw["inputSchema"]?.objectValue ?? raw["input_schema"]?.objectValue ?? [:],
        outputSchema: raw["outputSchema"]?.objectValue ?? raw["output_schema"]?.objectValue,
        annotations: raw["annotations"]?.objectValue,
        raw: raw
      )
    }
  }

  func callTool(
    connection: AgentMcpConnection,
    toolName: String,
    arguments: AgentMcpJSONObject
  ) throws -> AgentNativeToolExecutionResult {
    let response = try invoke(connection: connection, operation: "call_tool", toolName: toolName, arguments: arguments)
    let content = (response["content"]?.arrayValue ?? []).compactMap(\.objectValue)
    let message = content
      .compactMap { $0["text"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
      .joined(separator: "\n")
      .nilIfEmpty ?? "MCP tool completed"
    if response["isError"]?.boolValue == true || response["is_error"]?.boolValue == true {
      return AgentNativeToolExecutionResult.failure(
        code: "mcp_tool_error",
        message: message,
        details: [
          "connection_id": .string(connection.id),
          "tool_name": .string(toolName)
        ]
      )
    }
    var output: AgentMcpJSONObject = [
      "connection_id": .string(connection.id),
      "tool_name": .string(toolName),
      "content": .array(content.map { .object($0) })
    ]
    if let structured = response["structuredContent"]?.objectValue ?? response["structured_content"]?.objectValue {
      output["structured_content"] = .object(structured)
    }
    return AgentNativeToolExecutionResult.success(
      output: output,
      message: message,
      metadata: [
        "transport": .string(AgentMcpTransportKind.localStdio.rawValue),
        "server": .string(connection.displayName)
      ]
    )
  }

  private func invoke(
    connection: AgentMcpConnection,
    operation: String,
    toolName: String,
    arguments: AgentMcpJSONObject
  ) throws -> AgentMcpJSONObject {
    try synchronized {
      guard connection.transport == .localStdio else {
        throw AgentRuntimeCapabilityError.invalid("MCP connection is not a local stdio server")
      }
      guard connection.isCallable(nowMillis: nowMillis()) else {
        throw AgentRuntimeCapabilityError.invalid("MCP connection requires authentication or setup")
      }
      guard let manifest = packageRepository.get(connection.id) else {
        throw AgentRuntimeCapabilityError.invalid("Local MCP package metadata is missing")
      }
      guard let runtime = manifest.localRuntime else {
        throw AgentRuntimeCapabilityError.invalid("Local MCP runtime configuration is missing")
      }
      let payload = AgentMcpJSONCodec.stringify([
        "operation": .string(operation),
        "entrypoint": .string(runtime.entrypoint),
        "runtime": .string(runtime.language.rawValue),
        "server_arguments": .array(runtime.arguments.map(AgentMcpJSONValue.string)),
        "tool_name": .string(toolName),
        "arguments": .object(arguments),
        "timeout_ms": .int(runtime.timeoutMillis)
      ])
      let invocation = try packageRepository.prepareLocalInvocation(id: connection.id, payload: payload)
      defer { packageRepository.completeLocalInvocation(invocation) }
      let execution = try executor.execute(AgentMcpLocalRuntimeExecutionRequest(
        language: .python,
        source: Self.bridgeSource,
        arguments: [invocation.requestPath],
        timeoutMillis: runtime.timeoutMillis,
        networkEnabled: !runtime.allowedNetworkDomains.isEmpty,
        allowedNetworkDomains: runtime.allowedNetworkDomains,
        workspaceId: invocation.workspaceId,
        requestId: UUID().uuidString,
        secretEnvironment: renderEnvironment(runtime.environment, secrets: registry.secrets(connection.id))
      ))
      let decoded = try AgentMcpLocalRuntimeResponseCodec.decode(execution.stdout)
      if execution.exitCode != 0 {
        let reason = execution.stderr
          .trimmingCharacters(in: .whitespacesAndNewlines)
          .prefix(Self.maxErrorCharacters)
        throw AgentRuntimeCapabilityError.invalid(reason.isEmpty ? "Local MCP bridge exited with \(execution.exitCode)" : String(reason))
      }
      return decoded
    }
  }

  private func renderEnvironment(_ templates: [String: String], secrets: [String: String]) -> [String: String] {
    templates.mapValues { renderAuthTemplate($0, secrets: secrets) }
  }

  private func renderAuthTemplate(_ template: String, secrets: [String: String]) -> String {
    let source = template as NSString
    var rendered = ""
    var cursor = 0
    for match in Self.authPattern.matches(in: template, range: NSRange(location: 0, length: source.length)) {
      rendered += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
      let key = source.substring(with: match.range(at: 1))
      rendered += secrets[key] ?? ""
      cursor = match.range.location + match.range.length
    }
    rendered += source.substring(from: cursor)
    return rendered
  }

  private func synchronized<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }

  private static let maxTools = 128
  private static let maxErrorCharacters = 4_096
  private static let authPattern = try! NSRegularExpression(pattern: #"\{\{auth\.([A-Za-z0-9_.-]+)\}\}"#)
  private static let bridgeSource = #"""
  import json
  import os
  import sys

  PREFIX = "__GALAXYSSI_MCP_RESULT__"

  def emit(value):
      print(PREFIX + json.dumps(value, ensure_ascii=False, separators=(",", ":")), flush=True)

  def fail(message):
      emit({"ok": False, "error": str(message)[:4096]})
      raise SystemExit(1)

  if len(sys.argv) != 2:
      fail("Local MCP invocation path is missing")

  os.environ["GALAXYSSI_MCP_SANDBOX"] = "1"
  fail("Local MCP bridge execution is provided by the iOS runtime host")
  """#
}
