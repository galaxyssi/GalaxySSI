import CryptoKit
import Foundation

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
