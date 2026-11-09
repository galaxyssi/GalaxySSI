import CryptoKit
import Foundation
import os

struct AgentDesktopEvidenceQueryTrace {
  enum Stage: String {
    case publishStarted = "publish_started", publishAccepted = "publish_accepted", publishRejected = "publish_rejected"
    case responseReceived = "response_received", responseLate = "response_late", timedOut = "timed_out"
    case routeMismatch = "paired_route_mismatch", invalidResponse = "invalid_response"
    case indexValidated = "index_validated", indexRejected = "index_rejected"
    case pageStaged = "page_staged", pageNotStaged = "page_not_staged"
    case sliceComplete = "slice_complete", sliceYielded = "slice_yielded", sliceDeferred = "slice_deferred"
    case sliceWait = "slice_wait"
  }

  private static let logger = Logger(subsystem: "com.galaxyssi.chat.ios", category: "desktop-evidence")
  static var now: Int64 { Int64(ProcessInfo.processInfo.systemUptime * 1_000) }

  static func token(_ nonce: String) -> String {
    guard (1...128).contains(nonce.utf8.count) else { return "unavailable" }
    return SHA256.hash(data: Data(nonce.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
  }

  static func record(_ stage: Stage, nonce: String, started: Int64) {
    let correlation = token(nonce)
    let elapsed = max(0, now - started)
    logger.info("Evidence query rpc=\(correlation, privacy: .public) stage=\(stage.rawValue, privacy: .public) elapsed_ms=\(elapsed, privacy: .public)")
  }
}

struct AgentDesktopEvidenceReply {
  let request: AgentDesktopToolEvidenceWire.Request
  let payload: AgentMcpJSONObject
}

// Both transports call this from their existing MainActor-owned request/receive paths.
struct AgentDesktopEvidenceQueries<Transport: Equatable> {
  struct Ticket {
    let request: AgentDesktopToolEvidenceWire.Request
    let payload: AgentMcpJSONObject
    let stream: AsyncStream<AgentDesktopEvidenceReply>
    fileprivate let lease: UUID
  }

  enum Begin { case waiting(Ticket), retained(AgentDesktopEvidenceReply) }
  enum Receive: Equatable { case unknown, rejected, discarded, duplicate, active, late }

  private struct Entry {
    let request: AgentDesktopToolEvidenceWire.Request
    let payload: AgentMcpJSONObject
    let selector: Data
    let transport: Transport
    let lease: UUID
    let started: Int64
    var signal: AsyncStream<AgentDesktopEvidenceReply>.Continuation?
    var expires: Int64?
    var response: AgentMcpJSONObject?
    var bytes = 0
    var delivered = false
    var successor: UUID?
  }

  private let lateLimit: Int
  private let byteLimit: Int
  private let retention: Int64
  private var entries: [String: Entry] = [:]

  init(lateLimit: Int = 128, byteLimit: Int = 2 * 1_024 * 1_024, retention: Int64 = 120_000) {
    self.lateLimit = max(0, lateLimit)
    self.byteLimit = max(0, byteLimit)
    self.retention = max(0, retention)
  }

  func started(_ nonce: String) -> Int64? { entries[nonce]?.started }

  mutating func begin(_ request: AgentDesktopToolEvidenceWire.Request, payload: AgentMcpJSONObject,
      transport: Transport, now: Int64) -> Begin? {
    prune(now)
    guard payload["request_id"] == .string(request.nonce), entries[request.nonce] == nil,
          ["index", "page"].contains(payload.string("mode")) else { return nil }
    let selector = Data(AgentMcpJSONCodec.stringify(payload.filter { $0.key != "request_id" }).utf8)
    let retained = entries.values.filter {
      $0.expires != nil && $0.transport == transport && $0.selector == selector &&
        $0.request.binding == request.binding && $0.request.generation == request.generation
    }
    if let cached = retained.first(where: { $0.response != nil }), let payload = cached.response {
      entries.removeValue(forKey: cached.request.nonce)
      return .retained(.init(request: cached.request, payload: payload))
    }
    guard entries.values.filter({ $0.expires == nil }).count < 2 else { return nil }
    var signal: AsyncStream<AgentDesktopEvidenceReply>.Continuation?
    let stream = AsyncStream<AgentDesktopEvidenceReply>(bufferingPolicy: .bufferingNewest(1)) { signal = $0 }
    guard let signal else { return nil }
    let lease = UUID()
    let activeLeases = Set(entries.values.filter { $0.expires == nil }.map(\.lease))
    // Desktop deduplicates transport messages by nonce, so a retry publishes a fresh nonce.
    for previous in retained where previous.successor.map({ !activeLeases.contains($0) }) ?? true {
      entries[previous.request.nonce]?.successor = lease
    }
    entries[request.nonce] = Entry(request: request, payload: payload, selector: selector, transport: transport,
      lease: lease, started: now, signal: signal)
    return .waiting(Ticket(request: request, payload: payload, stream: stream, lease: lease))
  }

  mutating func receive(_ response: AgentMcpJSONObject, transport: Transport, desktop: String, now: Int64) -> Receive {
    prune(now)
    let nonce = response.string("request_id")
    guard var entry = entries[nonce] else { return .unknown }
    let mode = entry.payload.string("mode"), status = response.string("status")
    guard entry.transport == transport, ["ready", "unavailable"].contains(status),
          entry.request.matchesTransportResponse(response, authenticatedDesktopId: desktop, mode: mode),
          mode != "page" || status != "ready" ||
            ["evidence_id", "sha256", "page_index"].allSatisfy({ response[$0] == entry.payload[$0] })
    else { return .rejected }
    guard !entry.delivered else { return .duplicate }
    entry.delivered = true
    let reply = AgentDesktopEvidenceReply(request: entry.request, payload: response)
    if let signal = entry.signal {
      entries[nonce] = entry
      signal.yield(reply)
      signal.finish()
      return .active
    }
    let bytes = AgentMcpJSONCodec.stringify(response).utf8.count
    guard bytes <= byteLimit else {
      entries.removeValue(forKey: nonce)
      return .discarded
    }
    if let successor = entry.successor,
       var active = entries.values.first(where: { $0.lease == successor && !$0.delivered && $0.signal != nil }),
       let signal = active.signal {
      active.delivered = true
      entries[active.request.nonce] = active
      entries.removeValue(forKey: nonce)
      signal.yield(reply)
      signal.finish()
      return .late
    }
    entry.response = response
    entry.bytes = bytes
    entries[nonce] = entry
    bound()
    return entries[nonce] == nil ? .discarded : .late
  }

  mutating func timeout(_ ticket: Ticket, now: Int64) {
    let nonce = ticket.request.nonce
    guard var entry = entries[nonce], entry.lease == ticket.lease, !entry.delivered,
          let signal = entry.signal else { return }
    entry.signal = nil
    entry.expires = now.addingReportingOverflow(retention).overflow ? Int64.max : now + retention
    entries[nonce] = entry
    prune(now)
    bound()
    signal.finish()
  }

  mutating func finish(_ ticket: Ticket, retainAfterTimeout: Bool) {
    let nonce = ticket.request.nonce
    if let entry = entries[nonce], entry.lease == ticket.lease {
      if retainAfterTimeout, entry.expires != nil { return }
      entries.removeValue(forKey: nonce)
      entry.signal?.finish()
    }
    if !retainAfterTimeout {
      entries = entries.filter { $0.value.successor != ticket.lease }
    }
  }

  mutating func removeAll() {
    let saved = entries
    entries.removeAll()
    for entry in saved.values { entry.signal?.finish() }
  }

  private mutating func prune(_ now: Int64) {
    entries = entries.filter { $0.value.expires.map { now < $0 } ?? true }
  }

  private mutating func bound() {
    let late = entries.values.filter { $0.expires != nil }.sorted {
      ($0.expires ?? 0, $0.request.nonce) < ($1.expires ?? 0, $1.request.nonce)
    }
    var count = late.count
    var bytes = late.reduce(0) { $0 + $1.bytes }
    for entry in late where count > lateLimit || bytes > byteLimit {
      entries.removeValue(forKey: entry.request.nonce)
      count -= 1
      bytes -= entry.bytes
    }
  }
}

struct AgentDesktopEvidenceRecoverySlice {
  private var remainingQueries = 4
  private var exceededBudget = false

  mutating func claimQuery() -> Bool {
    guard remainingQueries > 0 else {
      exceededBudget = true
      return false
    }
    remainingQueries -= 1
    return true
  }

  func outcome(archiveFinal: Bool, isCancelled: Bool) -> AgentDesktopEvidenceQueryTrace.Stage {
    if archiveFinal { return .sliceComplete }
    return exceededBudget && !isCancelled ? .sliceYielded : .sliceDeferred
  }
}

enum AgentDesktopToolEvidenceWire {
  static let contract = "galaxyssi.desktop-tool-evidence/1"
  static let maximumPageBytes = 16 * 1_024
  static let maximumOriginalBytes = 8 * 1_024 * 1_024

  enum RecordedEvent: String, CaseIterable {
    case commandExecution, fileChange, mcpToolCall, dynamicToolCall, webSearch

    var tool: String { "codex." + rawValue }

    // File changes are archived, but the iOS acceptance gate requires returned tool output.
    static let acceptanceTools = allCases.filter { $0 != .fileChange }.map(\.tool)
  }

  struct ArchiveReceipt: Codable, Equatable {
    let archiveId: String
    let desktopId: String
    let evidenceId: String
    let sha256: String
    let generation: Int64
    let totalBytes: Int
    let pageCount: Int
  }

  struct AcceptanceArchive: Codable, Equatable {
    let receipt: ArchiveReceipt
    let binding: AgentDesktopReplyBinding
    let itemType: String
    let tool: String
    let returnedOutput: Bool
    var recordedTool: String? { RecordedEvent(rawValue: itemType)?.tool }

    init?(receipt: ArchiveReceipt, binding: AgentDesktopReplyBinding, original: Data) {
      guard let root = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: original),
            let item = root["observation"]?.objectValue?["item"]?.objectValue else { return nil }
      let itemType = item.string("type")
      let tool = item.string("tool").ifBlank(itemType)
      let toolName = tool.lowercased()
      let failed = ["failed", "error", "cancelled", "canceled", "declined"].contains(item.string("status").lowercased()) ||
        AgentCollaborationCloudToolEvidence.reportsFailure(AgentMcpJSONCodec.stringify(item)) ||
        item["result"]?.objectValue?["isError"] == .bool(true)
      let hasOutput: Bool
      switch RecordedEvent(rawValue: itemType) {
      case .commandExecution:
        hasOutput = item["exitCode"] == .int(0) && !item.string("aggregatedOutput").isBlank
      case .mcpToolCall:
        hasOutput = item["result"]?.objectValue?.isEmpty == false
      case .dynamicToolCall:
        hasOutput = item["success"] == .bool(true) && item["contentItems"]?.arrayValue?.isEmpty == false
      case .webSearch:
        hasOutput = item["results"]?.arrayValue?.isEmpty == false
      default:
        hasOutput = false
      }
      self.receipt = receipt
      self.binding = binding
      self.itemType = itemType
      self.tool = tool
      self.returnedOutput = !failed && hasOutput && !toolName.contains("collaboration") && !toolName.contains("recall")
    }
  }

  struct FrozenRead: Codable {
    let evidenceId: String
    let sha256: String
    let totalBytes: Int
    var hostReadCoverage: AgentMcpJSONObject? = nil
  }

  struct ImportCursor: Codable, Equatable {
    var sequence: Int64 = 0
    var archiveFinal = false
    var skippedOversized: Int64? = nil
    var skippedCountComplete: Bool? = nil

    func advancing(to next: Int64, final: Bool, skipped: Int) -> Self? {
      guard !archiveFinal, sequence >= 0, next >= sequence, next <= 9_007_199_254_740_991,
            next > sequence || final, (0...20).contains(skipped), Int64(skipped) <= next - sequence,
            (0...sequence).contains(skippedOversized ?? 0) else { return nil }
      return .init(sequence: next, archiveFinal: final, skippedOversized: (skippedOversized ?? 0) + Int64(skipped),
        skippedCountComplete: skippedCountComplete ?? (sequence == 0))
    }
  }

  static func coverageKey(run: String, turn: String, member: String, source: String, generation: Int64) -> String {
    "desktop-import-coverage:" + AgentMcpJSONCodec.sha256(["run": .string(run), "turn": .string(turn),
      "member": .string(member), "source": .string(source), "generation": .int(generation)])
  }

  struct ImportJob: Codable {
    static let keyPrefix = "desktop-evidence-job:"
    let binding: AgentDesktopReplyBinding
    let generation: Int64
    let profileIdentity: String

    var key: String {
      var fields = binding.fields.mapValues(AgentMcpJSONValue.string)
      fields["desktop_id"] = .string(binding.desktopId)
      fields["execution_generation"] = .int(generation)
      fields["profile_identity"] = .string(profileIdentity)
      return Self.keyPrefix + AgentMcpJSONCodec.sha256(fields)
    }
  }

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
            RecordedEvent(rawValue: itemType) != nil,
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

    var skippedOversized: Int { entries.filter { !$0.canImport }.count }
  }

  struct Request {
    let binding: AgentDesktopReplyBinding
    let generation: Int64
    let nonce: String

    var archiveScope: AgentMcpJSONObject {
      var fields = binding.fields.mapValues(AgentMcpJSONValue.string)
      fields["desktop_id"] = .string(binding.desktopId)
      fields["execution_generation"] = .int(generation)
      return fields
    }

    func archiveId(_ descriptor: Descriptor) -> String {
      var fields = archiveScope
      fields["evidence_id"] = .string(descriptor.evidenceId)
      return AgentMcpJSONCodec.sha256(fields)
    }

    func stagedPageKey(_ descriptor: Descriptor) -> String {
      "desktop-evidence-stage:" + archiveId(descriptor) + ":" + descriptor.sha256
    }

    var cursorKey: String { "desktop-evidence-cursor:" + AgentMcpJSONCodec.sha256(archiveScope) }
    var pendingIndexKey: String { "desktop-evidence-index:" + AgentMcpJSONCodec.sha256(archiveScope) }

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
      matchesTransportResponse(response, authenticatedDesktopId: authenticatedDesktopId, mode: mode) &&
        response.string("status") == "ready"
    }

    func matchesTransportResponse(_ response: AgentMcpJSONObject, authenticatedDesktopId: String, mode: String) -> Bool {
      ["index", "page"].contains(mode) && authenticatedDesktopId == binding.desktopId &&
        response.string("type") == "agent_task_evidence" &&
        response.string("contract") == AgentDesktopToolEvidenceWire.contract &&
        response.string("mode") == mode &&
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
            case .int(let nextSequence)? = response["next_sequence"],
            let raw = response["entries"]?.arrayValue, raw.count <= 20 else { return nil }
      let archiveFinal: Bool
      switch response["archive_final"] {
      case nil: archiveFinal = false
      case .bool(let value)?: archiveFinal = value
      default: return nil
      }
      var entries: [Descriptor] = []
      var byId: [String: Descriptor] = [:]
      var cursor = sequence
      for value in raw {
        guard let object = value.objectValue, let item = Descriptor(object),
              item.sequence > cursor, byId[item.evidenceId] == nil,
              object["phone_import"] == nil || object["phone_import"] == .bool(true) else { return nil }
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
            let item = observation["item"]?.objectValue,
            item.string("type") == descriptor.itemType,
            !(descriptor.itemType == "dynamicToolCall" && item.string("tool") == "collaboration_recall")
      else { return nil }
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
               now: Int64, commitManifest: (AgentDesktopResultManifest) -> Bool = { _ in true }) -> AgentDesktopResultManifest? {
    let nonce = payload.string("request_id")
    guard let query = queries[nonce], query.binding == record.binding, query.generation == record.generation,
          now >= query.startedAt, now - query.startedAt <= 120_000,
          let manifest = savePage(payload, record: record, nonce: nonce, page: query.page),
          commitManifest(manifest) else { return nil }
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
          sequence >= record.sequence ||
            (record.acceptedReply ?? record.pinnedTeamReply)?.receipt.resultSHA256 == manifest.digest else { return nil }
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
