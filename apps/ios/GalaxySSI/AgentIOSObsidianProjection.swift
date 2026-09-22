import CryptoKit
import Foundation
import SQLite3

private struct AgentIOSObsidianProjectionSpec {
  var sourceKey: String
  var relativePath: String
  var sourceRevision: String
  var legacySourceKey = ""
  var exactSource = ""
  var content: () throws -> String
  var writeContent: ((URL) throws -> String?)?
}

private enum AgentIOSObsidianProjectionStep: Equatable {
  case written
  case unchanged
  case deferred
}

@MainActor
enum AgentIOSObsidianBridge {
  static func settings(stateStore: AgentIOSObsidianStateStore = AgentIOSObsidianStateStore()) -> AgentIOSObsidianSettings {
    stateStore.settings()
  }

  static func configure(
    _ vaultURL: URL,
    stateStore: AgentIOSObsidianStateStore = AgentIOSObsidianStateStore()
  ) throws -> AgentIOSObsidianSettings {
    let bookmark = try vaultURL.bookmarkData(
      options: .minimalBookmark,
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
    let settings = AgentIOSObsidianSettings(
      enabled: true,
      bookmarkData: bookmark,
      vaultName: vaultURL.lastPathComponent.ifBlank("Obsidian Vault")
    )
    stateStore.saveSettings(settings)
    return settings
  }

  static func disconnect(stateStore: AgentIOSObsidianStateStore = AgentIOSObsidianStateStore()) {
    var settings = stateStore.settings()
    settings.enabled = false
    settings.bookmarkData = Data()
    settings.vaultName = ""
    settings.lastError = ""
    stateStore.saveSettings(settings)
  }

  static func pendingCandidates(
    stateStore: AgentIOSObsidianStateStore = AgentIOSObsidianStateStore()
  ) -> [AgentIOSObsidianEditCandidate] {
    stateStore.candidates(status: .pending)
  }

  static func approveCandidate(
    _ candidateId: String,
    appStore: GalaxySSIStore,
    stateStore: AgentIOSObsidianStateStore = AgentIOSObsidianStateStore()
  ) -> Bool {
    guard var candidate = stateStore.candidates(status: .pending).first(where: { $0.id == candidateId }) else {
      return false
    }
    let body = stripFrontMatter(candidate.content).trimmingCharacters(in: .whitespacesAndNewlines)
    guard AgentIOSObsidianProjectionPrivacyPolicy.safeKnowledge(body) else { return false }
    let imported = appStore.importAgentKnowledge(
      title: candidate.title.ifBlank(URL(fileURLWithPath: candidate.relativePath).deletingPathExtension().lastPathComponent),
      content: body,
      source: "obsidian-edit://\(candidate.relativePath)",
      kind: .note,
      tags: ["obsidian", "reviewed"]
    )
    guard !imported.isEmpty else { return false }
    _ = appStore.updateAgentKnowledgeSourceAccess(
      itemIds: imported.map(\.id),
      cloudAccess: .deny,
      agentAccess: .localOnly
    )
    candidate.status = .approved
    candidate.reviewedAtMillis = AgentMemoryClock.nowMillis()
    stateStore.saveCandidate(candidate)
    stateStore.removeIndex(sourceKey: candidate.sourceKey)
    return true
  }

  static func rejectCandidate(
    _ candidateId: String,
    stateStore: AgentIOSObsidianStateStore = AgentIOSObsidianStateStore()
  ) -> Bool {
    guard var candidate = stateStore.candidates(status: .pending).first(where: { $0.id == candidateId }) else {
      return false
    }
    candidate.status = .rejected
    candidate.reviewedAtMillis = AgentMemoryClock.nowMillis()
    stateStore.saveCandidate(candidate)
    stateStore.removeIndex(sourceKey: candidate.sourceKey)
    return true
  }

  static func projectIncrementally(
    appStore: GalaxySSIStore,
    maximumWrites: Int = 12,
    stateStore: AgentIOSObsidianStateStore = AgentIOSObsidianStateStore()
  ) -> AgentIOSObsidianProjectionResult {
    var settings = stateStore.settings()
    guard settings.enabled, !settings.bookmarkData.isEmpty else {
      return AgentIOSObsidianProjectionResult(configured: false)
    }
    do {
      var stale = false
      let root = try URL(
        resolvingBookmarkData: settings.bookmarkData,
        options: .withoutUI,
        relativeTo: nil,
        bookmarkDataIsStale: &stale
      )
      let accessing = root.startAccessingSecurityScopedResource()
      defer { if accessing { root.stopAccessingSecurityScopedResource() } }
      if stale {
        settings.bookmarkData = try root.bookmarkData(
          options: .minimalBookmark,
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        )
      }

      let candidateCount = scanUserEdits(root: root, stateStore: stateStore)
      let writeLimit = max(1, min(maximumWrites, 32))
      var written = 0
      var unchanged = 0
      let namespace = sha256(settings.bookmarkData.base64EncodedString())
      var checkpoint = stateStore.projectionCheckpoint()
      if checkpoint?.namespace != namespace {
        checkpoint = nil
        stateStore.saveProjectionCheckpoint(nil)
      }
      var page: AgentKnowledgeSourcePage
      do {
        page = try appStore.agentKnowledgeDatabase.sourcePage(cursor: checkpoint?.cursor, limit: 50)
      } catch AgentKnowledgeDatabaseError.staleCursor {
        checkpoint = nil
        stateStore.saveProjectionCheckpoint(nil)
        page = try appStore.agentKnowledgeDatabase.sourcePage(limit: 50)
      }
      if let savedCheckpoint = checkpoint, savedCheckpoint.visited > page.total {
        stateStore.saveProjectionCheckpoint(nil)
        checkpoint = nil
        page = try appStore.agentKnowledgeDatabase.sourcePage(limit: 50)
      }
      var visited = checkpoint?.visited ?? 0
      for index in page.groups.indices {
        let step = try project(
          knowledgeProjectionSpec(appStore: appStore, group: page.groups[index]),
          canWrite: written < writeLimit,
          root: root,
          stateStore: stateStore
        )
        if step == .deferred { break }
        if step == .written { written += 1 } else { unchanged += 1 }
        visited += 1
        stateStore.saveProjectionCheckpoint(.init(
          namespace: namespace,
          cursor: page.positions[index],
          visited: visited
        ))
      }
      let currentRevision = try appStore.agentKnowledgeDatabase.sourceBrowseRevision()
      var knowledgeRemaining = max(page.total - visited, 0)
      if let pageRevision = page.positions.first?.revision, pageRevision != currentRevision {
        stateStore.saveProjectionCheckpoint(nil)
        knowledgeRemaining = max(page.total, 1)
      } else if knowledgeRemaining == 0 {
        stateStore.saveProjectionCheckpoint(nil)
      }

      var otherRemaining = 0
      for spec in otherProjectionSpecs(appStore: appStore) {
        let step = try project(
          spec,
          canWrite: written < writeLimit,
          root: root,
          stateStore: stateStore
        )
        switch step {
        case .written: written += 1
        case .unchanged: unchanged += 1
        case .deferred: otherRemaining += 1
        }
      }
      let remaining = knowledgeRemaining + otherRemaining
      settings.lastProjectionAtMillis = AgentMemoryClock.nowMillis()
      settings.lastError = ""
      stateStore.saveSettings(settings)
      return .init(
        configured: true,
        writtenCount: written,
        unchangedCount: unchanged,
        candidateCount: candidateCount,
        remainingCount: remaining
      )
    } catch {
      settings.lastError = String(error.localizedDescription.prefix(600))
      stateStore.saveSettings(settings)
      return .init(configured: true, error: settings.lastError)
    }
  }

  static func note(
    sourceKey: String,
    type: String,
    title: String,
    source: String,
    updatedAtMillis: Int64,
    tags: [String],
    body: String
  ) -> String {
    let cleanBody = AgentIOSObsidianProjectionPrivacyPolicy.transcriptText(body)
    return noteHeader(
      sourceKey: sourceKey,
      type: type,
      title: title,
      source: source,
      updatedAtMillis: updatedAtMillis,
      tags: tags,
      contentHash: sha256(cleanBody)
    ) + cleanBody + "\n"
  }

  private static func noteHeader(
    sourceKey: String,
    type: String,
    title: String,
    source: String,
    updatedAtMillis: Int64,
    tags: [String],
    contentHash: String
  ) -> String {
    let cleanTitle = AgentIOSObsidianProjectionPrivacyPolicy.safeMetadata(title) ? title.trimmingCharacters(in: .whitespacesAndNewlines) : ""
    let resolvedTitle = cleanTitle.ifBlank("GalaxySSI")
    let cleanSource = AgentIOSObsidianProjectionPrivacyPolicy.safeMetadata(source) ? source.trimmingCharacters(in: .whitespacesAndNewlines) : ""
    let cleanTags = tags.filter(AgentIOSObsidianProjectionPrivacyPolicy.safeMetadata)
    var lines = [
      "---",
      "galaxyssi_id: \"\(yaml(sourceKey))\"",
      "galaxyssi_type: \"\(yaml(type))\"",
      "status: current",
      "title: \"\(yaml(resolvedTitle))\""
    ]
    if !cleanSource.isEmpty { lines.append("source: \"\(yaml(cleanSource))\"") }
    lines.append("updated_at: \"\(isoDate(updatedAtMillis))\"")
    lines.append("content_hash: \"\(contentHash)\"")
    lines.append("managed_by: galaxyssi")
    if !cleanTags.isEmpty {
      lines.append("tags: [\(cleanTags.map { "\"\(yaml($0))\"" }.joined(separator: ", "))]")
    }
    lines.append(contentsOf: ["---", "", "# \(resolvedTitle)", ""])
    return lines.joined(separator: "\n")
  }

  private static func knowledgeProjectionSpec(
    appStore: GalaxySSIStore,
    group: AgentKnowledgeSourceGroup
  ) -> AgentIOSObsidianProjectionSpec {
    let source = group.localItemId.ifBlank(group.source)
    let reading = source.lowercased().hasPrefix("http://") || source.lowercased().hasPrefix("https://")
    let sourceKey = knowledgeSourceKey(group)
    let title = group.title.ifBlank("Knowledge")
    return AgentIOSObsidianProjectionSpec(
      sourceKey: sourceKey,
      relativePath: "\(reading ? "60 Reading" : "10 Knowledge")/\(fileName(title, sourceKey: sourceKey))",
      sourceRevision: group.sourceRevision,
      legacySourceKey: "knowledge:\(GlobalAgentText.stableKey(source))",
      exactSource: source,
      content: { "" },
      writeContent: { destination in
        try writeKnowledgeProjection(
          database: appStore.agentKnowledgeDatabase,
          group: group,
          sourceKey: sourceKey,
          type: reading ? "reading" : "knowledge",
          fallbackTitle: title,
          source: source,
          destination: destination
        )
      }
    )
  }

  static func writeKnowledgeProjection(
    database: AgentKnowledgeDatabase,
    group: AgentKnowledgeSourceGroup,
    sourceKey: String,
    type: String,
    fallbackTitle: String,
    source: String,
    destination: URL,
    scratchCipher suppliedScratchCipher: GalaxySSIAttachmentAtRestCipher? = nil
  ) throws -> String? {
    let fileManager = FileManager.default
    let jobId = UUID().uuidString.lowercased()
    let scratchURL = fileManager.temporaryDirectory
      .appendingPathComponent("galaxyssi-obsidian-order-\(jobId).sqlite")
    defer {
      for suffix in ["", "-wal", "-shm"] { try? fileManager.removeItem(atPath: scratchURL.path + suffix) }
    }
    var scratch: OpaquePointer?
    guard sqlite3_open_v2(
      scratchURL.path,
      &scratch,
      SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
      nil
    ) == SQLITE_OK, let scratch else { throw AgentKnowledgeDatabaseError.unavailable }
    defer { sqlite3_close_v2(scratch) }
    _ = sqlite3_exec(scratch, "PRAGMA journal_mode = DELETE", nil, nil, nil)
    _ = sqlite3_exec(scratch, "PRAGMA synchronous = FULL", nil, nil, nil)
    guard sqlite3_exec(scratch, """
      CREATE TABLE ordered_parts(
        chunk_index INTEGER NOT NULL,
        id_hash TEXT NOT NULL,
        encrypted_item BLOB NOT NULL,
        PRIMARY KEY(chunk_index, id_hash)
      )
      """, nil, nil, nil) == SQLITE_OK else { throw AgentKnowledgeDatabaseError.unavailable }
    try? fileManager.setAttributes(
      [.protectionKey: FileProtectionType.complete],
      ofItemAtPath: scratchURL.path
    )
    let scratchCipher = suppliedScratchCipher ?? GalaxySSIAttachmentAtRestCipher(
      keyAccount: "agent.obsidian.order.aes256.v1"
    )
    guard sqlite3_exec(scratch, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else {
      throw AgentKnowledgeDatabaseError.unavailable
    }
    do {
      try database.enumerateSourceSnapshotItems(group) { item in
        guard AgentIOSObsidianProjectionPrivacyPolicy.safeKnowledge(item.content) else { return }
        let idHash = sha256(item.id)
        let plaintext = try JSONEncoder.galaxySSI.encode(item)
        let encrypted = try scratchCipher.encrypt(
          plaintext,
          purpose: "obsidian-order:v1:\(jobId):\(idHash)"
        )
        var insert: OpaquePointer?
        guard sqlite3_prepare_v2(
          scratch,
          "INSERT INTO ordered_parts(chunk_index, id_hash, encrypted_item) VALUES (?, ?, ?)",
          -1,
          &insert,
          nil
        ) == SQLITE_OK, let insert else { throw AgentKnowledgeDatabaseError.unavailable }
        defer { sqlite3_finalize(insert) }
        sqlite3_bind_int64(insert, 1, Int64(item.chunkIndex))
        idHash.withCString {
          sqlite3_bind_text(insert, 2, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        encrypted.withUnsafeBytes { bytes in
          sqlite3_bind_blob(insert, 3, bytes.baseAddress, Int32(encrypted.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        guard sqlite3_step(insert) == SQLITE_DONE else { throw AgentKnowledgeDatabaseError.corruptRecord }
      }
      guard sqlite3_exec(scratch, "COMMIT", nil, nil, nil) == SQLITE_OK else {
        throw AgentKnowledgeDatabaseError.unavailable
      }
    } catch {
      _ = sqlite3_exec(scratch, "ROLLBACK", nil, nil, nil)
      throw error
    }

    var bodyHasher = SHA256()
    var title = fallbackTitle
    var updatedAt: Int64 = 0
    var tags: [String] = []
    var seenTags = Set<String>()
    var count = 0
    var previousTail = ""
    var redacted = false
    func scanOrdered(_ consume: (String) throws -> Void) throws {
      var statement: OpaquePointer?
      guard sqlite3_prepare_v2(
        scratch,
        "SELECT id_hash, encrypted_item FROM ordered_parts ORDER BY chunk_index ASC, id_hash ASC",
        -1,
        &statement,
        nil
      ) == SQLITE_OK, let statement else { throw AgentKnowledgeDatabaseError.unavailable }
      defer { sqlite3_finalize(statement) }
      while sqlite3_step(statement) == SQLITE_ROW {
        guard let hashText = sqlite3_column_text(statement, 0),
              let bytes = sqlite3_column_blob(statement, 1) else {
          throw AgentKnowledgeDatabaseError.corruptRecord
        }
        let idHash = String(cString: hashText)
        let encrypted = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 1)))
        guard let plaintext = try? scratchCipher.decrypt(
                encrypted,
                expectedPurpose: "obsidian-order:v1:\(jobId):\(idHash)"
              ),
              let item = try? JSONDecoder.galaxySSI.decode(AgentKnowledgeItem.self, from: plaintext),
              sha256(item.id) == idHash else { throw AgentKnowledgeDatabaseError.corruptRecord }
        try consume(AgentIOSObsidianProjectionPrivacyPolicy.transcriptText(item.content)
          .trimmingCharacters(in: .whitespacesAndNewlines))
        if count == 0 {
          title = item.title.replacingOccurrences(
            of: #"\s+\[[0-9]+/[0-9]+\]$"#,
            with: "",
            options: .regularExpression
          ).ifBlank(fallbackTitle)
        }
        updatedAt = max(updatedAt, item.updatedAtMillis)
        for tag in item.tags where tags.count < 16 && seenTags.insert(tag).inserted { tags.append(tag) }
        count += 1
      }
    }
    try scanOrdered { part in
      if count > 0 {
        let separator = Data("\n\n".utf8)
        bodyHasher.update(data: separator)
        redacted = redacted || !AgentIOSObsidianProjectionPrivacyPolicy.safeKnowledge(
          previousTail + "\n\n" + String(part.prefix(64))
        )
      }
      bodyHasher.update(data: Data(part.utf8))
      previousTail = String(part.suffix(64))
    }
    guard count > 0 else { return nil }
    if redacted {
      let content = note(
        sourceKey: sourceKey,
        type: type,
        title: title,
        source: source,
        updatedAtMillis: updatedAt,
        tags: tags,
        body: "Sensitive content omitted by GalaxySSI"
      )
      try content.write(to: destination, atomically: true, encoding: .utf8)
      return sha256(content)
    }

    let bodyHash = bodyHasher.finalize().map { String(format: "%02x", $0) }.joined()
    let header = noteHeader(
      sourceKey: sourceKey,
      type: type,
      title: title,
      source: source,
      updatedAtMillis: updatedAt,
      tags: tags,
      contentHash: bodyHash
    )
    let temporary = destination.deletingLastPathComponent()
      .appendingPathComponent(".\(destination.lastPathComponent).\(jobId).tmp")
    fileManager.createFile(atPath: temporary.path, contents: nil)
    defer { try? fileManager.removeItem(at: temporary) }
    let output = try FileHandle(forWritingTo: temporary)
    var outputHasher = SHA256()
    func write(_ data: Data) throws {
      try output.write(contentsOf: data)
      outputHasher.update(data: data)
    }
    do {
      try write(Data(header.utf8))
      var written = 0
      count = 0
      try scanOrdered { part in
        if written > 0 { try write(Data("\n\n".utf8)) }
        try write(Data(part.utf8))
        written += 1
      }
      try write(Data("\n".utf8))
      try output.synchronize()
      try output.close()
    } catch {
      try? output.close()
      throw error
    }
    try fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: temporary.path)
    if fileManager.fileExists(atPath: destination.path) {
      _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
    } else {
      try fileManager.moveItem(at: temporary, to: destination)
    }
    return outputHasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  private static func project(
    _ spec: AgentIOSObsidianProjectionSpec,
    canWrite: Bool,
    root: URL,
    stateStore: AgentIOSObsidianStateStore
  ) throws -> AgentIOSObsidianProjectionStep {
    let indexed = stateStore.index(sourceKey: spec.sourceKey) ?? adoptLegacyIndex(
      spec: spec,
      root: root,
      stateStore: stateStore
    )
    if indexed?.userModified == true || indexed?.sourceRevision == spec.sourceRevision {
      return .unchanged
    }
    guard canWrite else { return .deferred }
    let relativePath = indexed?.relativePath.ifBlank(spec.relativePath) ?? spec.relativePath
    let fileURL = root.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true,
      attributes: nil
    )
    let generatedHash: String
    if let writeContent = spec.writeContent {
      guard let hash = try writeContent(fileURL) else { return .unchanged }
      generatedHash = hash
    } else {
      let content = try spec.content()
      guard !content.isEmpty else { return .unchanged }
      try content.write(to: fileURL, atomically: true, encoding: .utf8)
      generatedHash = sha256(content)
    }
    stateStore.saveIndex(.init(
      sourceKey: spec.sourceKey,
      relativePath: relativePath,
      sourceRevision: spec.sourceRevision,
      generatedHash: generatedHash,
      lastModifiedMillis: modifiedMillis(fileURL),
      userModified: false
    ))
    return .written
  }

  private static func otherProjectionSpecs(appStore: GalaxySSIStore) -> [AgentIOSObsidianProjectionSpec] {
    var specs: [AgentIOSObsidianProjectionSpec] = []

    for installation in UserDefaultsAgentSkillStore().list() {
      let manifest = installation.manifest
      let sourceKey = "skill:\(manifest.id):\(manifest.version)"
      let revision = GlobalAgentText.stableKey(sourceKey, String(installation.updatedAtMillis), manifest.instructions)
      specs.append(.init(
        sourceKey: sourceKey,
        relativePath: "30 Skills/\(fileName(manifest.name, sourceKey: sourceKey))",
        sourceRevision: revision
      ) {
        let steps = manifest.steps.enumerated().map { "\($0.offset + 1). `\($0.element.toolId)`" }.joined(separator: "\n")
        let body = [manifest.description, manifest.instructions, steps.isEmpty ? "" : "## Steps\n\(steps)"]
          .filter { !$0.isEmpty }
          .joined(separator: "\n\n")
        return note(
          sourceKey: sourceKey,
          type: "skill",
          title: manifest.name,
          source: manifest.source,
          updatedAtMillis: installation.updatedAtMillis,
          tags: ["skill"],
          body: body
        )
      })
    }

    let plans = appStore.agentMemorySnapshot().activeItems.filter {
      $0.kind == .task && !$0.isExpired()
    }
    if !plans.isEmpty {
      let revision = GlobalAgentText.stableKey(plans.map { "\($0.id):\($0.version)" }.sorted().joined(separator: "|"))
      specs.append(.init(sourceKey: "plans:current", relativePath: "50 Plans/GalaxySSI plans.md", sourceRevision: revision) {
        note(
          sourceKey: "plans:current",
          type: "plan",
          title: "GalaxySSI plans",
          source: "GalaxySSI memory",
          updatedAtMillis: plans.map(\.timestampMillis).max() ?? 0,
          tags: ["plan"],
          body: plans.map { "- [ ] \($0.value)" }.joined(separator: "\n")
        )
      })
    }

    let insights = appStore.globalProactiveMessages.suffix(100)
    if !insights.isEmpty {
      let revision = GlobalAgentText.stableKey(insights.map { "\($0.id):\($0.status.rawValue):\($0.viewedAtMillis)" }.joined(separator: "|"))
      specs.append(.init(sourceKey: "insights:current", relativePath: "40 Insights/GalaxySSI insights.md", sourceRevision: revision) {
        note(
          sourceKey: "insights:current",
          type: "insight",
          title: "GalaxySSI insights",
          source: "GalaxySSI proactive cognition",
          updatedAtMillis: insights.map(\.createdAtMillis).max() ?? 0,
          tags: ["insight"],
          body: insights.map { "## \($0.title)\n\($0.content)" }.joined(separator: "\n\n")
        )
      })
    }

    let allMessages = appStore.contacts.flatMap { appStore.messages(for: $0.id) }
    for conversation in appStore.agentSessions(includeArchived: true) where !conversation.privateMode && !conversation.trackingPaused {
      let messages = allMessages.filter { $0.conversationId == conversation.id && !$0.isSystem }
      let sourceKey = "agent-conversation:\(conversation.id)"
      let revision = GlobalAgentText.stableKey(
        String(conversation.updatedAt),
        messages.last?.id.uuidString ?? "",
        String(messages.count)
      )
      specs.append(.init(
        sourceKey: sourceKey,
        relativePath: "70 Agent Conversations/\(fileName(conversation.title, sourceKey: sourceKey))",
        sourceRevision: revision
      ) {
        let body = messages.map { message in
          let role = message.isMine ? "You" : "GalaxySSI"
          return "### \(role)\n\(AgentIOSObsidianProjectionPrivacyPolicy.transcriptText(message.content))"
        }.joined(separator: "\n\n")
        return note(
          sourceKey: sourceKey,
          type: "agent_conversation",
          title: conversation.title,
          source: "GalaxySSI Agent",
          updatedAtMillis: conversation.updatedAt,
          tags: ["agent-conversation"],
          body: body
        )
      })
    }
    return specs.sorted { $0.sourceKey < $1.sourceKey }
  }

  private static func scanUserEdits(root: URL, stateStore: AgentIOSObsidianStateStore) -> Int {
    let index = stateStore.index().filter { !$0.userModified }
    guard !index.isEmpty else { return 0 }
    let start = stateStore.editScanCursor() % index.count
    let selected = (0..<min(maximumEditScans, index.count)).map { index[(start + $0) % index.count] }
    var found = 0
    let pending = stateStore.candidates(status: .pending)
    for var entry in selected {
      let url = root.appendingPathComponent(entry.relativePath)
      guard FileManager.default.fileExists(atPath: url.path),
            modifiedMillis(url) != entry.lastModifiedMillis,
            let data = try? Data(contentsOf: url),
            let content = String(data: data, encoding: .utf8) else { continue }
      let currentHash = sha256(content)
      if currentHash == entry.generatedHash {
        entry.lastModifiedMillis = modifiedMillis(url)
        stateStore.saveIndex(entry)
        continue
      }
      if !pending.contains(where: { $0.sourceKey == entry.sourceKey && sha256($0.content) == currentHash }) {
        stateStore.saveCandidate(.init(
          sourceKey: entry.sourceKey,
          relativePath: entry.relativePath,
          title: url.deletingPathExtension().lastPathComponent,
          content: String(content.prefix(maximumCandidateCharacters))
        ))
        found += 1
      }
      entry.userModified = true
      entry.lastModifiedMillis = modifiedMillis(url)
      stateStore.saveIndex(entry)
    }
    stateStore.saveEditScanCursor((start + selected.count) % index.count)
    return found
  }

  static func knowledgeSourceKey(_ group: AgentKnowledgeSourceGroup) -> String {
    let identity = group.localItemId.isEmpty
      ? "source\0\(group.source)"
      : "item\0\(group.localItemId)"
    return "knowledge:v2:\(sha256(identity))"
  }

  private static func adoptLegacyIndex(
    spec: AgentIOSObsidianProjectionSpec,
    root: URL,
    stateStore: AgentIOSObsidianStateStore
  ) -> AgentIOSObsidianProjectionIndexEntry? {
    guard !spec.legacySourceKey.isEmpty, !spec.exactSource.isEmpty,
          var legacy = stateStore.index(sourceKey: spec.legacySourceKey),
          !legacy.relativePath.isEmpty else { return nil }
    let segments = legacy.relativePath.split(separator: "/").map(String.init)
    guard !segments.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { return nil }
    let url = root.appendingPathComponent(legacy.relativePath)
    guard let content = try? String(contentsOf: url, encoding: .utf8),
          frontMatterValue("galaxyssi_id", in: content) == spec.legacySourceKey,
          frontMatterValue("source", in: content) == spec.exactSource,
          content.contains("managed_by: galaxyssi") else { return nil }
    let actualHash = sha256(content)
    if !legacy.userModified && actualHash != legacy.generatedHash { legacy.userModified = true }
    legacy.sourceKey = spec.sourceKey
    legacy.sourceRevision = legacy.userModified ? legacy.sourceRevision : spec.sourceRevision
    stateStore.saveIndex(legacy)
    stateStore.removeIndex(sourceKey: spec.legacySourceKey)
    return legacy
  }

  private static func frontMatterValue(_ name: String, in content: String) -> String? {
    guard content.hasPrefix("---\n"), let end = content.range(of: "\n---\n", range: content.index(content.startIndex, offsetBy: 4)..<content.endIndex) else {
      return nil
    }
    let prefix = String(content[content.index(content.startIndex, offsetBy: 4)..<end.lowerBound])
    let marker = "\(name):"
    guard let line = prefix.split(separator: "\n").map(String.init).first(where: { $0.hasPrefix(marker) }) else {
      return nil
    }
    let value = line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
    guard value.count >= 2, value.first == "\"", value.last == "\"" else { return nil }
    return String(value.dropFirst().dropLast())
      .replacingOccurrences(of: "\\\"", with: "\"")
      .replacingOccurrences(of: "\\\\", with: "\\")
  }

  private static func fileName(_ title: String, sourceKey: String) -> String {
    let safeTitle = AgentIOSObsidianProjectionPrivacyPolicy.safeMetadata(title) ? title : ""
    let clean = safeTitle
      .replacingOccurrences(of: #"[\\/:*?\"<>|]"#, with: " ", options: .regularExpression)
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
    let bounded = String(clean.prefix(80)).ifBlank("GalaxySSI")
    return "\(bounded)-\(GlobalAgentText.stableKey(sourceKey).prefix(8)).md"
  }

  private static func stripFrontMatter(_ value: String) -> String {
    guard value.hasPrefix("---"),
          let range = value.range(of: "\n---", range: value.index(value.startIndex, offsetBy: 3)..<value.endIndex) else {
      return value
    }
    return String(value[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func yaml(_ value: String) -> String {
    String(value.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .prefix(1_000))
  }

  private static func isoDate(_ millis: Int64) -> String {
    let formatter = ISO8601DateFormatter()
    return formatter.string(from: Date(timeIntervalSince1970: Double(max(millis, 1)) / 1_000))
  }

  private static func sha256(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  private static func modifiedMillis(_ url: URL) -> Int64 {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
          let date = attributes[.modificationDate] as? Date else { return 0 }
    return Int64((date.timeIntervalSince1970 * 1_000).rounded())
  }

  private static let maximumEditScans = 8
  private static let maximumCandidateCharacters = 256_000
}
