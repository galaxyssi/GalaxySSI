import CryptoKit
import Foundation

enum AgentRuntimeProjectWorkspaceDisposition: String, Codable, CaseIterable, Identifiable {
  case unchanged = "unchanged"
  case committed = "committed"
  case failedCandidate = "failed_candidate"
  case rolledBack = "rolled_back"
  case rollbackFailed = "rollback_failed"

  var id: String { rawValue }
}

struct AgentRuntimeProjectResourceLimits: Codable, Equatable {
  var wallClockMillis: Int64
  var cpuMillis: Int64
  var memoryBytes: Int64
  var diskBytes: Int64
  var maxProcesses: Int
  var maxOutputBytes: Int64
  var maxArtifactBytes: Int64

  init(
    wallClockMillis: Int64 = 60_000,
    cpuMillis: Int64 = 45_000,
    memoryBytes: Int64 = 512 * 1024 * 1024,
    diskBytes: Int64 = 512 * 1024 * 1024,
    maxProcesses: Int = 64,
    maxOutputBytes: Int64 = 512 * 1024,
    maxArtifactBytes: Int64 = 256 * 1024 * 1024
  ) {
    self.wallClockMillis = max(100, wallClockMillis)
    self.cpuMillis = max(100, cpuMillis)
    self.memoryBytes = max(1024 * 1024, memoryBytes)
    self.diskBytes = max(1024 * 1024, diskBytes)
    self.maxProcesses = max(1, maxProcesses)
    self.maxOutputBytes = max(1024, maxOutputBytes)
    self.maxArtifactBytes = max(1024, maxArtifactBytes)
  }

  enum CodingKeys: String, CodingKey {
    case wallClockMillis = "wall_clock_ms"
    case cpuMillis = "cpu_ms"
    case memoryBytes = "memory_bytes"
    case diskBytes = "disk_bytes"
    case maxProcesses = "max_processes"
    case maxOutputBytes = "max_output_bytes"
    case maxArtifactBytes = "max_artifact_bytes"
  }
}

struct AgentRuntimeProjectExecutionRequest: Codable, Equatable {
  var language: AgentRuntimeLanguage
  var source: String
  var arguments: [String]
  var timeoutMillis: Int64
  var networkEnabled: Bool
  var allowedNetworkDomains: [String]
  var artifactPaths: [String]
  var workspaceId: String
  var requestId: String
  var resourceLimits: AgentRuntimeProjectResourceLimits

  init(
    language: AgentRuntimeLanguage,
    source: String,
    arguments: [String] = [],
    timeoutMillis: Int64 = 60_000,
    networkEnabled: Bool = false,
    allowedNetworkDomains: [String] = [],
    artifactPaths: [String] = [],
    workspaceId: String,
    requestId: String,
    resourceLimits: AgentRuntimeProjectResourceLimits = AgentRuntimeProjectResourceLimits()
  ) {
    self.language = language
    self.source = source
    self.arguments = arguments
    self.timeoutMillis = max(100, timeoutMillis)
    self.networkEnabled = networkEnabled
    self.allowedNetworkDomains = Array(Set(allowedNetworkDomains.map { $0.lowercased() })).sorted()
    self.artifactPaths = artifactPaths
    self.workspaceId = workspaceId
    self.requestId = requestId
    self.resourceLimits = resourceLimits
  }

  enum CodingKeys: String, CodingKey {
    case language
    case source
    case arguments
    case timeoutMillis = "timeout_ms"
    case networkEnabled = "network_enabled"
    case allowedNetworkDomains = "allowed_network_domains"
    case artifactPaths = "artifact_paths"
    case workspaceId = "workspace_id"
    case requestId = "request_id"
    case resourceLimits = "resource_limits"
  }
}

struct AgentRuntimeProjectSnapshot: Codable, Equatable {
  var workspaceId: String
  var fileCount: Int
  var totalBytes: Int64
  var byteLimit: Int64

  init(workspaceId: String, fileCount: Int = 0, totalBytes: Int64 = 0, byteLimit: Int64 = 0) {
    self.workspaceId = workspaceId
    self.fileCount = max(0, fileCount)
    self.totalBytes = max(0, totalBytes)
    self.byteLimit = max(0, byteLimit)
  }

  enum CodingKeys: String, CodingKey {
    case workspaceId = "workspace_id"
    case fileCount = "workspace_file_count"
    case totalBytes = "workspace_bytes"
    case byteLimit = "byte_limit"
  }

  func publicValue() -> AgentMcpJSONObject {
    [
      "workspace_id": .string(workspaceId),
      "workspace_file_count": .int(Int64(fileCount)),
      "workspace_bytes": .int(totalBytes),
      "byte_limit": .int(byteLimit)
    ]
  }
}

struct AgentRuntimeProjectCheckpoint: Codable, Equatable, Identifiable {
  var workspaceId: String
  var checkpointId: String
  var fileCount: Int
  var totalBytes: Int64
  var createdAtMillis: Int64

  var id: String { checkpointId }

  enum CodingKeys: String, CodingKey {
    case workspaceId = "workspace_id"
    case checkpointId = "checkpoint_id"
    case fileCount = "file_count"
    case totalBytes = "total_bytes"
    case createdAtMillis = "created_at_millis"
  }

  func publicValue() -> AgentMcpJSONObject {
    [
      "workspace_id": .string(workspaceId),
      "checkpoint_id": .string(checkpointId),
      "file_count": .int(Int64(fileCount)),
      "total_bytes": .int(totalBytes),
      "created_at_millis": .int(createdAtMillis)
    ]
  }
}

struct AgentRuntimeProjectStatus: Codable, Equatable {
  var workspaceId: String
  var fileCount: Int
  var totalBytes: Int64
  var checkpoints: [AgentRuntimeProjectCheckpoint]

  enum CodingKeys: String, CodingKey {
    case workspaceId = "workspace_id"
    case fileCount = "workspace_file_count"
    case totalBytes = "workspace_bytes"
    case checkpoints
  }

  func publicValue() -> AgentMcpJSONObject {
    [
      "workspace_id": .string(workspaceId),
      "workspace_file_count": .int(Int64(fileCount)),
      "workspace_bytes": .int(totalBytes),
      "checkpoints": .array(checkpoints.map { .object($0.publicValue()) })
    ]
  }
}

struct AgentRuntimePreparedProject: Equatable {
  var request: AgentRuntimeProjectExecutionRequest
  var directory: URL
  var sourceFile: URL
  var importedProjectBytes: Int64
}

struct AgentRuntimeProjectCommitResult: Equatable {
  var checkpoint: AgentRuntimeProjectCheckpoint
  var project: AgentRuntimeProjectSnapshot

  func publicValue(
    disposition: AgentRuntimeProjectWorkspaceDisposition = .committed
  ) -> AgentMcpJSONObject {
    [
      "workspace_disposition": .string(disposition.rawValue),
      "checkpoint": .object(checkpoint.publicValue()),
      "project": .object(project.publicValue())
    ]
  }
}

struct AgentRuntimeProjectArtifact: Equatable {
  var relativePath: String
  var artifactKind: String
  var fileCount: Int
  var sizeBytes: Int64
  var sha256: String
  var hostURL: URL

  func publicValue(includeHostPath: Bool = false) -> AgentMcpJSONObject {
    var value: AgentMcpJSONObject = [
      "relative_path": .string(relativePath),
      "artifact_kind": .string(artifactKind),
      "file_count": .int(Int64(fileCount)),
      "size_bytes": .int(sizeBytes),
      "sha256": .string(sha256)
    ]
    if includeHostPath {
      value["host_path"] = .string(hostURL.path)
    }
    return value
  }
}

struct AgentRuntimeProjectWorkspaceError: LocalizedError, Equatable {
  var code: AgentWorkspaceFileErrorCode
  var message: String

  var errorDescription: String? { message }

  static func invalid(_ message: String) -> AgentRuntimeProjectWorkspaceError {
    AgentRuntimeProjectWorkspaceError(code: .invalidPath, message: message)
  }

  static func quota(_ message: String) -> AgentRuntimeProjectWorkspaceError {
    AgentRuntimeProjectWorkspaceError(code: .limitExceeded, message: message)
  }
}

final class AgentRuntimeProjectWorkspaceManager {
  private let runtimeRoot: URL
  private let projectRoot: URL
  private let checkpointRoot: URL
  private let artifactRoot: URL
  private let fileManager: FileManager
  private let nowMillis: () -> Int64

  init(
    runtimeRoot: URL,
    projectRoot: URL,
    checkpointRoot: URL? = nil,
    artifactRoot: URL? = nil,
    fileManager: FileManager = .default,
    nowMillis: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
  ) {
    self.runtimeRoot = runtimeRoot
    self.projectRoot = projectRoot
    self.checkpointRoot = checkpointRoot ?? projectRoot.appendingPathComponent(".galaxyssi-checkpoints", isDirectory: true)
    self.artifactRoot = artifactRoot ?? runtimeRoot.appendingPathComponent("artifacts", isDirectory: true)
    self.fileManager = fileManager
    self.nowMillis = nowMillis
  }

  func prepare(_ request: AgentRuntimeProjectExecutionRequest) throws -> AgentRuntimePreparedProject {
    let workspace = try workspaceDirectoryName(request.workspaceId)
    let requestDirectory = runtimeRoot.appendingPathComponent(safeDirectoryName("run", request.requestId), isDirectory: true)
    try replaceDirectory(requestDirectory)
    let imported = try copyContents(
      from: projectDirectory(workspace),
      to: requestDirectory,
      byteLimit: request.resourceLimits.diskBytes,
      excludingPrivateRuntimeFiles: false
    )
    let sourceFile = requestDirectory.appendingPathComponent(sourceFileName(for: request.language), isDirectory: false)
    try fileManager.createDirectory(
      at: sourceFile.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data(request.source.utf8).write(to: sourceFile, options: [.atomic])
    try writeRequestManifest(request, under: requestDirectory)
    return AgentRuntimePreparedProject(
      request: request,
      directory: requestDirectory,
      sourceFile: sourceFile,
      importedProjectBytes: imported.totalBytes
    )
  }

  func syncProject(_ prepared: AgentRuntimePreparedProject, byteLimit: Int64) throws -> AgentRuntimeProjectSnapshot {
    let workspace = try workspaceDirectoryName(prepared.request.workspaceId)
    let target = projectDirectory(workspace)
    let staging = projectRoot.appendingPathComponent(".staging-\(safeDirectoryName("sync", prepared.request.requestId))", isDirectory: true)
    try replaceDirectory(staging)
    do {
      let snapshot = try copyContents(
        from: prepared.directory,
        to: staging,
        byteLimit: byteLimit,
        excludingPrivateRuntimeFiles: true
      )
      try replaceItem(at: target, with: staging)
      return AgentRuntimeProjectSnapshot(
        workspaceId: workspace,
        fileCount: snapshot.fileCount,
        totalBytes: snapshot.totalBytes,
        byteLimit: byteLimit
      )
    } catch {
      try? fileManager.removeItem(at: staging)
      throw error
    }
  }

  func checkpoint(workspaceId: String, checkpointId: String, byteLimit: Int64) throws -> AgentRuntimeProjectCheckpoint {
    let workspace = try workspaceDirectoryName(workspaceId)
    let checkpoint = try checkpointDirectoryName(checkpointId)
    let source = projectDirectory(workspace)
    let destination = checkpointDirectory(workspaceId: workspace, checkpointId: checkpoint)
    try replaceDirectory(destination)
    let snapshot = try copyContents(
      from: source,
      to: destination,
      byteLimit: byteLimit,
      excludingPrivateRuntimeFiles: false
    )
    return AgentRuntimeProjectCheckpoint(
      workspaceId: workspace,
      checkpointId: checkpoint,
      fileCount: snapshot.fileCount,
      totalBytes: snapshot.totalBytes,
      createdAtMillis: nowMillis()
    )
  }

  func rollback(workspaceId: String, checkpointId: String, byteLimit: Int64) throws -> AgentRuntimeProjectSnapshot {
    let workspace = try workspaceDirectoryName(workspaceId)
    let checkpoint = try checkpointDirectoryName(checkpointId)
    let source = checkpointDirectory(workspaceId: workspace, checkpointId: checkpoint)
    guard directoryExists(source) else {
      throw AgentRuntimeProjectWorkspaceError.invalid("Checkpoint does not exist in this workspace")
    }
    let staging = projectRoot.appendingPathComponent(".rollback-\(safeDirectoryName("checkpoint", checkpoint))", isDirectory: true)
    try replaceDirectory(staging)
    do {
      let snapshot = try copyContents(
        from: source,
        to: staging,
        byteLimit: byteLimit,
        excludingPrivateRuntimeFiles: false
      )
      try replaceItem(at: projectDirectory(workspace), with: staging)
      return AgentRuntimeProjectSnapshot(
        workspaceId: workspace,
        fileCount: snapshot.fileCount,
        totalBytes: snapshot.totalBytes,
        byteLimit: byteLimit
      )
    } catch {
      try? fileManager.removeItem(at: staging)
      throw error
    }
  }

  func commitProject(
    prepared: AgentRuntimePreparedProject,
    byteLimit: Int64,
    checkpointId: String
  ) throws -> AgentRuntimeProjectCommitResult {
    let checkpoint = try self.checkpoint(
      workspaceId: prepared.request.workspaceId,
      checkpointId: checkpointId,
      byteLimit: byteLimit
    )
    let project = try syncProject(prepared, byteLimit: byteLimit)
    return AgentRuntimeProjectCommitResult(checkpoint: checkpoint, project: project)
  }

  func workspaceStatus(_ workspaceId: String) throws -> AgentRuntimeProjectStatus {
    let workspace = try workspaceDirectoryName(workspaceId)
    let projectSnapshot = try summarizeDirectory(projectDirectory(workspace), byteLimit: Int64.max)
    return AgentRuntimeProjectStatus(
      workspaceId: workspace,
      fileCount: projectSnapshot.fileCount,
      totalBytes: projectSnapshot.totalBytes,
      checkpoints: checkpointSummaries(workspaceId: workspace)
    )
  }

  func collectArtifacts(
    prepared: AgentRuntimePreparedProject,
    request: AgentRuntimeProjectExecutionRequest
  ) throws -> [AgentRuntimeProjectArtifact] {
    let paths = request.artifactPaths.map(AgentWorkspaceFilePathPolicy.displayPath).filter { !$0.isEmpty }
    guard !paths.isEmpty else { return [] }
    let sources = try paths.map { path -> (path: String, url: URL, directory: Bool) in
      let url = try childURL(path, under: prepared.directory, allowRoot: false)
      guard fileManager.fileExists(atPath: url.path) else {
        throw AgentRuntimeProjectWorkspaceError.invalid("Artifact path does not exist: \(path)")
      }
      return (path, url, directoryExists(url))
    }
    if sources.count == 1, !sources[0].directory {
      return [try collectFileArtifact(sources[0].url, relativePath: sources[0].path, requestId: request.requestId)]
    }
    return [try collectArchiveArtifact(sources, requestId: request.requestId)]
  }

  private func collectFileArtifact(
    _ source: URL,
    relativePath: String,
    requestId: String
  ) throws -> AgentRuntimeProjectArtifact {
    let data = try Data(contentsOf: source)
    let destination = artifactRoot
      .appendingPathComponent(safeDirectoryName("request", requestId), isDirectory: true)
      .appendingPathComponent(relativePath, isDirectory: false)
    try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: destination, options: [.atomic])
    return AgentRuntimeProjectArtifact(
      relativePath: relativePath,
      artifactKind: "file",
      fileCount: 1,
      sizeBytes: Int64(data.count),
      sha256: sha256(data),
      hostURL: destination
    )
  }

  private func collectArchiveArtifact(
    _ sources: [(path: String, url: URL, directory: Bool)],
    requestId: String
  ) throws -> AgentRuntimeProjectArtifact {
    let entries = try archiveEntries(sources)
    let archiveData = AgentRuntimeProjectArchiveBuilder.buildStoredZip(entries: entries)
    let destination = artifactRoot
      .appendingPathComponent(safeDirectoryName("request", requestId), isDirectory: true)
      .appendingPathComponent("project.zip", isDirectory: false)
    try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try archiveData.write(to: destination, options: [.atomic])
    return AgentRuntimeProjectArtifact(
      relativePath: "project.zip",
      artifactKind: "project_archive",
      fileCount: entries.count,
      sizeBytes: Int64(archiveData.count),
      sha256: sha256(archiveData),
      hostURL: destination
    )
  }

  private func archiveEntries(
    _ sources: [(path: String, url: URL, directory: Bool)]
  ) throws -> [AgentRuntimeProjectArchiveEntry] {
    var entries: [AgentRuntimeProjectArchiveEntry] = []
    for source in sources {
      if source.directory {
        for file in try regularFiles(under: source.url) {
          let child = try relativePath(from: source.url, to: file)
          let entryPath = [source.path, child].filter { !$0.isEmpty }.joined(separator: "/")
          entries.append(AgentRuntimeProjectArchiveEntry(path: entryPath, data: try Data(contentsOf: file)))
        }
      } else {
        entries.append(AgentRuntimeProjectArchiveEntry(path: source.path, data: try Data(contentsOf: source.url)))
      }
    }
    return entries.sorted { $0.path < $1.path }
  }

  private func checkpointSummaries(workspaceId: String) -> [AgentRuntimeProjectCheckpoint] {
    let root = checkpointRoot.appendingPathComponent(workspaceId, isDirectory: true)
    guard let children = try? fileManager.contentsOfDirectory(
      at: root,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ) else {
      return []
    }
    return children
      .filter(directoryExists)
      .compactMap { url -> AgentRuntimeProjectCheckpoint? in
        guard let summary = try? summarizeDirectory(url, byteLimit: Int64.max) else { return nil }
        return AgentRuntimeProjectCheckpoint(
          workspaceId: workspaceId,
          checkpointId: url.lastPathComponent,
          fileCount: summary.fileCount,
          totalBytes: summary.totalBytes,
          createdAtMillis: modifiedMillis(url)
        )
      }
      .sorted { $0.checkpointId < $1.checkpointId }
  }

  private func copyContents(
    from source: URL,
    to destination: URL,
    byteLimit: Int64,
    excludingPrivateRuntimeFiles: Bool
  ) throws -> AgentRuntimeProjectSnapshot {
    try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
    guard directoryExists(source) else {
      return AgentRuntimeProjectSnapshot(workspaceId: destination.lastPathComponent, byteLimit: byteLimit)
    }
    var fileCount = 0
    var totalBytes: Int64 = 0
    for file in try regularFilesAndDirectories(under: source) {
      let relative = try relativePath(from: source, to: file)
      if excludingPrivateRuntimeFiles && isPrivateRuntimePath(relative) {
        continue
      }
      let target = destination.appendingPathComponent(relative, isDirectory: directoryExists(file))
      if directoryExists(file) {
        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        continue
      }
      let data = try Data(contentsOf: file)
      totalBytes += Int64(data.count)
      guard totalBytes <= byteLimit else {
        throw AgentRuntimeProjectWorkspaceError.quota("Runtime project exceeds byte limit")
      }
      try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: target, options: [.atomic])
      fileCount += 1
    }
    return AgentRuntimeProjectSnapshot(
      workspaceId: destination.lastPathComponent,
      fileCount: fileCount,
      totalBytes: totalBytes,
      byteLimit: byteLimit
    )
  }

  private func summarizeDirectory(_ directory: URL, byteLimit: Int64) throws -> AgentRuntimeProjectSnapshot {
    guard directoryExists(directory) else {
      return AgentRuntimeProjectSnapshot(workspaceId: directory.lastPathComponent, byteLimit: byteLimit)
    }
    var fileCount = 0
    var totalBytes: Int64 = 0
    for file in try regularFiles(under: directory) {
      let dataSize = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      totalBytes += Int64(dataSize)
      guard totalBytes <= byteLimit else {
        throw AgentRuntimeProjectWorkspaceError.quota("Runtime project exceeds byte limit")
      }
      fileCount += 1
    }
    return AgentRuntimeProjectSnapshot(
      workspaceId: directory.lastPathComponent,
      fileCount: fileCount,
      totalBytes: totalBytes,
      byteLimit: byteLimit
    )
  }

  private func regularFiles(under directory: URL) throws -> [URL] {
    try regularFilesAndDirectories(under: directory).filter { !directoryExists($0) }
  }

  private func regularFilesAndDirectories(under directory: URL) throws -> [URL] {
    guard directoryExists(directory) else { return [] }
    guard let enumerator = fileManager.enumerator(
      at: directory,
      includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
      options: []
    ) else {
      return []
    }
    var values: [URL] = []
    for case let url as URL in enumerator {
      let resource = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
      if resource.isSymbolicLink == true {
        enumerator.skipDescendants()
        throw AgentRuntimeProjectWorkspaceError.invalid("Symlinks are not allowed in runtime projects")
      }
      if resource.isDirectory == true || resource.isRegularFile == true {
        values.append(url)
      }
    }
    return values.sorted { $0.path < $1.path }
  }

  private func writeRequestManifest(_ request: AgentRuntimeProjectExecutionRequest, under directory: URL) throws {
    let manifest = try JSONEncoder().encode(request)
    try manifest.write(to: directory.appendingPathComponent("request.json", isDirectory: false), options: [.atomic])
  }

  private func replaceDirectory(_ url: URL) throws {
    try? fileManager.removeItem(at: url)
    try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
  }

  private func replaceItem(at target: URL, with source: URL) throws {
    try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? fileManager.removeItem(at: target)
    try fileManager.moveItem(at: source, to: target)
  }

  private func projectDirectory(_ workspaceId: String) -> URL {
    projectRoot.appendingPathComponent(workspaceId, isDirectory: true)
  }

  private func checkpointDirectory(workspaceId: String, checkpointId: String) -> URL {
    checkpointRoot
      .appendingPathComponent(workspaceId, isDirectory: true)
      .appendingPathComponent(checkpointId, isDirectory: true)
  }

  private func childURL(_ path: String, under root: URL, allowRoot: Bool) throws -> URL {
    let segments = try normalizedSegments(path, allowRoot: allowRoot)
    return segments.reduce(root) { partial, segment in
      partial.appendingPathComponent(segment, isDirectory: false)
    }
  }

  private func normalizedSegments(_ path: String, allowRoot: Bool) throws -> [String] {
    switch AgentWorkspaceFilePathPolicy.normalizeRelativePath(path, allowRoot: allowRoot) {
    case .success(let segments):
      return segments
    case .failure(let error):
      throw AgentRuntimeProjectWorkspaceError(code: error.code, message: error.message)
    }
  }

  private func workspaceDirectoryName(_ value: String) throws -> String {
    switch AgentWorkspaceFilePathPolicy.workspaceDirectoryName(value) {
    case .success(let workspace):
      return workspace
    case .failure(let error):
      throw AgentRuntimeProjectWorkspaceError(code: error.code, message: error.message)
    }
  }

  private func checkpointDirectoryName(_ value: String) throws -> String {
    try workspaceDirectoryName(value)
  }

  private func relativePath(from base: URL, to child: URL) throws -> String {
    let basePath = base.standardizedFileURL.path
    let childPath = child.standardizedFileURL.path
    guard childPath == basePath || childPath.hasPrefix(basePath + "/") else {
      throw AgentRuntimeProjectWorkspaceError.invalid("Runtime project path escaped its root")
    }
    var relative = String(childPath.dropFirst(basePath.count))
    while relative.hasPrefix("/") {
      relative.removeFirst()
    }
    return AgentWorkspaceFilePathPolicy.displayPath(relative)
  }

  private func sourceFileName(for language: AgentRuntimeLanguage) -> String {
    switch language {
    case .shell:
      return "main.sh"
    case .python, .uv:
      return "main.py"
    case .javascript:
      return "main.js"
    case .typescript:
      return "main.ts"
    case .go:
      return "main.go"
    case .rust:
      return "main.rs"
    case .c:
      return "main.c"
    case .cpp:
      return "main.cpp"
    case .java:
      return "Main.java"
    case .browser:
      return "main.browser.json"
    case .ffmpeg, .ffprobe:
      return "media-task.json"
    }
  }

  private func safeDirectoryName(_ prefix: String, _ value: String) -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if case .success = AgentWorkspaceFilePathPolicy.workspaceDirectoryName(normalized) {
      return normalized
    }
    return "\(prefix)-\(sha256(Data(value.utf8)).prefix(32))"
  }

  private func isPrivateRuntimePath(_ path: String) -> Bool {
    let components = path.split(separator: "/").map(String.init)
    return components.contains { $0.hasPrefix(".galaxyssi-") } ||
      components.contains("request.json") ||
      components.first == ".galaxyssi"
  }

  private func directoryExists(_ url: URL) -> Bool {
    var isDirectory = ObjCBool(false)
    return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
  }

  private func modifiedMillis(_ url: URL) -> Int64 {
    let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    return Int64((modified ?? Date()).timeIntervalSince1970 * 1000)
  }

  private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

struct AgentRuntimeProjectArchiveEntry: Equatable {
  var path: String
  var data: Data
}

enum AgentRuntimeProjectArchiveBuilder {
  static func buildStoredZip(entries: [AgentRuntimeProjectArchiveEntry]) -> Data {
    var output = Data()
    var centralDirectory = Data()
    var offset: UInt32 = 0
    for entry in entries {
      let name = AgentWorkspaceFilePathPolicy.displayPath(entry.path)
      let nameBytes = Data(name.utf8)
      let crc = crc32(entry.data)
      appendUInt32(0x04034b50, to: &output)
      appendUInt16(20, to: &output)
      appendUInt16(0, to: &output)
      appendUInt16(0, to: &output)
      appendUInt16(0, to: &output)
      appendUInt16(0, to: &output)
      appendUInt32(crc, to: &output)
      appendUInt32(UInt32(entry.data.count), to: &output)
      appendUInt32(UInt32(entry.data.count), to: &output)
      appendUInt16(UInt16(nameBytes.count), to: &output)
      appendUInt16(0, to: &output)
      output.append(nameBytes)
      output.append(entry.data)

      appendUInt32(0x02014b50, to: &centralDirectory)
      appendUInt16(20, to: &centralDirectory)
      appendUInt16(20, to: &centralDirectory)
      appendUInt16(0, to: &centralDirectory)
      appendUInt16(0, to: &centralDirectory)
      appendUInt16(0, to: &centralDirectory)
      appendUInt16(0, to: &centralDirectory)
      appendUInt32(crc, to: &centralDirectory)
      appendUInt32(UInt32(entry.data.count), to: &centralDirectory)
      appendUInt32(UInt32(entry.data.count), to: &centralDirectory)
      appendUInt16(UInt16(nameBytes.count), to: &centralDirectory)
      appendUInt16(0, to: &centralDirectory)
      appendUInt16(0, to: &centralDirectory)
      appendUInt16(0, to: &centralDirectory)
      appendUInt16(0, to: &centralDirectory)
      appendUInt32(0, to: &centralDirectory)
      appendUInt32(offset, to: &centralDirectory)
      centralDirectory.append(nameBytes)
      offset = UInt32(output.count)
    }
    let centralOffset = UInt32(output.count)
    output.append(centralDirectory)
    appendUInt32(0x06054b50, to: &output)
    appendUInt16(0, to: &output)
    appendUInt16(0, to: &output)
    appendUInt16(UInt16(entries.count), to: &output)
    appendUInt16(UInt16(entries.count), to: &output)
    appendUInt32(UInt32(centralDirectory.count), to: &output)
    appendUInt32(centralOffset, to: &output)
    appendUInt16(0, to: &output)
    return output
  }

  private static func appendUInt16(_ value: UInt16, to data: inout Data) {
    data.append(UInt8(value & 0xff))
    data.append(UInt8((value >> 8) & 0xff))
  }

  private static func appendUInt32(_ value: UInt32, to data: inout Data) {
    data.append(UInt8(value & 0xff))
    data.append(UInt8((value >> 8) & 0xff))
    data.append(UInt8((value >> 16) & 0xff))
    data.append(UInt8((value >> 24) & 0xff))
  }

  private static func crc32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xffffffff
    for byte in data {
      let index = Int((crc ^ UInt32(byte)) & 0xff)
      crc = (crc >> 8) ^ crc32Table[index]
    }
    return crc ^ 0xffffffff
  }

  private static let crc32Table: [UInt32] = {
    (0..<256).map { value -> UInt32 in
      var crc = UInt32(value)
      for _ in 0..<8 {
        if crc & 1 == 1 {
          crc = (crc >> 1) ^ 0xedb88320
        } else {
          crc >>= 1
        }
      }
      return crc
    }
  }()
}
