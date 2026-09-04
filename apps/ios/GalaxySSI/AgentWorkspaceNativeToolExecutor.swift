import CryptoKit
import Foundation

final class AgentWorkspaceNativeToolExecutor {
  private static let maxBatchFiles = 64
  private static let maxBatchWriteBytes: Int64 = 1_024 * 1_024

  private struct Entry: Equatable {
    var type: AgentWorkspaceEntryType
    var data: Data
    var modifiedAtMillis: Int64
  }

  private struct ZipSourceEntry: Equatable {
    var path: String
    var directory: Bool
    var data: Data
    var modifiedAtMillis: Int64
  }

  private struct TextBatchFile: Equatable {
    var path: String
    var data: Data
  }

  private struct ZipArchiveEntry: Equatable {
    var path: String
    var directory: Bool
    var method: UInt16
    var compressedBytes: Int64
    var uncompressedBytes: Int64
    var compressionRatio: Double
    var crc32: UInt32
    var lastModifiedMillis: Int64
    var dataOffset: Int
    var dataLength: Int
  }

  private struct ZipInspection: Equatable {
    var archivePath: String
    var archiveBytes: Int64
    var totalCompressedBytes: Int64
    var totalUncompressedBytes: Int64
    var entries: [ZipArchiveEntry]
  }

  private var workspaces: [String: [String: Entry]] = [:]
  private let policy: AgentWorkspaceFilePolicy
  private let nowMillis: () -> Int64
  private let stateStore: AgentWorkspaceNativeToolStateStore?

  init(
    policy: AgentWorkspaceFilePolicy = AgentWorkspaceFilePolicy(),
    nowMillis: @escaping () -> Int64 = {
      Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    },
    stateStore: AgentWorkspaceNativeToolStateStore? = nil
  ) {
    self.policy = policy
    self.nowMillis = nowMillis
    self.stateStore = stateStore
    self.workspaces = Self.restoreWorkspaces(stateStore?.load() ?? [:])
  }

  func executableDefinition(_ definition: AgentPhoneNativeToolDefinition) -> AgentNativeToolExecutableDefinition {
    AgentNativeToolExecutableDefinition(
      definition: definition,
      executor: { invocation in
        try invocation.checkpoint()
        let result = self.execute(toolId: invocation.descriptor.id, input: invocation.input)
        try invocation.checkpoint()
        return result
      }
    )
  }

  private func execute(toolId: String, input: AgentMcpJSONObject) -> AgentNativeToolExecutionResult {
    switch run(toolId: toolId, input: input) {
    case .success(let output):
      return .success(output: output)
    case .failure(let error):
      return AgentNativeToolExecutionResult.failure(
        code: "workspace_file_error",
        message: error.message,
        details: ["workspace_error": .object(errorObject(error))]
      )
    }
  }

  private func run(toolId: String, input: AgentMcpJSONObject) -> AgentWorkspaceFileResult<AgentMcpJSONObject> {
    let workspaceId = canonicalWorkspaceId(string(input, "workspace_id")) ?? string(input, "workspace_id")
    switch toolId {
    case AgentPhoneNativeToolCatalog.workspaceInitialize:
      return initialize(workspaceId)
    case AgentPhoneNativeToolCatalog.workspaceMkdir:
      return mkdir(workspaceId, string(input, "path"), recursive: bool(input, "recursive", true))
    case AgentPhoneNativeToolCatalog.workspaceList:
      return list(
        workspaceId,
        string(input, "path", ""),
        recursive: bool(input, "recursive", false),
        maxEntries: int(input, "max_entries", policy.maxListEntries)
      )
    case AgentPhoneNativeToolCatalog.workspaceStat:
      return stat(workspaceId, string(input, "path"))
    case AgentPhoneNativeToolCatalog.workspaceReadText:
      return readText(workspaceId, string(input, "path"), maxBytes: int64(input, "max_bytes", policy.maxTextReadBytes))
    case AgentPhoneNativeToolCatalog.workspaceReadBytes:
      return readBytes(workspaceId, string(input, "path"), maxBytes: int64(input, "max_bytes", policy.maxBytesReadBytes))
    case AgentPhoneNativeToolCatalog.workspaceWriteText:
      return writeData(
        workspaceId,
        string(input, "path"),
        Data(string(input, "text").utf8),
        kind: .write,
        overwrite: true,
        createParents: bool(input, "create_parents", false)
      )
    case AgentPhoneNativeToolCatalog.workspaceWriteTextBatch:
      return writeTextBatch(
        workspaceId,
        files: textBatchFiles(input, "files"),
        overwrite: bool(input, "overwrite", true)
      )
    case AgentPhoneNativeToolCatalog.workspaceCreateText:
      return writeData(
        workspaceId,
        string(input, "path"),
        Data(string(input, "text").utf8),
        kind: .create,
        overwrite: false,
        createParents: bool(input, "create_parents", false)
      )
    case AgentPhoneNativeToolCatalog.workspaceAppendText:
      return appendData(workspaceId, string(input, "path"), Data(string(input, "text").utf8))
    case AgentPhoneNativeToolCatalog.workspaceWriteBytes:
      return writeData(
        workspaceId,
        string(input, "path"),
        decodedBase64(input),
        kind: .write,
        overwrite: true,
        createParents: bool(input, "create_parents", false)
      )
    case AgentPhoneNativeToolCatalog.workspaceCreateBytes:
      return writeData(
        workspaceId,
        string(input, "path"),
        decodedBase64(input),
        kind: .create,
        overwrite: false,
        createParents: bool(input, "create_parents", false)
      )
    case AgentPhoneNativeToolCatalog.workspaceAppendBytes:
      return appendData(workspaceId, string(input, "path"), decodedBase64(input))
    case AgentPhoneNativeToolCatalog.workspaceMove:
      return moveOrCopy(
        workspaceId,
        sourcePath: string(input, "source_path"),
        destinationPath: string(input, "destination_path"),
        kind: .move,
        overwrite: bool(input, "overwrite", false),
        createParents: bool(input, "create_parents", false)
      )
    case AgentPhoneNativeToolCatalog.workspaceCopy:
      return moveOrCopy(
        workspaceId,
        sourcePath: string(input, "source_path"),
        destinationPath: string(input, "destination_path"),
        kind: .copy,
        overwrite: bool(input, "overwrite", false),
        createParents: bool(input, "create_parents", false)
      )
    case AgentPhoneNativeToolCatalog.workspaceDelete:
      return delete(workspaceId, string(input, "path"), recursive: bool(input, "recursive", false))
    case AgentPhoneNativeToolCatalog.workspaceSearchText:
      return searchText(
        workspaceId,
        string(input, "path"),
        query: string(input, "query"),
        caseSensitive: bool(input, "case_sensitive", false),
        maxResults: int(input, "max_results", policy.maxSearchResults)
      )
    case AgentPhoneNativeToolCatalog.workspaceApplyExactPatch:
      return applyExactPatch(
        workspaceId,
        string(input, "path"),
        expected: string(input, "expected_text"),
        replacement: string(input, "replacement_text"),
        expectedOccurrences: int(input, "expected_occurrences", 1)
      )
    case AgentPhoneNativeToolCatalog.workspaceDiffSummary:
      return diffSummary(workspaceId, string(input, "path"), proposedText: string(input, "proposed_text"))
    case AgentPhoneNativeToolCatalog.workspaceSha256:
      return sha256(workspaceId, string(input, "path"))
    case AgentPhoneNativeToolCatalog.workspaceZipCreate:
      return createZip(
        workspaceId,
        archivePath: string(input, "archive_path"),
        sourcePaths: stringList(input, "source_paths"),
        overwrite: bool(input, "overwrite", false),
        createParents: bool(input, "create_parents", false)
      )
    case AgentPhoneNativeToolCatalog.workspaceZipList:
      return listZip(workspaceId, archivePath: string(input, "archive_path"))
    case AgentPhoneNativeToolCatalog.workspaceZipExtract:
      return extractZip(
        workspaceId,
        archivePath: string(input, "archive_path"),
        destinationPath: string(input, "destination_path"),
        overwrite: bool(input, "overwrite", false)
      )
    default:
      return failure(.unsupportedFileType, "execute", toolId, "Workspace tool is not implemented on iOS yet")
    }
  }

  private func initialize(_ workspaceId: String) -> AgentWorkspaceFileResult<AgentMcpJSONObject> {
    guard case .success(let cleanId) = AgentWorkspaceFilePathPolicy.workspaceDirectoryName(workspaceId) else {
      return failure(.invalidWorkspace, "initialize", workspaceId, "Workspace ID is invalid")
    }
    let existed = workspaces[cleanId] != nil
    if !existed {
      workspaces[cleanId] = ["": Entry(type: .directory, data: Data(), modifiedAtMillis: nowMillis())]
      persistWorkspaces()
    }
    return .success(mutationObject(
      kind: .initialize,
      path: "",
      affectedEntries: existed ? 0 : 1,
      metadata: metadata(workspaceId: cleanId, path: "")
    ))
  }

  private func mkdir(
    _ workspaceId: String,
    _ path: String,
    recursive: Bool
  ) -> AgentWorkspaceFileResult<AgentMcpJSONObject> {
    guard let cleanWorkspaceId = canonicalWorkspaceId(workspaceId),
          var workspace = workspace(cleanWorkspaceId, operation: "mkdir") else {
      return failure(.invalidWorkspace, "mkdir", workspaceId, "Workspace ID is invalid")
    }
    guard let normalized = normalizedPath(path, operation: "mkdir", allowRoot: true) else {
      return failure(.pathEscape, "mkdir", path, "Workspace path escaped the workspace")
    }
    let segments = pathSegments(normalized)
    var affected = 0
    var cursor = ""
    for segment in segments {
      cursor = cursor.isEmpty ? segment : "\(cursor)/\(segment)"
      if let existing = workspace[cursor] {
        guard existing.type == .directory else {
          return failure(.notADirectory, "mkdir", cursor, "Workspace entry is not a directory")
        }
      } else {
        if !recursive && cursor != normalized {
          return failure(.notFound, "mkdir", parentPath(normalized), "Parent directory does not exist")
        }
        workspace[cursor] = Entry(type: .directory, data: Data(), modifiedAtMillis: nowMillis())
        affected += 1
      }
    }
    saveWorkspace(workspace, id: cleanWorkspaceId)
    return .success(mutationObject(
      kind: .mkdir,
      path: normalized,
      affectedEntries: affected,
      metadata: metadata(workspaceId: cleanWorkspaceId, path: normalized)
    ))
  }

  private func list(
    _ workspaceId: String,
    _ path: String,
    recursive: Bool,
    maxEntries: Int
  ) -> AgentWorkspaceFileResult<AgentMcpJSONObject> {
    guard let cleanWorkspaceId = canonicalWorkspaceId(workspaceId),
          let workspace = workspace(cleanWorkspaceId, operation: "list") else {
      return failure(.invalidWorkspace, "list", workspaceId, "Workspace ID is invalid")
    }
    guard let normalized = normalizedPath(path, operation: "list", allowRoot: true) else {
      return failure(.pathEscape, "list", path, "Workspace path escaped the workspace")
    }
    guard workspace[normalized] != nil else {
      return failure(.notFound, "list", normalized, "Workspace entry was not found")
    }
    guard workspace[normalized]?.type == .directory else {
      return failure(.notADirectory, "list", normalized, "Workspace entry is not a directory")
    }
    let limited = max(1, min(maxEntries, policy.maxListEntries))
    let prefix = normalized.isEmpty ? "" : "\(normalized)/"
    let entries = workspace.keys
      .filter { !$0.isEmpty && $0.hasPrefix(prefix) }
      .filter { recursive || parentPath($0) == normalized }
      .sorted()
      .prefix(limited)
      .compactMap { metadataObject(metadata(workspaceId: cleanWorkspaceId, path: $0)) }
    return .success([
      "path": .string(normalized),
      "recursive": .bool(recursive),
      "entries": .array(entries.map { .object($0) })
    ])
  }

  private func stat(_ workspaceId: String, _ path: String) -> AgentWorkspaceFileResult<AgentMcpJSONObject> {
    guard let cleanWorkspaceId = canonicalWorkspaceId(workspaceId),
          workspace(cleanWorkspaceId, operation: "stat") != nil else {
      return failure(.invalidWorkspace, "stat", workspaceId, "Workspace ID is invalid")
    }
    guard let normalized = normalizedPath(path, operation: "stat", allowRoot: true) else {
      return failure(.pathEscape, "stat", path, "Workspace path escaped the workspace")
    }
    guard let value = metadata(workspaceId: cleanWorkspaceId, path: normalized) else {
      return failure(.notFound, "stat", normalized, "Workspace entry was not found")
    }
    return .success(metadataObject(value))
  }

  private func readText(
    _ workspaceId: String,
    _ path: String,
    maxBytes: Int64
  ) -> AgentWorkspaceFileResult<AgentMcpJSONObject> {
    guard let read = readFile(workspaceId, path, operation: "read_text", maxBytes: min(maxBytes, policy.maxTextReadBytes)) else {
      return failure(.notFound, "read_text", path, "Workspace file was not found")
    }
    guard let text = String(data: read.data, encoding: .utf8) else {
      return failure(.invalidText, "read_text", read.path, "Workspace file is not valid UTF-8")
    }
    return .success([
      "path": .string(read.path),
      "text": .string(text),
      "size_bytes": .int(Int64(read.data.count)),
      "sha256": .string(sha256Hex(read.data))
    ])
  }

  private func readBytes(
    _ workspaceId: String,
    _ path: String,
    maxBytes: Int64
  ) -> AgentWorkspaceFileResult<AgentMcpJSONObject> {
    guard let read = readFile(workspaceId, path, operation: "read_bytes", maxBytes: min(maxBytes, policy.maxBytesReadBytes)) else {
      return failure(.notFound, "read_bytes", path, "Workspace file was not found")
    }
    return .success([
      "path": .string(read.path),
      "base64": .string(read.data.base64EncodedString()),
      "metadata": .object(metadataObject(read.metadata)),
      "sha256": .string(sha256Hex(read.data))
    ])
  }

  private func writeData(
    _ workspaceId: String,
    _ path: String,
    _ data: Data,
    kind: AgentWorkspaceMutationKind,
    overwrite: Bool,
    createParents: Bool
  ) -> AgentWorkspaceFileResult<AgentMcpJSONObject> {
    guard Int64(data.count) <= policy.maxWriteBytes else {
      return failure(.limitExceeded, kind.rawValue.lowercased(), path, "Workspace write exceeds the configured limit")
    }
    guard let cleanWorkspaceId = canonicalWorkspaceId(workspaceId),
          var workspace = workspace(cleanWorkspaceId, operation: kind.rawValue.lowercased()) else {
      return failure(.invalidWorkspace, kind.rawValue.lowercased(), workspaceId, "Workspace ID is invalid")
    }
    guard let normalized = normalizedPath(path, operation: kind.rawValue.lowercased(), allowRoot: false) else {
      return failure(.pathEscape, kind.rawValue.lowercased(), path, "Workspace path escaped the workspace")
    }
    if !ensureParent(&workspace, path: normalized, createParents: createParents) {
      return failure(.notFound, kind.rawValue.lowercased(), parentPath(normalized), "Parent directory does not exist")
    }
    if let existing = workspace[normalized], existing.type == .directory {
      return failure(.notAFile, kind.rawValue.lowercased(), normalized, "Workspace entry is not a file")
    }
    if !overwrite && workspace[normalized] != nil {
      return failure(.alreadyExists, kind.rawValue.lowercased(), normalized, "Workspace file already exists")
    }
    workspace[normalized] = Entry(type: .file, data: data, modifiedAtMillis: nowMillis())
    saveWorkspace(workspace, id: cleanWorkspaceId)
    return .success(mutationObject(
      kind: kind,
      path: normalized,
      affectedEntries: 1,
      affectedBytes: Int64(data.count),
      metadata: metadata(workspaceId: cleanWorkspaceId, path: normalized)
    ))
  }

  private func writeTextBatch(
    _ workspaceId: String,
    files: [TextBatchFile]?,
    overwrite: Bool
  ) -> AgentWorkspaceFileResult<AgentMcpJSONObject> {
    guard let files, !files.isEmpty, files.count <= Self.maxBatchFiles else {
      return failure(.limitExceeded, "write_text_batch", workspaceId, "Batch must contain between 1 and \(Self.maxBatchFiles) files")
    }
    guard Set(files.map(\.path)).count == files.count else {
      return failure(.invalidPath, "write_text_batch", workspaceId, "Batch contains duplicate file paths")
    }

    var totalBytes: Int64 = 0
    for file in files {
      guard Int64(file.data.count) <= policy.maxWriteBytes,
            let updatedTotal = checkedAdd(totalBytes, Int64(file.data.count)),
            updatedTotal <= Self.maxBatchWriteBytes else {
        return failure(.limitExceeded, "write_text_batch", file.path, "Batch exceeds the \(Self.maxBatchWriteBytes) byte write limit")
      }
      totalBytes = updatedTotal
    }

    guard let cleanWorkspaceId = canonicalWorkspaceId(workspaceId),
          var workspace = workspace(cleanWorkspaceId, operation: "write_text_batch") else {
      return failure(.invalidWorkspace, "write_text_batch", workspaceId, "Workspace ID is invalid")
    }

    var prepared: [TextBatchFile] = []
    for file in files {
      guard let normalized = normalizedPath(file.path, operation: "write_text_batch", allowRoot: false) else {
        return failure(.pathEscape, "write_text_batch", file.path, "Workspace path escaped the workspace")
      }
      guard !prepared.contains(where: { $0.path == normalized }) else {
        return failure(.invalidPath, "write_text_batch", normalized, "Batch contains duplicate file paths")
      }
      if let existing = workspace[normalized] {
        guard existing.type == .file else {
          return failure(.notAFile, "write_text_batch", normalized, "Workspace entry is not a file")
        }
        guard overwrite else {
          return failure(.alreadyExists, "write_text_batch", normalized, "Workspace file already exists")
        }
      }
      prepared.append(TextBatchFile(path: normalized, data: file.data))
    }
    let batchPaths = Set(prepared.map(\.path))
    for file in prepared {
      var ancestor = parentPath(file.path)
      while !ancestor.isEmpty {
        guard !batchPaths.contains(ancestor) else {
          return failure(.notADirectory, "write_text_batch", ancestor, "Batch path conflicts with a descendant file")
        }
        ancestor = parentPath(ancestor)
      }
    }

    // Work on a copy first so a rejected entry cannot leave a partial project behind.
    for file in prepared {
      guard ensureParent(&workspace, path: file.path, createParents: true) else {
        return failure(.notFound, "write_text_batch", parentPath(file.path), "Parent directory does not exist")
      }
      workspace[file.path] = Entry(type: .file, data: file.data, modifiedAtMillis: nowMillis())
    }
    saveWorkspace(workspace, id: cleanWorkspaceId)

    let mutations = prepared.map { file in
      AgentMcpJSONValue.object(mutationObject(
        kind: .write,
        path: file.path,
        affectedEntries: 1,
        affectedBytes: Int64(file.data.count),
        metadata: metadata(workspaceId: cleanWorkspaceId, path: file.path)
      ))
    }
    return .success([
      "files": .array(mutations),
      "affected_entries": .int(Int64(prepared.count)),
      "affected_bytes": .int(totalBytes)
    ])
  }

  private func appendData(
    _ workspaceId: String,
    _ path: String,
    _ data: Data
  ) -> AgentWorkspaceFileResult<AgentMcpJSONObject> {
    guard Int64(data.count) <= policy.maxWriteBytes else {
      return failure(.limitExceeded, "append", path, "Workspace append exceeds the configured limit")
    }
    guard let cleanWorkspaceId = canonicalWorkspaceId(workspaceId),
          var workspace = workspace(cleanWorkspaceId, operation: "append") else {
      return failure(.invalidWorkspace, "append", workspaceId, "Workspace ID is invalid")
    }
    guard let normalized = normalizedPath(path, operation: "append", allowRoot: false) else {
      return failure(.pathEscape, "append", path, "Workspace path escaped the workspace")
    }
    guard var existing = workspace[normalized] else {
      return failure(.notFound, "append", normalized, "Workspace file was not found")
    }
    guard existing.type == .file else {
      return failure(.notAFile, "append", normalized, "Workspace entry is not a file")
    }
    existing.data.append(data)
    existing.modifiedAtMillis = nowMillis()
    workspace[normalized] = existing
    saveWorkspace(workspace, id: cleanWorkspaceId)
    return .success(mutationObject(
      kind: .append,
      path: normalized,
      affectedEntries: 1,
      affectedBytes: Int64(data.count),
      metadata: metadata(workspaceId: cleanWorkspaceId, path: normalized)
    ))
  }

  private func moveOrCopy(
    _ workspaceId: String,
    sourcePath: String,
    destinationPath: String,
    kind: AgentWorkspaceMutationKind,
    overwrite: Bool,
    createParents: Bool
  ) -> AgentWorkspaceFileResult<AgentMcpJSONObject> {
    guard let cleanWorkspaceId = canonicalWorkspaceId(workspaceId),
          var workspace = workspace(cleanWorkspaceId, operation: kind.rawValue.lowercased()) else {
      return failure(.invalidWorkspace, kind.rawValue.lowercased(), workspaceId, "Workspace ID is invalid")
    }
    guard let source = normalizedPath(sourcePath, operation: kind.rawValue.lowercased(), allowRoot: false),
          let destination = normalizedPath(destinationPath, operation: kind.rawValue.lowercased(), allowRoot: false) else {
      return failure(.pathEscape, kind.rawValue.lowercased(), sourcePath, "Workspace path escaped the workspace")
    }
    guard workspace[source] != nil else {
      return failure(.notFound, kind.rawValue.lowercased(), source, "Workspace source entry was not found")
    }
    if !ensureParent(&workspace, path: destination, createParents: createParents) {
      return failure(.notFound, kind.rawValue.lowercased(), parentPath(destination), "Parent directory does not exist")
    }
    if workspace[destination] != nil && !overwrite {
      return failure(.alreadyExists, kind.rawValue.lowercased(), destination, "Destination already exists")
    }
    let affectedPaths = subtreePaths(in: workspace, root: source)
    var affectedBytes: Int64 = 0
    for oldPath in affectedPaths {
      guard let entry = workspace[oldPath] else { continue }
      let suffix = oldPath == source ? "" : String(oldPath.dropFirst(source.count + 1))
      let newPath = suffix.isEmpty ? destination : "\(destination)/\(suffix)"
      var next = entry
      next.modifiedAtMillis = nowMillis()
      workspace[newPath] = next
      if entry.type == .file {
        affectedBytes += Int64(entry.data.count)
      }
    }
    if kind == .move {
      for oldPath in affectedPaths.sorted(by: { $0.count > $1.count }) {
        workspace.removeValue(forKey: oldPath)
      }
    }
    saveWorkspace(workspace, id: cleanWorkspaceId)
    return .success(mutationObject(
      kind: kind,
      path: destination,
      sourcePath: source,
      affectedEntries: affectedPaths.count,
      affectedBytes: affectedBytes,
      metadata: metadata(workspaceId: cleanWorkspaceId, path: destination)
    ))
  }

  private func delete(
    _ workspaceId: String,
    _ path: String,
    recursive: Bool
  ) -> AgentWorkspaceFileResult<AgentMcpJSONObject> {
    guard let cleanWorkspaceId = canonicalWorkspaceId(workspaceId),
          var workspace = workspace(cleanWorkspaceId, operation: "delete") else {
      return failure(.invalidWorkspace, "delete", workspaceId, "Workspace ID is invalid")
    }
    guard let normalized = normalizedPath(path, operation: "delete", allowRoot: false) else {
      return failure(.pathEscape, "delete", path, "Workspace path escaped the workspace")
    }
    guard workspace[normalized] != nil else {
      return failure(.notFound, "delete", normalized, "Workspace entry was not found")
    }
    let paths = subtreePaths(in: workspace, root: normalized)
    if paths.count > 1 && !recursive {
      return failure(.directoryNotEmpty, "delete", normalized, "Directory is not empty")
    }
    var bytes: Int64 = 0
    for item in paths {
      if workspace[item]?.type == .file {
        bytes += Int64(workspace[item]?.data.count ?? 0)
      }
      workspace.removeValue(forKey: item)
    }
    saveWorkspace(workspace, id: cleanWorkspaceId)
    return .success(mutationObject(kind: .delete, path: normalized, affectedEntries: paths.count, affectedBytes: bytes))
  }

  private func searchText(
    _ workspaceId: String,
    _ path: String,
    query: String,
    caseSensitive: Bool,
    maxResults: Int
  ) -> AgentWorkspaceFileResult<AgentMcpJSONObject> {
    guard let cleanWorkspaceId = canonicalWorkspaceId(workspaceId),
          let workspace = workspace(cleanWorkspaceId, operation: "search_text") else {
      return failure(.invalidWorkspace, "search_text", workspaceId, "Workspace ID is invalid")
    }
    guard let normalized = normalizedPath(path, operation: "search_text", allowRoot: true) else {
      return failure(.pathEscape, "search_text", path, "Workspace path escaped the workspace")
    }
    guard workspace[normalized] != nil else {
      return failure(.notFound, "search_text", normalized, "Workspace entry was not found")
    }
    let candidates = subtreePaths(in: workspace, root: normalized).filter { workspace[$0]?.type == .file }.sorted()
    let needle = caseSensitive ? query : query.lowercased()
    var matches: [AgentMcpJSONValue] = []
    var scannedFiles = 0
    var skippedFiles = 0
    var scannedBytes: Int64 = 0
    let cap = max(1, min(maxResults, policy.maxSearchResults))
    for candidate in candidates {
      guard let entry = workspace[candidate] else { continue }
      if Int64(entry.data.count) > policy.maxSearchFileBytes {
        skippedFiles += 1
        continue
      }
      guard let text = String(data: entry.data, encoding: .utf8) else {
        skippedFiles += 1
        continue
      }
      scannedFiles += 1
      scannedBytes += Int64(entry.data.count)
      let lines = text.components(separatedBy: "\n")
      for (lineIndex, line) in lines.enumerated() {
        let haystack = caseSensitive ? line : line.lowercased()
        if let range = haystack.range(of: needle), matches.count < cap {
          matches.append(.object([
            "path": .string(candidate),
            "line": .int(Int64(lineIndex + 1)),
            "column": .int(Int64(haystack.distance(from: haystack.startIndex, to: range.lowerBound) + 1)),
            "excerpt": .string(String(line.prefix(512)))
          ]))
        }
      }
    }
    return .success([
      "query": .string(query),
      "matches": .array(matches),
      "scanned_files": .int(Int64(scannedFiles)),
      "skipped_files": .int(Int64(skippedFiles)),
      "scanned_bytes": .int(scannedBytes),
      "truncated": .bool(matches.count >= cap)
    ])
  }

  private func applyExactPatch(
    _ workspaceId: String,
    _ path: String,
    expected: String,
    replacement: String,
    expectedOccurrences: Int
  ) -> AgentWorkspaceFileResult<AgentMcpJSONObject> {
    let read = readText(workspaceId, path, maxBytes: policy.maxPatchBytes)
    guard case .success(let object) = read, let current = object["text"]?.strictStringValue else {
      return read
    }
    let occurrences = AgentWorkspacePatchPolicy.countOccurrences(text: current, expected: expected)
    guard occurrences == expectedOccurrences else {
      return failure(.patchMismatch, "patch_exact", path, "Expected \(expectedOccurrences) occurrence(s), found \(occurrences)")
    }
    let updated = AgentWorkspacePatchPolicy.replaceOccurrences(text: current, expected: expected, replacement: replacement)
    guard case .success = writeData(workspaceId, path, Data(updated.utf8), kind: .write, overwrite: true, createParents: false) else {
      return failure(.ioError, "patch_exact", path, "Unable to write patched text")
    }
    let normalized = AgentWorkspaceFilePathPolicy.displayPath(path)
    let diff = AgentWorkspacePatchPolicy.summarizeDiff(before: current, after: updated)
    return .success([
      "path": .string(normalized),
      "replacements": .int(Int64(occurrences)),
      "diff": .object(diffObject(diff)),
      "metadata": .object(metadataObject(metadata(workspaceId: workspaceId, path: normalized)))
    ])
  }

  private func diffSummary(
    _ workspaceId: String,
    _ path: String,
    proposedText: String
  ) -> AgentWorkspaceFileResult<AgentMcpJSONObject> {
    let read = readText(workspaceId, path, maxBytes: policy.maxPatchBytes)
    guard case .success(let object) = read, let current = object["text"]?.strictStringValue else {
      return read
    }
    return .success(diffObject(AgentWorkspacePatchPolicy.summarizeDiff(before: current, after: proposedText)))
  }

  private func sha256(_ workspaceId: String, _ path: String) -> AgentWorkspaceFileResult<AgentMcpJSONObject> {
    guard let read = readFile(workspaceId, path, operation: "sha256", maxBytes: policy.maxHashBytes) else {
      return failure(.notFound, "sha256", path, "Workspace file was not found")
    }
    return .success([
      "path": .string(read.path),
      "algorithm": .string("SHA-256"),
      "hex": .string(sha256Hex(read.data)),
      "size_bytes": .int(Int64(read.data.count))
    ])
  }

  private func createZip(
    _ workspaceId: String,
    archivePath: String,
    sourcePaths: [String],
    overwrite: Bool,
    createParents: Bool
  ) -> AgentWorkspaceFileResult<AgentMcpJSONObject> {
    guard !sourcePaths.isEmpty else {
      return failure(.invalidPath, "zip_create", archivePath, "At least one ZIP source path is required")
    }
    guard let cleanWorkspaceId = canonicalWorkspaceId(workspaceId),
          var workspace = workspace(cleanWorkspaceId, operation: "zip_create") else {
      return failure(.invalidWorkspace, "zip_create", workspaceId, "Workspace ID is invalid")
    }
    guard let archive = normalizedPath(archivePath, operation: "zip_create", allowRoot: false) else {
      return failure(.pathEscape, "zip_create", archivePath, "Workspace archive path escaped the workspace")
    }
    if let existing = workspace[archive] {
      guard existing.type == .file else {
        return failure(.notAFile, "zip_create", archive, "Archive destination is not a file")
      }
      guard overwrite else {
        return failure(.alreadyExists, "zip_create", archive, "Archive already exists")
      }
    }
    if !ensureParent(&workspace, path: archive, createParents: createParents) {
      return failure(.notFound, "zip_create", parentPath(archive), "Archive parent directory does not exist")
    }

    var selected: [String: Entry] = [:]
    for sourcePath in sourcePaths {
      guard let source = normalizedPath(sourcePath, operation: "zip_create", allowRoot: false) else {
        return failure(.pathEscape, "zip_create", sourcePath, "ZIP source path escaped the workspace")
      }
      guard workspace[source] != nil else {
        return failure(.notFound, "zip_create", source, "ZIP source entry was not found")
      }
      if archive == source || archive.hasPrefix("\(source)/") {
        return failure(.invalidPath, "zip_create", archive, "Archive destination cannot be inside a selected source")
      }
      for path in subtreePaths(in: workspace, root: source) {
        guard let entry = workspace[path] else { continue }
        if selected[path] != nil {
          return failure(.invalidPath, "zip_create", path, "ZIP sources overlap at \(path)")
        }
        selected[path] = entry
        if selected.count > policy.maxZipEntries {
          return failure(.limitExceeded, "zip_create", path, "ZIP contains more than \(policy.maxZipEntries) entries")
        }
      }
    }

    var totalUncompressedBytes: Int64 = 0
    let sources = selected.keys.sorted().compactMap { path -> ZipSourceEntry? in
      guard let entry = selected[path] else { return nil }
      return ZipSourceEntry(
        path: path,
        directory: entry.type == .directory,
        data: entry.type == .file ? entry.data : Data(),
        modifiedAtMillis: entry.modifiedAtMillis
      )
    }
    for source in sources {
      guard source.path.count <= policy.maxZipEntryNameCharacters else {
        return failure(.limitExceeded, "zip_create", source.path, "ZIP entry name is too long")
      }
      if !source.directory {
        let size = Int64(source.data.count)
        guard size <= policy.maxZipEntryBytes else {
          return failure(.limitExceeded, "zip_create", source.path, "ZIP source entry exceeds the per-entry limit")
        }
        guard let nextTotal = checkedAdd(totalUncompressedBytes, size) else {
          return failure(.limitExceeded, "zip_create", source.path, "ZIP source byte count overflow")
        }
        totalUncompressedBytes = nextTotal
        guard totalUncompressedBytes <= policy.maxZipUncompressedBytes else {
          return failure(.limitExceeded, "zip_create", source.path, "ZIP sources exceed the total uncompressed size limit")
        }
      }
    }

    let archiveData = buildStoredZip(sources)
    guard Int64(archiveData.count) <= policy.maxZipArchiveBytes else {
      return failure(.limitExceeded, "zip_create", archive, "ZIP archive exceeds the compressed size limit")
    }
    guard case .success(let inspection) = inspectZipData(archiveData, archivePath: archive, operation: "zip_create") else {
      return failure(.invalidArchive, "zip_create", archive, "Created ZIP archive failed validation")
    }
    workspace[archive] = Entry(type: .file, data: archiveData, modifiedAtMillis: nowMillis())
    saveWorkspace(workspace, id: cleanWorkspaceId)
    return .success(zipListingObject(inspection))
  }

  private func listZip(
    _ workspaceId: String,
    archivePath: String
  ) -> AgentWorkspaceFileResult<AgentMcpJSONObject> {
    guard let read = readZipArchive(workspaceId, archivePath: archivePath, operation: "zip_list") else {
      return failure(.notFound, "zip_list", archivePath, "Workspace ZIP archive was not found")
    }
    switch inspectZipData(read.data, archivePath: read.path, operation: "zip_list") {
    case .success(let inspection):
      return .success(zipListingObject(inspection))
    case .failure(let error):
      return .failure(error)
    }
  }

  private func extractZip(
    _ workspaceId: String,
    archivePath: String,
    destinationPath: String,
    overwrite: Bool
  ) -> AgentWorkspaceFileResult<AgentMcpJSONObject> {
    guard let cleanWorkspaceId = canonicalWorkspaceId(workspaceId),
          var workspace = workspace(cleanWorkspaceId, operation: "zip_extract") else {
      return failure(.invalidWorkspace, "zip_extract", workspaceId, "Workspace ID is invalid")
    }
    guard let archive = normalizedPath(archivePath, operation: "zip_extract", allowRoot: false) else {
      return failure(.pathEscape, "zip_extract", archivePath, "Workspace archive path escaped the workspace")
    }
    guard let destination = normalizedPath(destinationPath, operation: "zip_extract", allowRoot: true) else {
      return failure(.pathEscape, "zip_extract", destinationPath, "Workspace destination path escaped the workspace")
    }
    guard let archiveEntry = workspace[archive], archiveEntry.type == .file else {
      return failure(.notFound, "zip_extract", archive, "Workspace ZIP archive was not found")
    }
    guard Int64(archiveEntry.data.count) <= policy.maxZipArchiveBytes else {
      return failure(.limitExceeded, "zip_extract", archive, "ZIP archive exceeds the compressed size limit")
    }
    let inspection: ZipInspection
    switch inspectZipData(archiveEntry.data, archivePath: archive, operation: "zip_extract") {
    case .success(let value):
      inspection = value
    case .failure(let error):
      return .failure(error)
    }
    if let existingDestination = workspace[destination], existingDestination.type != .directory {
      return failure(.notADirectory, "zip_extract", destination, "ZIP destination is not a directory")
    }
    if !destination.isEmpty && workspace[destination] == nil &&
      !ensureParent(&workspace, path: destination, createParents: false) {
      return failure(.notFound, "zip_extract", parentPath(destination), "ZIP destination parent directory does not exist")
    }

    for entry in inspection.entries {
      if entry.method != 0 && entry.method != 8 {
        return failure(.unsupportedFileType, "zip_extract", entry.path, "ZIP compression method is not supported on iOS yet")
      }
      let target = joinedPath(destination, entry.path)
      if target == archive {
        return failure(.invalidArchive, "zip_extract", target, "ZIP cannot overwrite its own archive")
      }
      if !entry.directory && !ensureParent(&workspace, path: target, createParents: true) {
        return failure(.notFound, "zip_extract", parentPath(target), "ZIP entry parent directory does not exist")
      }
      var ancestor = parentPath(target)
      while !ancestor.isEmpty {
        if let existing = workspace[ancestor], existing.type != .directory {
          return failure(.alreadyExists, "zip_extract", ancestor, "ZIP entry parent conflicts with a file")
        }
        ancestor = parentPath(ancestor)
      }
      if let existing = workspace[target] {
        if entry.directory {
          guard existing.type == .directory else {
            return failure(.alreadyExists, "zip_extract", target, "ZIP directory conflicts with a file")
          }
        } else if existing.type != .file || !overwrite {
          return failure(.alreadyExists, "zip_extract", target, "ZIP file destination already exists")
        }
      }
    }

    if workspace[destination] == nil {
      workspace[destination] = Entry(type: .directory, data: Data(), modifiedAtMillis: nowMillis())
    }
    var extractedBytes: Int64 = 0
    for entry in inspection.entries.sorted(by: { $0.path < $1.path }) {
      let target = joinedPath(destination, entry.path)
      if entry.directory {
        if workspace[target] == nil {
          workspace[target] = Entry(type: .directory, data: Data(), modifiedAtMillis: nowMillis())
        }
        continue
      }
      let data: Data
      switch zipEntryData(entry, archiveData: archiveEntry.data) {
      case .success(let value):
        data = value
      case .failure(let error):
        return .failure(error)
      }
      guard let nextBytes = checkedAdd(extractedBytes, Int64(data.count)) else {
        return failure(.limitExceeded, "zip_extract", entry.path, "ZIP extracted byte count overflow")
      }
      extractedBytes = nextBytes
      guard extractedBytes <= policy.maxZipUncompressedBytes else {
        return failure(.limitExceeded, "zip_extract", entry.path, "ZIP decompressed data exceeds the configured size limit")
      }
      _ = ensureParent(&workspace, path: target, createParents: true)
      workspace[target] = Entry(
        type: .file,
        data: data,
        modifiedAtMillis: entry.lastModifiedMillis > 0 ? entry.lastModifiedMillis : nowMillis()
      )
    }
    saveWorkspace(workspace, id: cleanWorkspaceId)
    return .success([
      "archive_path": .string(archive),
      "destination_path": .string(destination),
      "extracted_entries": .int(Int64(inspection.entries.count)),
      "extracted_bytes": .int(extractedBytes)
    ])
  }

  private func zipEntryData(_ entry: ZipArchiveEntry, archiveData: Data) -> AgentWorkspaceFileResult<Data> {
    guard rangeFits(start: entry.dataOffset, length: entry.dataLength, in: archiveData) else {
      return failure(.invalidArchive, "zip_extract", entry.path, "ZIP local entry is out of bounds")
    }
    let compressed = archiveData.subdata(in: entry.dataOffset..<(entry.dataOffset + entry.dataLength))
    let data: Data
    switch entry.method {
    case 0:
      data = compressed
    case 8:
      do {
        data = try AgentMcpPackageInstaller.inflateDeflate(
          compressed,
          expectedBytes: entry.uncompressedBytes,
          maxBytes: Int(min(policy.maxZipEntryBytes, Int64(Int.max)))
        )
      } catch {
        let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return failure(.invalidArchive, "zip_extract", entry.path, detail)
      }
    default:
      return failure(.unsupportedFileType, "zip_extract", entry.path, "ZIP compression method is not supported on iOS yet")
    }
    guard Int64(data.count) == entry.uncompressedBytes else {
      return failure(.invalidArchive, "zip_extract", entry.path, "ZIP entry size changed during extraction")
    }
    guard crc32(data) == entry.crc32 else {
      return failure(.invalidArchive, "zip_extract", entry.path, "ZIP entry CRC did not match")
    }
    return .success(data)
  }

  private func readZipArchive(
    _ workspaceId: String,
    archivePath: String,
    operation: String
  ) -> (path: String, data: Data)? {
    guard let cleanWorkspaceId = canonicalWorkspaceId(workspaceId),
          let workspace = workspace(cleanWorkspaceId, operation: operation),
          let normalized = normalizedPath(archivePath, operation: operation, allowRoot: false),
          let entry = workspace[normalized],
          entry.type == .file,
          Int64(entry.data.count) <= policy.maxZipArchiveBytes else {
      return nil
    }
    return (normalized, entry.data)
  }

  private func buildStoredZip(_ entries: [ZipSourceEntry]) -> Data {
    var output = Data()
    var centralRecords: [(entry: ZipSourceEntry, entryName: String, crc32: UInt32, localOffset: Int)] = []
    for entry in entries {
      let entryName = entry.directory ? "\(entry.path)/" : entry.path
      let nameBytes = Data(entryName.utf8)
      let localOffset = output.count
      let crc = entry.directory ? 0 : crc32(entry.data)
      let size = UInt32(entry.directory ? 0 : entry.data.count)
      appendUInt32LE(0x04034b50, to: &output)
      appendUInt16LE(20, to: &output)
      appendUInt16LE(0x0800, to: &output)
      appendUInt16LE(0, to: &output)
      appendUInt16LE(0, to: &output)
      appendUInt16LE(0, to: &output)
      appendUInt32LE(crc, to: &output)
      appendUInt32LE(size, to: &output)
      appendUInt32LE(size, to: &output)
      appendUInt16LE(UInt16(nameBytes.count), to: &output)
      appendUInt16LE(0, to: &output)
      output.append(nameBytes)
      if !entry.directory {
        output.append(entry.data)
      }
      centralRecords.append((entry, entryName, crc, localOffset))
    }
    let centralStart = output.count
    for record in centralRecords {
      let nameBytes = Data(record.entryName.utf8)
      let size = UInt32(record.entry.directory ? 0 : record.entry.data.count)
      appendUInt32LE(0x02014b50, to: &output)
      appendUInt16LE(20, to: &output)
      appendUInt16LE(20, to: &output)
      appendUInt16LE(0x0800, to: &output)
      appendUInt16LE(0, to: &output)
      appendUInt16LE(0, to: &output)
      appendUInt16LE(0, to: &output)
      appendUInt32LE(record.crc32, to: &output)
      appendUInt32LE(size, to: &output)
      appendUInt32LE(size, to: &output)
      appendUInt16LE(UInt16(nameBytes.count), to: &output)
      appendUInt16LE(0, to: &output)
      appendUInt16LE(0, to: &output)
      appendUInt16LE(0, to: &output)
      appendUInt16LE(0, to: &output)
      appendUInt32LE(record.entry.directory ? 0x10 : 0, to: &output)
      appendUInt32LE(UInt32(record.localOffset), to: &output)
      output.append(nameBytes)
    }
    let centralSize = output.count - centralStart
    appendUInt32LE(0x06054b50, to: &output)
    appendUInt16LE(0, to: &output)
    appendUInt16LE(0, to: &output)
    appendUInt16LE(UInt16(centralRecords.count), to: &output)
    appendUInt16LE(UInt16(centralRecords.count), to: &output)
    appendUInt32LE(UInt32(centralSize), to: &output)
    appendUInt32LE(UInt32(centralStart), to: &output)
    appendUInt16LE(0, to: &output)
    return output
  }

  private func inspectZipData(
    _ data: Data,
    archivePath: String,
    operation: String
  ) -> AgentWorkspaceFileResult<ZipInspection> {
    guard Int64(data.count) <= policy.maxZipArchiveBytes else {
      return failure(.limitExceeded, operation, archivePath, "ZIP archive exceeds the compressed size limit")
    }
    guard let eocdOffset = endOfCentralDirectoryOffset(data),
          let diskNumber = readUInt16LE(data, eocdOffset + 4),
          let centralDisk = readUInt16LE(data, eocdOffset + 6),
          let diskEntryCount = readUInt16LE(data, eocdOffset + 8),
          let totalEntryCount = readUInt16LE(data, eocdOffset + 10),
          let centralSizeValue = readUInt32LE(data, eocdOffset + 12),
          let centralOffsetValue = readUInt32LE(data, eocdOffset + 16) else {
      return failure(.invalidArchive, operation, archivePath, "ZIP central directory was not found")
    }
    guard diskNumber == 0, centralDisk == 0, diskEntryCount == totalEntryCount else {
      return failure(.invalidArchive, operation, archivePath, "Multi-disk ZIP archives are not supported")
    }
    let entryCount = Int(totalEntryCount)
    guard entryCount <= policy.maxZipEntries else {
      return failure(.limitExceeded, operation, archivePath, "ZIP contains more than \(policy.maxZipEntries) entries")
    }
    let centralOffset = Int(centralOffsetValue)
    let centralSize = Int(centralSizeValue)
    guard rangeFits(start: centralOffset, length: centralSize, in: data) else {
      return failure(.invalidArchive, operation, archivePath, "ZIP central directory is out of bounds")
    }

    var cursor = centralOffset
    var entries: [ZipArchiveEntry] = []
    var seen: [String: Bool] = [:]
    var totalCompressedBytes: Int64 = 0
    var totalUncompressedBytes: Int64 = 0
    for _ in 0..<entryCount {
      guard readUInt32LE(data, cursor) == 0x02014b50,
            let flags = readUInt16LE(data, cursor + 8),
            let method = readUInt16LE(data, cursor + 10),
            let crc = readUInt32LE(data, cursor + 16),
            let compressed = readUInt32LE(data, cursor + 20),
            let uncompressed = readUInt32LE(data, cursor + 24),
            let nameLength = readUInt16LE(data, cursor + 28),
            let extraLength = readUInt16LE(data, cursor + 30),
            let commentLength = readUInt16LE(data, cursor + 32),
            let localOffsetValue = readUInt32LE(data, cursor + 42) else {
        return failure(.invalidArchive, operation, archivePath, "ZIP central directory entry is invalid")
      }
      guard flags & 0x0001 == 0 else {
        return failure(.unsupportedFileType, operation, archivePath, "Encrypted ZIP entries are not supported")
      }
      guard method == 0 || method == 8 else {
        return failure(.unsupportedFileType, operation, archivePath, "ZIP compression method is not supported on iOS yet")
      }
      let nameStart = cursor + 46
      let extraStart = nameStart + Int(nameLength)
      let commentStart = extraStart + Int(extraLength)
      let nextCursor = commentStart + Int(commentLength)
      guard rangeFits(start: nameStart, length: Int(nameLength), in: data),
            rangeFits(start: extraStart, length: Int(extraLength), in: data),
            rangeFits(start: commentStart, length: Int(commentLength), in: data),
            nextCursor <= centralOffset + centralSize else {
        return failure(.invalidArchive, operation, archivePath, "ZIP central directory entry is out of bounds")
      }
      guard let rawName = String(data: data.subdata(in: nameStart..<extraStart), encoding: .utf8) else {
        return failure(.invalidArchive, operation, archivePath, "ZIP entry name is not valid UTF-8")
      }
      let normalizedName: String
      switch AgentWorkspaceFilePathPolicy.normalizeArchiveEntry(rawName, policy: policy) {
      case .success(let value):
        normalizedName = value
      case .failure(let error):
        return .failure(AgentWorkspaceFileError(code: error.code, operation: operation, path: rawName, message: error.message))
      }
      let directory = rawName.hasSuffix("/") || rawName.hasSuffix("\\")
      if seen[normalizedName] != nil {
        return failure(.invalidArchive, operation, normalizedName, "ZIP contains duplicate entry \(normalizedName)")
      }
      seen[normalizedName] = directory
      let compressedBytes = Int64(compressed)
      let uncompressedBytes = Int64(uncompressed)
      if directory && (compressedBytes > 0 || uncompressedBytes > 0) {
        return failure(.invalidArchive, operation, normalizedName, "ZIP directory entry unexpectedly contains data")
      }
      guard uncompressedBytes <= policy.maxZipEntryBytes else {
        return failure(.limitExceeded, operation, normalizedName, "ZIP entry exceeds the per-entry size limit")
      }
      guard let nextUncompressed = checkedAdd(totalUncompressedBytes, uncompressedBytes),
            let nextCompressed = checkedAdd(totalCompressedBytes, compressedBytes) else {
        return failure(.limitExceeded, operation, normalizedName, "ZIP byte count overflow")
      }
      totalUncompressedBytes = nextUncompressed
      totalCompressedBytes = nextCompressed
      guard totalUncompressedBytes <= policy.maxZipUncompressedBytes else {
        return failure(.limitExceeded, operation, normalizedName, "ZIP exceeds the total uncompressed size limit")
      }
      let ratio = compressionRatio(uncompressedBytes: uncompressedBytes, compressedBytes: compressedBytes)
      guard ratio <= policy.maxZipCompressionRatio else {
        return failure(.limitExceeded, operation, normalizedName, "ZIP entry exceeds the compression ratio limit")
      }
      let localOffset = Int(localOffsetValue)
      guard let dataOffset = zipEntryDataOffset(data, localOffset: localOffset),
            rangeFits(start: dataOffset, length: Int(compressed), in: data) else {
        return failure(.invalidArchive, operation, normalizedName, "ZIP local entry is out of bounds")
      }
      entries.append(ZipArchiveEntry(
        path: normalizedName,
        directory: directory,
        method: method,
        compressedBytes: compressedBytes,
        uncompressedBytes: uncompressedBytes,
        compressionRatio: ratio,
        crc32: crc,
        lastModifiedMillis: 0,
        dataOffset: dataOffset,
        dataLength: Int(compressed)
      ))
      cursor = nextCursor
    }
    for (name, _) in seen {
      let segments = pathSegments(name)
      guard segments.count > 1 else { continue }
      for index in 1..<segments.count {
        let parent = segments.prefix(index).joined(separator: "/")
        if seen[parent] == false {
          return failure(.invalidArchive, operation, parent, "ZIP file entry is used as a directory: \(parent)")
        }
      }
    }
    guard compressionRatio(
      uncompressedBytes: totalUncompressedBytes,
      compressedBytes: totalCompressedBytes
    ) <= policy.maxZipCompressionRatio else {
      return failure(.limitExceeded, operation, archivePath, "ZIP exceeds the total compression ratio limit")
    }
    return .success(ZipInspection(
      archivePath: archivePath,
      archiveBytes: Int64(data.count),
      totalCompressedBytes: totalCompressedBytes,
      totalUncompressedBytes: totalUncompressedBytes,
      entries: entries.sorted { $0.path < $1.path }
    ))
  }

  private func readFile(
    _ workspaceId: String,
    _ path: String,
    operation: String,
    maxBytes: Int64
  ) -> (path: String, data: Data, metadata: AgentWorkspaceFileMetadata)? {
    guard let workspace = workspace(workspaceId, operation: operation),
          let normalized = normalizedPath(path, operation: operation, allowRoot: false),
          let entry = workspace[normalized],
          entry.type == .file,
          Int64(entry.data.count) <= maxBytes,
          let metadata = metadata(workspaceId: workspaceId, path: normalized) else {
      return nil
    }
    return (normalized, entry.data, metadata)
  }

  private func workspace(_ workspaceId: String, operation: String) -> [String: Entry]? {
    guard let cleanId = canonicalWorkspaceId(workspaceId) else {
      return nil
    }
    if workspaces[cleanId] == nil {
      workspaces[cleanId] = ["": Entry(type: .directory, data: Data(), modifiedAtMillis: nowMillis())]
      persistWorkspaces()
    }
    return workspaces[cleanId]
  }

  private func saveWorkspace(_ workspace: [String: Entry], id: String) {
    workspaces[id] = workspace
    persistWorkspaces()
  }

  private func persistWorkspaces() {
    stateStore?.save(workspaces.mapValues { workspace in
      workspace.mapValues { entry in
        AgentWorkspaceNativeToolStoredEntry(
          type: entry.type,
          data: entry.data,
          modifiedAtMillis: entry.modifiedAtMillis
        )
      }
    })
  }

  private static func restoreWorkspaces(
    _ stored: [String: [String: AgentWorkspaceNativeToolStoredEntry]]
  ) -> [String: [String: Entry]] {
    stored.reduce(into: [:]) { result, workspace in
      guard case .success(let cleanWorkspaceId) = AgentWorkspaceFilePathPolicy.workspaceDirectoryName(workspace.key) else {
        return
      }
      var entries: [String: Entry] = [:]
      for item in workspace.value {
        guard case .success(let segments) = AgentWorkspaceFilePathPolicy.normalizeRelativePath(item.key, allowRoot: true),
              let data = item.value.data() else {
          continue
        }
        let path = segments.joined(separator: "/")
        entries[path] = Entry(
          type: item.value.type,
          data: item.value.type == .file ? data : Data(),
          modifiedAtMillis: item.value.modifiedAtMillis
        )
      }
      if entries[""]?.type != .directory {
        entries[""] = Entry(type: .directory, data: Data(), modifiedAtMillis: 0)
      }
      result[cleanWorkspaceId] = entries
    }
  }

  private func canonicalWorkspaceId(_ workspaceId: String) -> String? {
    guard case .success(let cleanId) = AgentWorkspaceFilePathPolicy.workspaceDirectoryName(workspaceId) else {
      return nil
    }
    return cleanId
  }

  private func normalizedPath(_ path: String, operation: String, allowRoot: Bool) -> String? {
    guard case .success(let segments) = AgentWorkspaceFilePathPolicy.normalizeRelativePath(path, allowRoot: allowRoot) else {
      return nil
    }
    return segments.joined(separator: "/")
  }

  private func ensureParent(_ workspace: inout [String: Entry], path: String, createParents: Bool) -> Bool {
    let parent = parentPath(path)
    if workspace[parent]?.type == .directory {
      return true
    }
    guard createParents else {
      return false
    }
    var cursor = ""
    for segment in pathSegments(parent) {
      cursor = cursor.isEmpty ? segment : "\(cursor)/\(segment)"
      if workspace[cursor] == nil {
        workspace[cursor] = Entry(type: .directory, data: Data(), modifiedAtMillis: nowMillis())
      }
      if workspace[cursor]?.type != .directory {
        return false
      }
    }
    return true
  }

  private func metadata(workspaceId: String, path: String) -> AgentWorkspaceFileMetadata? {
    guard let entry = workspaces[workspaceId]?[path] else { return nil }
    return AgentWorkspaceFileMetadata(
      path: path,
      type: entry.type,
      sizeBytes: entry.type == .file ? Int64(entry.data.count) : 0,
      lastModifiedMillis: entry.modifiedAtMillis
    )
  }

  private func metadataObject(_ metadata: AgentWorkspaceFileMetadata?) -> AgentMcpJSONObject {
    guard let metadata else { return [:] }
    return [
      "path": .string(metadata.path),
      "type": .string(metadata.type.rawValue.lowercased()),
      "size_bytes": .int(metadata.sizeBytes),
      "last_modified_epoch_ms": .int(metadata.lastModifiedMillis)
    ]
  }

  private func mutationObject(
    kind: AgentWorkspaceMutationKind,
    path: String,
    sourcePath: String = "",
    affectedEntries: Int = 1,
    affectedBytes: Int64 = 0,
    metadata: AgentWorkspaceFileMetadata? = nil
  ) -> AgentMcpJSONObject {
    var object: AgentMcpJSONObject = [
      "kind": .string(kind.rawValue.lowercased()),
      "path": .string(path),
      "source_path": .string(sourcePath),
      "affected_entries": .int(Int64(max(0, affectedEntries))),
      "affected_bytes": .int(max(0, affectedBytes))
    ]
    if let metadata {
      object["metadata"] = .object(metadataObject(metadata))
    }
    return object
  }

  private func diffObject(_ diff: AgentWorkspaceDiffSummary) -> AgentMcpJSONObject {
    var object: AgentMcpJSONObject = [
      "before_sha256": .string(diff.beforeSha256),
      "after_sha256": .string(diff.afterSha256),
      "before_bytes": .int(diff.beforeBytes),
      "after_bytes": .int(diff.afterBytes),
      "before_lines": .int(Int64(diff.beforeLines)),
      "after_lines": .int(Int64(diff.afterLines)),
      "added_lines": .int(Int64(diff.addedLines)),
      "deleted_lines": .int(Int64(diff.deletedLines)),
      "changed_line_pairs": .int(Int64(diff.changedLinePairs))
    ]
    if let line = diff.firstChangedLine {
      object["first_changed_line"] = .int(Int64(line))
    }
    return object
  }

  private func errorObject(_ error: AgentWorkspaceFileError) -> AgentMcpJSONObject {
    [
      "code": .string(error.code.rawValue),
      "operation": .string(error.operation),
      "path": .string(error.path),
      "message": .string(error.message)
    ]
  }

  private func zipListingObject(_ inspection: ZipInspection) -> AgentMcpJSONObject {
    [
      "archive_path": .string(inspection.archivePath),
      "archive_bytes": .int(inspection.archiveBytes),
      "total_compressed_bytes": .int(inspection.totalCompressedBytes),
      "total_uncompressed_bytes": .int(inspection.totalUncompressedBytes),
      "entries": .array(inspection.entries.map { .object(zipEntryObject($0)) })
    ]
  }

  private func zipEntryObject(_ entry: ZipArchiveEntry) -> AgentMcpJSONObject {
    [
      "path": .string(entry.path),
      "directory": .bool(entry.directory),
      "compressed_bytes": .int(entry.compressedBytes),
      "uncompressed_bytes": .int(entry.uncompressedBytes),
      "compression_ratio": .double(entry.compressionRatio),
      "crc32": .int(Int64(entry.crc32)),
      "last_modified_epoch_ms": .int(entry.lastModifiedMillis)
    ]
  }

  private func subtreePaths(in workspace: [String: Entry], root: String) -> [String] {
    let prefix = "\(root)/"
    return workspace.keys.filter { $0 == root || $0.hasPrefix(prefix) }.sorted()
  }

  private func joinedPath(_ base: String, _ child: String) -> String {
    base.isEmpty ? child : "\(base)/\(child)"
  }

  private func parentPath(_ path: String) -> String {
    let segments = pathSegments(path)
    guard segments.count > 1 else { return "" }
    return segments.dropLast().joined(separator: "/")
  }

  private func pathSegments(_ path: String) -> [String] {
    path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
  }

  private func checkedAdd(_ left: Int64, _ right: Int64) -> Int64? {
    guard right >= 0, left <= Int64.max - right else {
      return nil
    }
    return left + right
  }

  private func compressionRatio(uncompressedBytes: Int64, compressedBytes: Int64) -> Double {
    guard uncompressedBytes > 0 else { return 0 }
    guard compressedBytes > 0 else { return Double.greatestFiniteMagnitude }
    return Double(uncompressedBytes) / Double(compressedBytes)
  }

  private func appendUInt16LE(_ value: UInt16, to data: inout Data) {
    data.append(UInt8(value & 0x00ff))
    data.append(UInt8((value >> 8) & 0x00ff))
  }

  private func appendUInt32LE(_ value: UInt32, to data: inout Data) {
    data.append(UInt8(value & 0x000000ff))
    data.append(UInt8((value >> 8) & 0x000000ff))
    data.append(UInt8((value >> 16) & 0x000000ff))
    data.append(UInt8((value >> 24) & 0x000000ff))
  }

  private func readUInt16LE(_ data: Data, _ offset: Int) -> UInt16? {
    guard rangeFits(start: offset, length: 2, in: data) else { return nil }
    return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
  }

  private func readUInt32LE(_ data: Data, _ offset: Int) -> UInt32? {
    guard rangeFits(start: offset, length: 4, in: data) else { return nil }
    return UInt32(data[offset]) |
      (UInt32(data[offset + 1]) << 8) |
      (UInt32(data[offset + 2]) << 16) |
      (UInt32(data[offset + 3]) << 24)
  }

  private func rangeFits(start: Int, length: Int, in data: Data) -> Bool {
    start >= 0 && length >= 0 && start <= data.count && length <= data.count - start
  }

  private func endOfCentralDirectoryOffset(_ data: Data) -> Int? {
    guard data.count >= 22 else { return nil }
    let minimumOffset = max(0, data.count - 65_557)
    for offset in stride(from: data.count - 22, through: minimumOffset, by: -1) {
      if readUInt32LE(data, offset) == 0x06054b50 {
        return offset
      }
    }
    return nil
  }

  private func zipEntryDataOffset(_ data: Data, localOffset: Int) -> Int? {
    guard readUInt32LE(data, localOffset) == 0x04034b50,
          let nameLength = readUInt16LE(data, localOffset + 26),
          let extraLength = readUInt16LE(data, localOffset + 28) else {
      return nil
    }
    let dataOffset = localOffset + 30 + Int(nameLength) + Int(extraLength)
    return rangeFits(start: dataOffset, length: 0, in: data) ? dataOffset : nil
  }

  private func decodedBase64(_ input: AgentMcpJSONObject) -> Data {
    Data(base64Encoded: string(input, "base64")) ?? Data()
  }

  private func stringList(_ input: AgentMcpJSONObject, _ key: String) -> [String] {
    input[key]?.arrayValue?.compactMap(\.strictStringValue) ?? []
  }

  private func textBatchFiles(_ input: AgentMcpJSONObject, _ key: String) -> [TextBatchFile]? {
    guard let values = input[key]?.arrayValue else { return nil }
    let files = values.compactMap { value -> TextBatchFile? in
      guard let object = value.objectValue,
            let path = object["path"]?.strictStringValue,
            let text = object["text"]?.strictStringValue else {
        return nil
      }
      return TextBatchFile(path: path, data: Data(text.utf8))
    }
    return files.count == values.count ? files : nil
  }

  private func string(_ input: AgentMcpJSONObject, _ key: String, _ defaultValue: String? = nil) -> String {
    input[key]?.strictStringValue ?? defaultValue ?? ""
  }

  private func bool(_ input: AgentMcpJSONObject, _ key: String, _ defaultValue: Bool) -> Bool {
    input[key]?.boolValue ?? defaultValue
  }

  private func int(_ input: AgentMcpJSONObject, _ key: String, _ defaultValue: Int) -> Int {
    input[key]?.integerForSchema ?? defaultValue
  }

  private func int64(_ input: AgentMcpJSONObject, _ key: String, _ defaultValue: Int64) -> Int64 {
    input[key]?.intValue ?? defaultValue
  }

  private func failure<T: Equatable>(
    _ code: AgentWorkspaceFileErrorCode,
    _ operation: String,
    _ path: String,
    _ message: String
  ) -> AgentWorkspaceFileResult<T> {
    .failure(AgentWorkspaceFileError(code: code, operation: operation, path: path, message: message))
  }

  private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func crc32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xffffffff
    for byte in data {
      let index = Int((crc ^ UInt32(byte)) & 0xff)
      crc = (crc >> 8) ^ Self.crc32Table[index]
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
