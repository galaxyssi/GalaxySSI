import Foundation

struct AgentMcpLocalInvocation: Codable, Equatable {
  var workspaceId: String
  var requestPath: String

  enum CodingKeys: String, CodingKey {
    case workspaceId = "workspace_id"
    case requestPath = "request_path"
  }
}

final class AgentMcpPackageRepository {
  private let packagesRoot: URL
  private let runtimeProjectsRoot: URL
  private let fileManager: FileManager
  private let lock = NSLock()

  init(rootDirectory: URL, fileManager: FileManager = .default) {
    let root = rootDirectory.standardizedFileURL
    self.packagesRoot = root.appendingPathComponent(Self.packagesDirectory, isDirectory: true)
    self.runtimeProjectsRoot = root.appendingPathComponent(Self.runtimeProjectsDirectory, isDirectory: true)
    self.fileManager = fileManager
  }

  static func defaultRoot(fileManager: FileManager = .default) throws -> URL {
    guard let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      throw AgentRuntimeCapabilityError.invalid("MCP package storage is unavailable")
    }
    return root
  }

  func save(_ inspection: AgentMcpPackageInspection) throws {
    try synchronized {
      try persistPackageFiles(inspection)
    }
  }

  func get(_ id: String) -> AgentMcpPackageManifest? {
    synchronized {
      let manifestUrl = packageDirectory(id).appendingPathComponent(AgentMcpPackageInstaller.manifestPath)
      guard let data = try? Data(contentsOf: manifestUrl),
            let raw = String(data: data, encoding: .utf8) else {
        return nil
      }
      return try? AgentMcpPackageManifestCodec.decode(raw)
    }
  }

  func prepareLocalInvocation(id: String, payload: String) throws -> AgentMcpLocalInvocation {
    try synchronized {
      let payloadData = Data(payload.utf8)
      guard payloadData.count <= Self.maxInvocationBytes else {
        throw AgentRuntimeCapabilityError.invalid("Local MCP invocation is too large")
      }
      let sourceRuntime = packageDirectory(id).appendingPathComponent(AgentMcpPackageInstaller.runtimeDirectory, isDirectory: true)
      guard isDirectory(sourceRuntime) else {
        throw AgentRuntimeCapabilityError.invalid("Local MCP runtime files are not installed")
      }
      let workspaceId = localWorkspaceId(id)
      let workspace = runtimeProjectsRoot.appendingPathComponent(workspaceId, isDirectory: true)
      try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
      try replaceDirectory(source: sourceRuntime, target: workspace.appendingPathComponent("runtime", isDirectory: true))
      let control = workspace.appendingPathComponent(Self.controlDirectory, isDirectory: true)
      try fileManager.createDirectory(at: control, withIntermediateDirectories: true)
      for name in (try? fileManager.contentsOfDirectory(atPath: control.path)) ?? [] where name.hasPrefix("request-") {
        try? fileManager.removeItem(at: control.appendingPathComponent(name))
      }
      let requestName = "request-\(UUID().uuidString).json"
      let request = control.appendingPathComponent(requestName, isDirectory: false)
      try payloadData.write(to: request, options: [.atomic])
      return AgentMcpLocalInvocation(workspaceId: workspaceId, requestPath: "\(Self.controlDirectory)/\(requestName)")
    }
  }

  func completeLocalInvocation(_ invocation: AgentMcpLocalInvocation) {
    synchronized {
      guard let workspace = safeChild(runtimeProjectsRoot, invocation.workspaceId),
            let request = safeChild(workspace, invocation.requestPath) else {
        return
      }
      try? fileManager.removeItem(at: request)
    }
  }

  func delete(_ id: String) {
    synchronized {
      try? fileManager.removeItem(at: packageDirectory(id))
      if let workspace = safeChild(runtimeProjectsRoot, localWorkspaceId(id)) {
        try? fileManager.removeItem(at: workspace)
      }
    }
  }

  func clear() {
    synchronized {
      try? fileManager.removeItem(at: packagesRoot)
      guard let names = try? fileManager.contentsOfDirectory(atPath: runtimeProjectsRoot.path) else {
        return
      }
      for name in names where name.hasPrefix(Self.workspacePrefix) {
        try? fileManager.removeItem(at: runtimeProjectsRoot.appendingPathComponent(name, isDirectory: true))
      }
    }
  }

  private func persistPackageFiles(_ inspection: AgentMcpPackageInspection) throws {
    let target = packageDirectory(inspection.manifest.id)
    let parent = target.deletingLastPathComponent()
    try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
    let staging = parent.appendingPathComponent(".\(target.lastPathComponent).\(UUID().uuidString).staging", isDirectory: true)
    let backup = parent.appendingPathComponent(".\(target.lastPathComponent).\(UUID().uuidString).backup", isDirectory: true)
    try? fileManager.removeItem(at: staging)
    try? fileManager.removeItem(at: backup)
    try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
    do {
      try Data(inspection.rawManifest.utf8).write(
        to: staging.appendingPathComponent(AgentMcpPackageInstaller.manifestPath),
        options: [.atomic]
      )
      var totalBytes: Int64 = 0
      for (relative, data) in inspection.runtimeFiles {
        guard relative.hasPrefix(AgentMcpPackageInstaller.runtimeDirectory) else {
          throw AgentRuntimeCapabilityError.invalid("MCP runtime path is invalid")
        }
        guard let nextBytes = checkedAdd(totalBytes, Int64(data.count)),
              nextBytes <= AgentMcpPackageInstaller.maxExtractedBytes else {
          throw AgentRuntimeCapabilityError.invalid("MCP runtime files exceed the package limit")
        }
        totalBytes = nextBytes
        guard let output = safeChild(staging, relative) else {
          throw AgentRuntimeCapabilityError.invalid("MCP runtime path is unsafe")
        }
        try fileManager.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: output, options: [.atomic])
      }
      if fileManager.fileExists(atPath: target.path) {
        try fileManager.moveItem(at: target, to: backup)
      }
      do {
        try fileManager.moveItem(at: staging, to: target)
        try? fileManager.removeItem(at: backup)
      } catch {
        try? fileManager.removeItem(at: target)
        if fileManager.fileExists(atPath: backup.path) {
          try? fileManager.moveItem(at: backup, to: target)
        }
        throw AgentRuntimeCapabilityError.invalid("MCP package could not be committed")
      }
    } catch {
      try? fileManager.removeItem(at: staging)
      if !fileManager.fileExists(atPath: target.path), fileManager.fileExists(atPath: backup.path) {
        try? fileManager.moveItem(at: backup, to: target)
      }
      throw error
    }
  }

  private func replaceDirectory(source: URL, target: URL) throws {
    let parent = target.deletingLastPathComponent()
    try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
    let staging = parent.appendingPathComponent(".\(target.lastPathComponent).\(UUID().uuidString).staging", isDirectory: true)
    try? fileManager.removeItem(at: staging)
    try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
    guard let enumerator = fileManager.enumerator(atPath: source.path) else {
      throw AgentRuntimeCapabilityError.invalid("Local MCP runtime files are not installed")
    }
    do {
      for case let relative as String in enumerator {
        guard !relative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
        let input = source.appendingPathComponent(relative)
        guard let output = safeChild(staging, relative) else {
          throw AgentRuntimeCapabilityError.invalid("Local MCP runtime path is unsafe")
        }
        var isDirectoryValue = ObjCBool(false)
        guard fileManager.fileExists(atPath: input.path, isDirectory: &isDirectoryValue) else {
          continue
        }
        if isDirectoryValue.boolValue {
          try fileManager.createDirectory(at: output, withIntermediateDirectories: true)
        } else {
          let attributes = try fileManager.attributesOfItem(atPath: input.path)
          let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
          guard size <= Int64(AgentMcpPackageInstaller.maxAssetBytes) else {
            throw AgentRuntimeCapabilityError.invalid("Local MCP runtime file is invalid")
          }
          try fileManager.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
          try fileManager.copyItem(at: input, to: output)
        }
      }
      try? fileManager.removeItem(at: target)
      try fileManager.moveItem(at: staging, to: target)
    } catch {
      try? fileManager.removeItem(at: staging)
      throw error
    }
  }

  private func packageDirectory(_ id: String) -> URL {
    packagesRoot.appendingPathComponent(encodedId(id), isDirectory: true)
  }

  private func localWorkspaceId(_ id: String) -> String {
    "\(Self.workspacePrefix)\(AgentMcpPackageInstaller.sha256(Data(id.utf8)).prefix(32))"
  }

  private func encodedId(_ id: String) -> String {
    Data(id.utf8)
      .base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  private func safeChild(_ parent: URL, _ relative: String) -> URL? {
    guard case .success(let segments) = AgentWorkspaceFilePathPolicy.normalizeRelativePath(relative, allowRoot: false) else {
      return nil
    }
    let cleanParent = parent.standardizedFileURL
    var candidate = cleanParent
    for segment in segments {
      candidate.appendPathComponent(segment)
    }
    let cleanCandidate = candidate.standardizedFileURL
    guard cleanCandidate.path.hasPrefix(cleanParent.path + "/") else {
      return nil
    }
    return cleanCandidate
  }

  private func isDirectory(_ url: URL) -> Bool {
    var isDirectoryValue = ObjCBool(false)
    return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectoryValue) && isDirectoryValue.boolValue
  }

  private func checkedAdd(_ left: Int64, _ right: Int64) -> Int64? {
    guard right >= 0, left <= Int64.max - right else {
      return nil
    }
    return left + right
  }

  private func synchronized<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }

  private static let packagesDirectory = "agent-mcp-packages"
  private static let runtimeProjectsDirectory = "agent-native-workspaces"
  private static let controlDirectory = ".galaxyssi-mcp"
  private static let workspacePrefix = "mcp-"
  private static let maxInvocationBytes = 512 * 1_024
}

struct AgentMcpLocalRuntimeExecutionRequest: Codable, Equatable {
  var language: AgentRuntimeLanguage
  var source: String
  var arguments: [String]
  var timeoutMillis: Int64
  var networkEnabled: Bool
  var allowedNetworkDomains: [String]
  var workspaceId: String
  var requestId: String
  var secretEnvironment: [String: String]

  enum CodingKeys: String, CodingKey {
    case language
    case source
    case arguments
    case timeoutMillis = "timeout_ms"
    case networkEnabled = "network_enabled"
    case allowedNetworkDomains = "allowed_network_domains"
    case workspaceId = "workspace_id"
    case requestId = "request_id"
    case secretEnvironment = "secret_environment"
  }
}

struct AgentMcpLocalRuntimeExecutionResponse: Codable, Equatable {
  var stdout: String
  var stderr: String
  var exitCode: Int

  enum CodingKeys: String, CodingKey {
    case stdout
    case stderr
    case exitCode = "exit_code"
  }
}

struct AgentMcpDeclarativeHTTPRequest: Codable, Equatable {
  var method: String
  var url: String
  var headers: [String: String]
  var body: String?

  enum CodingKeys: String, CodingKey {
    case method
    case url
    case headers
    case body
  }
}

struct AgentMcpDeclarativeHTTPResponse: Codable, Equatable {
  var statusCode: Int
  var body: String

  enum CodingKeys: String, CodingKey {
    case statusCode = "status_code"
    case body
  }
}

struct AgentMcpDeclarativeHTTPError: LocalizedError, Equatable {
  var statusCode: Int
  var message: String
  var authenticationFailure: Bool

  var errorDescription: String? { message }
}

protocol AgentMcpLocalRuntimeExecuting {
  func execute(_ request: AgentMcpLocalRuntimeExecutionRequest) throws -> AgentMcpLocalRuntimeExecutionResponse
}

protocol AgentMcpDeclarativeHTTPTransport {
  func execute(_ request: AgentMcpDeclarativeHTTPRequest) async throws -> AgentMcpDeclarativeHTTPResponse
}

struct URLSessionAgentMcpDeclarativeHTTPTransport: AgentMcpDeclarativeHTTPTransport {
  var session: URLSession = .shared

  func execute(_ request: AgentMcpDeclarativeHTTPRequest) async throws -> AgentMcpDeclarativeHTTPResponse {
    guard let url = URL(string: request.url) else {
      throw AgentRuntimeCapabilityError.invalid("Declarative MCP request URL is invalid")
    }
    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = request.method
    request.headers.forEach { key, value in
      urlRequest.setValue(value, forHTTPHeaderField: key)
    }
    if let body = request.body {
      urlRequest.httpBody = Data(body.utf8)
      urlRequest.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
    }
    let (data, response) = try await session.data(for: urlRequest)
    guard let http = response as? HTTPURLResponse else {
      throw AgentRuntimeCapabilityError.invalid("Declarative MCP endpoint returned a non-HTTP response")
    }
    return AgentMcpDeclarativeHTTPResponse(
      statusCode: http.statusCode,
      body: String(data: data, encoding: .utf8) ?? ""
    )
  }
}

struct AgentMcpStreamableHTTPRequest: Codable, Equatable {
  var endpoint: String
  var body: String
  var headers: [String: String]
}

struct AgentMcpStreamableHTTPResponse: Codable, Equatable {
  var statusCode: Int
  var headers: [String: String]
  var body: String

  enum CodingKeys: String, CodingKey {
    case statusCode = "status_code"
    case headers
    case body
  }
}

struct AgentMcpStreamableHTTPError: LocalizedError, Equatable {
  var statusCode: Int
  var message: String
  var authenticationFailure: Bool

  var errorDescription: String? { message }
}

protocol AgentMcpStreamableHTTPNetworking {
  func post(_ request: AgentMcpStreamableHTTPRequest) async throws -> AgentMcpStreamableHTTPResponse
}

struct URLSessionAgentMcpStreamableHTTPNetworking: AgentMcpStreamableHTTPNetworking {
  var session: URLSession = .shared

  func post(_ request: AgentMcpStreamableHTTPRequest) async throws -> AgentMcpStreamableHTTPResponse {
    guard let url = URL(string: request.endpoint) else {
      throw AgentRuntimeCapabilityError.invalid("MCP streamable HTTP endpoint is invalid")
    }
    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = "POST"
    request.headers.forEach { key, value in
      urlRequest.setValue(value, forHTTPHeaderField: key)
    }
    urlRequest.httpBody = Data(request.body.utf8)
    let (data, response) = try await session.data(for: urlRequest)
    guard let http = response as? HTTPURLResponse else {
      throw AgentRuntimeCapabilityError.invalid("MCP streamable HTTP endpoint returned a non-HTTP response")
    }
    return AgentMcpStreamableHTTPResponse(
      statusCode: http.statusCode,
      headers: http.allHeaderFields.reduce(into: [String: String]()) { result, item in
        if let key = item.key as? String {
          result[key] = "\(item.value)"
        }
      },
      body: String(data: data, encoding: .utf8) ?? ""
    )
  }
}

final class AgentMcpStreamableHTTPTransport {
  private let endpoint: String
  private let requestHeaders: [String: String]
  private let networking: AgentMcpStreamableHTTPNetworking
  private let lock = NSRecursiveLock()
  private var incoming: [String] = []
  private var opened = false
  private var closed = false
  private var protocolVersion = ""
  private var sessionId = ""

  var currentSessionId: String {
    synchronized { sessionId }
  }

  init(
    endpoint: String,
    requestHeaders: [String: String] = [:],
    networking: AgentMcpStreamableHTTPNetworking = URLSessionAgentMcpStreamableHTTPNetworking()
  ) throws {
    self.endpoint = try AgentMcpEndpointPolicy.normalize(endpoint)
    self.requestHeaders = requestHeaders
    self.networking = networking
  }

  func open() throws {
    try synchronized {
      guard !closed else {
        throw AgentRuntimeCapabilityError.invalid("MCP transport is closed")
      }
      opened = true
    }
  }

  func send(_ message: String) async throws {
    let request = try synchronized {
      guard opened, !closed else {
        throw AgentRuntimeCapabilityError.invalid("MCP transport is not open")
      }
      return AgentMcpStreamableHTTPRequest(endpoint: endpoint, body: message, headers: requestHeaderSnapshot())
    }
    let response = try await networking.post(request)
    try synchronized {
      if let nextSessionId = header("Mcp-Session-Id", in: response.headers)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .nilIfEmpty {
        sessionId = nextSessionId
      }
      guard (200...299).contains(response.statusCode) else {
        let detail = response.body
          .trimmingCharacters(in: .whitespacesAndNewlines)
          .prefix(Self.maxErrorBodyCharacters)
        throw AgentMcpStreamableHTTPError(
          statusCode: response.statusCode,
          message: "MCP server returned HTTP \(response.statusCode)\(detail.isEmpty ? "" : ": \(detail)")",
          authenticationFailure: [401, 403].contains(response.statusCode)
        )
      }
      let trimmed = response.body.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else {
        return
      }
      let contentType = header("Content-Type", in: response.headers)?.lowercased() ?? ""
      let messages = contentType.contains("text/event-stream") ? parseSse(response.body) : [trimmed]
      incoming.append(contentsOf: messages.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }
  }

  func receive() -> String? {
    synchronized {
      incoming.isEmpty ? nil : incoming.removeFirst()
    }
  }

  func onProtocolVersionNegotiated(_ version: String) {
    synchronized {
      protocolVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }

  func close() {
    synchronized {
      guard !closed else {
        return
      }
      closed = true
      incoming.removeAll()
    }
  }

  func parseSse(_ document: String) -> [String] {
    var messages: [String] = []
    var data: [String] = []
    func flush() {
      if !data.isEmpty {
        messages.append(data.joined(separator: "\n"))
      }
      data.removeAll()
    }
    for raw in document.components(separatedBy: .newlines) {
      let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
      if line.isEmpty {
        flush()
      } else if line.hasPrefix(":") {
        continue
      } else if line.hasPrefix("data:") {
        var value = String(line.dropFirst("data:".count))
        if value.hasPrefix(" ") {
          value.removeFirst()
        }
        data.append(value)
      }
    }
    flush()
    return messages
  }

  private func requestHeaderSnapshot() -> [String: String] {
    var headers = [
      "Accept": "application/json, text/event-stream",
      "Content-Type": "application/json",
      "User-Agent": "GalaxySSI-iOS-MCP/1"
    ]
    for (key, value) in requestHeaders where Self.isSafeHeader(name: key, value: value) {
      headers[key] = value
    }
    if !protocolVersion.isEmpty {
      headers["MCP-Protocol-Version"] = protocolVersion
    }
    if !sessionId.isEmpty {
      headers["Mcp-Session-Id"] = sessionId
    }
    return headers
  }

  private func header(_ name: String, in headers: [String: String]) -> String? {
    headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
  }

  private func synchronized<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }

  private static func isSafeHeader(name: String, value: String) -> Bool {
    name.range(of: #"^[A-Za-z0-9!#$%&'*+.^_`|~-]{1,128}$"#, options: .regularExpression) != nil &&
      value.count <= maxHeaderValueCharacters &&
      !value.contains("\r") &&
      !value.contains("\n") &&
      name.caseInsensitiveCompare("Host") != .orderedSame &&
      name.caseInsensitiveCompare("Content-Length") != .orderedSame
  }

  private static let maxHeaderValueCharacters = 8_192
  private static let maxErrorBodyCharacters = 240
}
