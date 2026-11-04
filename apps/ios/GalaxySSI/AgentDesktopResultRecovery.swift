import CryptoKit
import Foundation

enum AgentDesktopToolEvidenceWire {
  static let contract = "galaxyssi.desktop-tool-evidence/1"
  static let maximumPageBytes = 16 * 1_024
  static let maximumOriginalBytes = 8 * 1_024 * 1_024

  struct Descriptor: Equatable {
    let evidenceId: String
    let sha256: String
    let sequence: Int64
    let totalBytes: Int
    let pageCount: Int
    let itemType: String
    var canImport: Bool { totalBytes <= AgentDesktopToolEvidenceWire.maximumOriginalBytes }

    init?(_ object: AgentMcpJSONObject) {
      evidenceId = object.string("evidence_id")
      sha256 = object.string("sha256")
      sequence = object.int64("sequence")
      totalBytes = Int(clamping: object.int64("total_bytes"))
      pageCount = Int(clamping: object.int64("page_count"))
      itemType = object.string("item_type")
      guard AgentDesktopToolEvidenceWire.isDigest(evidenceId), AgentDesktopToolEvidenceWire.isDigest(sha256),
            (1...9_007_199_254_740_991).contains(sequence),
            totalBytes > 0,
            pageCount == (totalBytes - 1) / AgentDesktopToolEvidenceWire.maximumPageBytes + 1,
            ["commandExecution", "fileChange", "mcpToolCall", "dynamicToolCall", "webSearch"].contains(itemType),
            object.string("trust") == "execution_observed_not_claim_verified",
            object.string("coverage") == "provider_payload_as_received" else { return nil }
    }
  }

  struct IndexPage {
    let entries: [Descriptor]
    let nextSequence: Int64
    let hasMore: Bool
    let archiveFinal: Bool
    let inlineOriginals: [String: Data]
  }

  struct Request {
    let binding: AgentDesktopReplyBinding
    let generation: Int64
    let nonce: String

    init?(binding: AgentDesktopReplyBinding, generation: Int64, nonce: String) {
      guard binding.isValid, binding.teamSource != nil, binding.agentId == "codex",
            AgentRemoteOutcomePolicy.validGeneration(generation),
            !nonce.isBlank, nonce.utf8.count <= 128 else { return nil }
      self.binding = binding
      self.generation = generation
      self.nonce = nonce
    }

    func pageRequest(_ descriptor: Descriptor, index: Int) -> AgentMcpJSONObject? {
      guard descriptor.canImport, (0..<descriptor.pageCount).contains(index) else { return nil }
      var payload = request(mode: "page")
      payload["evidence_id"] = .string(descriptor.evidenceId)
      payload["sha256"] = .string(descriptor.sha256)
      payload["page_index"] = .int(Int64(index))
      return payload
    }

    func indexRequest(after sequence: Int64, inlineBytes: Int = 0) -> AgentMcpJSONObject? {
      guard (0...9_007_199_254_740_991).contains(sequence),
            (0...AgentDesktopToolEvidenceWire.maximumPageBytes).contains(inlineBytes) else { return nil }
      var payload = request(mode: "index")
      payload["after_sequence"] = .int(sequence)
      if inlineBytes > 0 { payload["inline_page_bytes"] = .int(Int64(inlineBytes)) }
      return payload
    }

    private func request(mode: String) -> AgentMcpJSONObject {
      var payload = binding.fields.mapValues(AgentMcpJSONValue.string)
      payload["type"] = .string("agent_task_evidence_request")
      payload["contract"] = .string(AgentDesktopToolEvidenceWire.contract)
      payload["mode"] = .string(mode)
      payload["request_id"] = .string(nonce)
      payload["execution_generation"] = .int(generation)
      return payload
    }

    func verifyPage(_ response: AgentMcpJSONObject, authenticatedDesktopId: String,
                    descriptor: Descriptor, index: Int) -> Data? {
      guard matches(response, authenticatedDesktopId: authenticatedDesktopId, mode: "page") else { return nil }
      return verifyPageBody(response, descriptor: descriptor, index: index)
    }

    private func matches(_ response: AgentMcpJSONObject, authenticatedDesktopId: String, mode: String) -> Bool {
      authenticatedDesktopId == binding.desktopId &&
        response.string("type") == "agent_task_evidence" &&
        response.string("contract") == AgentDesktopToolEvidenceWire.contract &&
        response.string("mode") == mode && response.string("status") == "ready" &&
        response.string("request_id") == nonce && response["execution_generation"] == .int(generation) &&
        binding.fields.allSatisfy { response[$0.key] == .string($0.value) }
    }

    func verifyIndex(_ response: AgentMcpJSONObject, authenticatedDesktopId: String,
                     after sequence: Int64, inlineBytes: Int = 0) -> IndexPage? {
      guard indexRequest(after: sequence, inlineBytes: inlineBytes) != nil,
            matches(response, authenticatedDesktopId: authenticatedDesktopId, mode: "index"),
            response["provider_history_complete"] == .bool(false),
            response.string("coverage") == "observed_completed_items_only",
            response.string("projection") == "external_execution_observations",
            case .bool(let hasMore)? = response["has_more"],
            case .bool(let archiveFinal)? = response["archive_final"],
            case .int(let nextSequence)? = response["next_sequence"],
            let raw = response["entries"]?.arrayValue, raw.count <= 20 else { return nil }
      var entries: [Descriptor] = []
      var byId: [String: Descriptor] = [:]
      var cursor = sequence
      for value in raw {
        guard let object = value.objectValue, let item = Descriptor(object),
              item.sequence > cursor, byId[item.evidenceId] == nil,
              object["phone_import"] != .bool(false) else { return nil }
        cursor = item.sequence
        byId[item.evidenceId] = item
        entries.append(item)
      }
      guard cursor == nextSequence, !hasMore || !entries.isEmpty else { return nil }
      let inline: [AgentMcpJSONValue]
      if let value = response["inline_pages"] {
        guard let pages = value.arrayValue, pages.count <= entries.count else { return nil }
        inline = pages
      } else { inline = [] }
      var remaining = inlineBytes
      var originals: [String: Data] = [:]
      for value in inline {
        guard let page = value.objectValue, let descriptor = byId[page.string("evidence_id")],
              descriptor.pageCount == 1, descriptor.totalBytes <= remaining,
              originals[descriptor.evidenceId] == nil,
              let bytes = verifyPageBody(page, descriptor: descriptor, index: 0),
              let original = verifyOriginal([bytes], descriptor: descriptor) else { return nil }
        originals[descriptor.evidenceId] = original
        remaining -= bytes.count
      }
      return IndexPage(entries: entries, nextSequence: nextSequence, hasMore: hasMore,
        archiveFinal: archiveFinal, inlineOriginals: originals)
    }

    private func verifyPageBody(_ response: AgentMcpJSONObject, descriptor: Descriptor, index: Int) -> Data? {
      guard descriptor.canImport, response.string("status") == "ready",
            Descriptor(response) == descriptor,
            (0..<descriptor.pageCount).contains(index), response["page_index"] == .int(Int64(index)) else { return nil }
      let encoded = response.string("data_b64")
      let size = AgentDesktopToolEvidenceWire.maximumPageBytes
      let expectedBytes = min(size, descriptor.totalBytes - index * size)
      guard encoded.utf8.count <= ((expectedBytes + 2) / 3) * 4,
            let bytes = Data(base64Encoded: encoded), bytes.count == expectedBytes,
            AgentDesktopToolEvidenceWire.digest(bytes) == response.string("page_sha256") else { return nil }
      return bytes
    }

    func verifyOriginal(_ pages: [Data], descriptor: Descriptor) -> Data? {
      guard descriptor.canImport, pages.count == descriptor.pageCount else { return nil }
      var body = Data()
      body.reserveCapacity(descriptor.totalBytes)
      let size = AgentDesktopToolEvidenceWire.maximumPageBytes
      for (index, page) in pages.enumerated() {
        guard page.count == min(size, descriptor.totalBytes - index * size) else { return nil }
        body.append(page)
      }
      guard body.count == descriptor.totalBytes, AgentDesktopToolEvidenceWire.digest(body) == descriptor.sha256,
            let original = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: body),
            original.string("contract") == AgentDesktopToolEvidenceWire.contract,
            original["execution_generation"] == .int(generation),
            binding.fields.allSatisfy({ original[$0.key] == .string($0.value) }),
            original.string("trust") == "execution_observed_not_claim_verified",
            original.string("coverage") == "provider_payload_as_received",
            let observation = original["observation"]?.objectValue,
            observation.string("provider") == "codex",
            !observation.string("thread_id").isBlank, !observation.string("turn_id").isBlank,
            observation["item"]?.objectValue?.string("type") == descriptor.itemType else { return nil }
      return body
    }
  }

  private static func isDigest(_ value: String) -> Bool {
    value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }

  private static func digest(_ bytes: Data) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }
}

struct AgentDesktopResultManifest: Codable, Equatable {
  var digest: String
  var pageCount: Int
  var totalBytes: Int

  var isValid: Bool {
    digest.count == 64 && digest.allSatisfy { $0.isHexDigit && !$0.isUppercase } &&
      totalBytes > 0 && totalBytes <= AgentResultPageCheckpointStore.maximumResultBytes &&
      pageCount == (totalBytes + AgentResultPageCheckpointStore.maximumPageBytes - 1) / AgentResultPageCheckpointStore.maximumPageBytes
  }
}

extension AgentDesktopReplyBinding {
  func checkpointIdentity(generation: Int64) -> AgentResultCheckpointIdentity {
    AgentResultCheckpointIdentity(desktopId: desktopId, clientRouteId: identity.clientRouteId,
      conversationId: identity.conversationId, taskId: identity.taskId, turnId: identity.turnId,
      contactId: contactId, sourceMessageId: sourceIdentity, agentId: agentId, executionGeneration: generation)
  }
}

@MainActor
final class AgentDesktopResultRecovery {
  private struct Query {
    var binding: AgentDesktopReplyBinding
    var generation: Int64
    var page: Int
    var startedAt: Int64
  }
  let pages: AgentResultPageCheckpointStore
  let receipts: AgentResultReceiptJournal
  private var queries: [String: Query] = [:]

  init(pages: AgentResultPageCheckpointStore, receipts: AgentResultReceiptJournal) {
    self.pages = pages
    self.receipts = receipts
  }

  convenience init(ownerId: String, secrets: GalaxySSISecretStore) {
    let root = Self.root(ownerId: ownerId)
    self.init(pages: AgentResultPageCheckpointStore(fileURL: root.appendingPathComponent("pages.sqlite3"), secrets: secrets),
      receipts: AgentResultReceiptJournal(fileURL: root.appendingPathComponent("receipts.sqlite3"), secrets: secrets))
  }

  private static func root(ownerId: String) -> URL {
    let owner = Self.sha256(Data(ownerId.utf8))
    return AgentResultPageCheckpointStore.defaultFileURL().deletingLastPathComponent()
      .appendingPathComponent("desktop-\(owner)", isDirectory: true)
  }

  func destroyAllData() {
    queries.removeAll()
    pages.destroyAllData()
    receipts.destroyAllData()
  }

  func expectedBinding(_ payload: [String: Any]) -> AgentDesktopReplyBinding? {
    queries[payload.string("request_id")]?.binding
  }

  func request(_ record: AgentDesktopReplyRecoveryRecord, now: Int64) -> [String: Any]? {
    guard record.generation > 0, AgentDesktopReplyRecovery.terminalStatuses.contains(record.status) else { return nil }
    queries = queries.filter { now < $0.value.startedAt || now - $0.value.startedAt <= 120_000 }
    guard queries.count < 128 else { return nil }
    let page: Int
    if let manifest = record.resultManifest {
      guard manifest.isValid, let missing = pages.missingPageIndices(
        identity: record.binding.checkpointIdentity(generation: record.generation), resultSHA256: manifest.digest,
        pageCount: manifest.pageCount, totalBytes: manifest.totalBytes).first else { return nil }
      page = missing
    } else { page = 0 }
    guard !queries.values.contains(where: { $0.binding == record.binding && $0.generation == record.generation &&
      $0.page == page && now >= $0.startedAt && now - $0.startedAt < 8_000 }) else { return nil }
    let nonce = UUID().uuidString
    queries[nonce] = Query(binding: record.binding, generation: record.generation, page: page, startedAt: now)
    var payload: [String: Any] = record.binding.fields
    payload["type"] = "agent_task_result_page_request"
    payload["request_id"] = nonce
    payload["desktop_id"] = record.binding.desktopId
    payload["execution_generation"] = record.generation
    payload["page_index"] = page
    if let manifest = record.resultManifest { payload["sha256"] = manifest.digest }
    return payload
  }

  func receive(_ payload: [String: Any], record: AgentDesktopReplyRecoveryRecord,
               now: Int64) -> AgentDesktopResultManifest? {
    let nonce = payload.string("request_id")
    guard let query = queries[nonce], query.binding == record.binding, query.generation == record.generation,
          now >= query.startedAt, now - query.startedAt <= 120_000,
          let manifest = savePage(payload, record: record, nonce: nonce, page: query.page) else { return nil }
    queries.removeValue(forKey: nonce)
    return manifest
  }

  func receiveInline(_ payload: [String: Any], record: AgentDesktopReplyRecoveryRecord,
                     queryNonce: String) -> AgentDesktopResultManifest? {
    savePage(payload, record: record, nonce: queryNonce, page: 0)
  }

  private func savePage(_ payload: [String: Any], record: AgentDesktopReplyRecoveryRecord,
                        nonce: String, page: Int) -> AgentDesktopResultManifest? {
    guard record.generation > 0, AgentDesktopReplyRecovery.terminalStatuses.contains(record.status),
          payload.string("type") == "agent_task_result_page", payload.string("status") == "ready",
          payload.string("request_id") == nonce, record.binding.matches(payload),
          payload["desktop_id"] == nil || payload.string("desktop_id") == record.binding.desktopId,
          AgentDesktopReplyRecovery.integer(payload["execution_generation"], minimum: 1) == record.generation,
          AgentDesktopReplyRecovery.integer(payload["page_index"], minimum: 0) == Int64(page),
          let count = AgentDesktopReplyRecovery.integer(payload["page_count"], minimum: 1),
          let total = AgentDesktopReplyRecovery.integer(payload["total_bytes"], minimum: 1),
          total <= Int64(AgentResultPageCheckpointStore.maximumResultBytes),
          let encoded = payload["data_b64"] as? String,
          encoded.count <= ((AgentResultPageCheckpointStore.maximumPageBytes + 2) / 3) * 4,
          let data = Data(base64Encoded: encoded) else { return nil }
    let manifest = AgentDesktopResultManifest(digest: payload.string("sha256"), pageCount: Int(count), totalBytes: Int(total))
    guard manifest.isValid, page < manifest.pageCount,
          record.resultManifest == nil || record.resultManifest == manifest,
          data.count == min(AgentResultPageCheckpointStore.maximumPageBytes,
            manifest.totalBytes - page * AgentResultPageCheckpointStore.maximumPageBytes),
          Self.sha256(data) == payload.string("page_sha256"),
          manifest.pageCount != 1 || Self.sha256(data) == manifest.digest else { return nil }
    let checkpoint = AgentResultPageCheckpoint(identity: record.binding.checkpointIdentity(generation: record.generation),
      pageIndex: page, pageCount: manifest.pageCount, totalBytes: manifest.totalBytes,
      resultSHA256: manifest.digest, pageSHA256: payload.string("page_sha256"), data: data)
    return pages.save(checkpoint) ? manifest : nil
  }

  func assembled(_ record: AgentDesktopReplyRecoveryRecord) -> [String: Any]? {
    guard let manifest = record.resultManifest, manifest.isValid else { return nil }
    let restored = pages.restoredPages(identity: record.binding.checkpointIdentity(generation: record.generation),
      resultSHA256: manifest.digest, pageCount: manifest.pageCount, totalBytes: manifest.totalBytes)
    guard restored.count == manifest.pageCount, restored.enumerated().allSatisfy({ $0.offset == $0.element.pageIndex }) else { return nil }
    var data = Data()
    for page in restored { data.append(page.data) }
    guard data.count == manifest.totalBytes, Self.sha256(data) == manifest.digest,
          var payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          payload.string("type") == "text", record.binding.matches(payload),
          payload.string("task_status") == record.status,
          AgentDesktopReplyRecovery.integer(payload["execution_generation"], minimum: 1) == record.generation,
          let sequence = AgentDesktopReplyRecovery.integer(payload["status_sequence"], minimum: 0),
          sequence >= record.sequence else { return nil }
    payload["desktop_id"] = record.binding.desktopId
    payload["result_recovery"] = ["sha256": manifest.digest]
    if payload.string("message_id").isEmpty { payload["message_id"] = "recovered:\(record.binding.key):\(manifest.digest)" }
    return payload
  }

  func receipt(_ record: AgentDesktopReplyRecoveryRecord) -> AgentResultReceipt? {
    guard let manifest = record.resultManifest, manifest.isValid, record.generation > 0 else { return nil }
    let binding = record.binding
    return AgentResultReceipt(desktopId: binding.desktopId, clientRouteId: binding.identity.clientRouteId,
      conversationId: binding.identity.conversationId, taskId: binding.identity.taskId, turnId: binding.identity.turnId,
      contactId: binding.contactId, sourceMessageId: binding.sourceIdentity, agentId: binding.agentId,
      executionGeneration: record.generation, resultSHA256: manifest.digest)
  }

  func cleanup(_ receipt: AgentResultReceipt) -> Bool {
    guard receipts.isConfirmed(receipt) else { return false }
    let identity = AgentResultCheckpointIdentity(desktopId: receipt.desktopId, clientRouteId: receipt.clientRouteId,
      conversationId: receipt.conversationId, taskId: receipt.taskId, turnId: receipt.turnId,
      contactId: receipt.contactId, sourceMessageId: receipt.sourceMessageId, agentId: receipt.agentId,
      executionGeneration: receipt.executionGeneration)
    guard pages.clear(identity: identity, resultSHA256: receipt.resultSHA256) else { return false }
    return receipts.markCleaned(receipt)
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
