import Foundation

enum CloudSearchPageReads {
  struct Attempt {
    let url: String
    let result: AgentNativeToolResult?
    let stopped: String?
    var receipt: AgentMcpJSONObject {
      ["url": .string(url), "source_id": .string(url),
       "operation": .string("fetch"),
       "status": .string(result?.isSuccess == true ? "completed" : "failed"),
       "error_code": .string(stopped ?? result?.error?.code ?? (result?.isSuccess == true ? "" : "page_read_failed"))]
    }
  }
  private final class Collector {
    private let lock = NSLock()
    private var closed = false
    private var values: [Int: Attempt] = [:]
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return closed }
    func store(_ value: Attempt, at index: Int) {
      lock.lock(); defer { lock.unlock() }
      if !closed { values[index] = value }
    }
    func finish(_ urls: [String], reason: String) -> [Attempt] {
      lock.lock(); defer { lock.unlock() }; closed = true
      return urls.enumerated().map { values[$0.offset] ?? Attempt(url: $0.element, result: nil, stopped: reason) }
    }
  }

  static func urls(in output: AgentMcpJSONObject, limit: Int) -> [String] {
    var seen = Set<String>(), urls: [String] = []
    for item in output["evidence_pack"]?.objectValue?["items"]?.arrayValue ?? [] {
      guard urls.count < min(max(limit, 1), 4) else { break }
      guard let raw = item.objectValue?["url"]?.stringValue, raw.utf8.count <= 4_096,
            let parts = URLComponents(string: raw), parts.scheme?.lowercased() == "https",
            !(parts.host ?? "").isEmpty, parts.user == nil, parts.password == nil,
            seen.insert(AgentIOSWebEvidencePack.canonicalURL(raw)).inserted else { continue }
      urls.append(raw)
    }
    return urls
  }

  static func read(_ urls: [String], provider: AgentIOSWebIntelligenceToolProviding,
                   context: AgentNativeToolInvocationContext, budgetMillis: Int64 = 8_000,
                   nowMillis: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) },
                   cancelled: () -> Bool = { Task.isCancelled }) -> [Attempt] {
    let urls = Array(urls.prefix(4)), collector = Collector()
    guard !urls.isEmpty else { return [] }
    if cancelled() { return collector.finish(urls, reason: "page_read_cancelled") }
    let now = nowMillis()
    let budget = min(max(budgetMillis, 0), 8_000)
    let proposed = now.addingReportingOverflow(budget)
    let deadline = min(context.deadlineEpochMillis ?? Int64.max, proposed.overflow ? Int64.max : proposed.partialValue)
    guard deadline > now, budget > 0 else { return collector.finish(urls, reason: "page_read_deadline") }
    let difference = deadline.subtractingReportingOverflow(now)
    let remaining = difference.overflow ? budget : min(budget, difference.partialValue)
    guard remaining >= 1_000 else { return collector.finish(urls, reason: "page_read_insufficient_budget") }
    let waitDeadline = DispatchTime.now() + .milliseconds(Int(remaining))
    let group = DispatchGroup()
    for (index, url) in urls.enumerated() {
      var child = context
      child.invocationId = "\(context.invocationId.prefix(100))-page-\(index)"
      child.idempotencyKey = context.idempotencyKey.map { "\($0.prefix(100))-page-\(index)" }
      child.deadlineEpochMillis = deadline
      let childContext = child
      group.enter()
      DispatchQueue.global(qos: .userInitiated).async {
        defer { group.leave() }
        guard !collector.cancelled else { return }
        do {
          // Registry descriptor caches and audit stores are not shared between workers.
          let registry = try AgentNativeToolRegistry().registerExecutables(
            AgentPhoneNativeToolCatalog.webIntelligenceExecutableDefinitions(provider: provider))
          let result = registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.toolId(.fetch),
            input: ["url": .string(url), "timeout_ms": .int(remaining)], context: childContext,
            hooks: AgentNativeToolInvocationHooks(nowMillis: nowMillis, cancellationRequested: { collector.cancelled }))
          collector.store(Attempt(url: url, result: result, stopped: nil), at: index)
        } catch { collector.store(Attempt(url: url, result: nil, stopped: "page_read_setup_failed"), at: index) }
      }
    }
    var reason = "page_read_deadline"
    while group.wait(timeout: .now() + .milliseconds(10)) == .timedOut {
      if cancelled() { reason = "page_read_cancelled"; break }
      if DispatchTime.now() >= waitDeadline { break }
    }
    return collector.finish(urls, reason: reason)
  }

  static func attach(to output: AgentMcpJSONObject, attempts: [Attempt]) -> AgentMcpJSONObject {
    guard !attempts.isEmpty else { return output }
    var enriched = output
    var documents = output["documents"]?.arrayValue ?? []
    var bodies: [String: AgentMcpJSONValue] = [:], bodyOrder: [String] = []
    var receipts = output["receipts"]?.arrayValue ?? []
    for attempt in attempts {
      receipts.append(.object(attempt.receipt))
      guard let result = attempt.result else { continue }
      receipts.append(contentsOf: result.output["receipts"]?.arrayValue ?? [])
      guard result.isSuccess else { continue }
      documents.append(contentsOf: (result.output["documents"]?.arrayValue ?? []).prefix(4))
      for value in result.output["evidence_pack"]?.objectValue?["items"]?.arrayValue ?? [] {
        guard let item = value.objectValue, item["evidence_level"] == .string("retrieved_body") else { continue }
        let key = AgentIOSWebEvidencePack.canonicalURL(item["url"]?.stringValue ?? "")
        if !key.isEmpty, bodies[key] == nil { bodies[key] = value; bodyOrder.append(key) }
      }
    }
    let pageReceipts = attempts.map { AgentMcpJSONValue.object($0.receipt) }
    enriched["receipts"] = .array(receipts)
    if !documents.isEmpty { enriched["documents"] = .array(documents) }
    let partial = attempts.contains { $0.result?.isSuccess != true }
    if partial { enriched["status"] = .string("partial") }
    guard var pack = output["evidence_pack"]?.objectValue else { return enriched }
    var items = pack["items"]?.arrayValue ?? []
    for index in items.indices {
      let key = AgentIOSWebEvidencePack.canonicalURL(items[index].objectValue?["url"]?.stringValue ?? "")
      if var body = bodies.removeValue(forKey: key)?.objectValue {
        body["rank"] = items[index].objectValue?["rank"] ?? .int(Int64(index + 1))
        items[index] = .object(body)
      }
    }
    for key in bodyOrder { if let body = bodies.removeValue(forKey: key) { items.append(body) } }
    items = Array(items.prefix(12))
    pack["items"] = .array(items)
    pack["page_reads"] = .array(pageReceipts)
    pack["page_read_status"] = .string(partial ? "partial" : "completed")
    pack["receipts"] = .array((pack["receipts"]?.arrayValue ?? []) + Array(receipts.dropFirst(output["receipts"]?.arrayValue?.count ?? 0)))
    if partial { pack["status"] = .string("partial") }
    var stats = pack["stats"]?.objectValue ?? [:]
    let count = items.filter { $0.objectValue?["source_kind"] == .string("document") }.count
    stats["item_count"] = .int(Int64(items.count)); stats["document_count"] = .int(Int64(count))
    stats["discovery_count"] = .int(Int64(items.count - count))
    stats["domain_count"] = .int(Int64(Set(items.compactMap { URL(string: $0.objectValue?.string("url") ?? "")?.host?.lowercased() }).count))
    pack["stats"] = .object(stats)
    enriched["evidence_pack"] = .object(AgentIOSWebEvidenceVerification.attach(pack))
    return enriched
  }

  static func compactReceipts(in pack: AgentMcpJSONObject) -> AgentMcpJSONValue? {
    guard let reads = pack["page_reads"]?.arrayValue else { return nil }
    return .array(reads.prefix(4).enumerated().map { index, value in
      let receipt = value.objectValue ?? [:]
      return .object([
        "page_read_ordinal": .int(Int64(index + 1)),
        "source_url_sha256": .string(AgentMcpJSONCodec.sha256(["url": receipt["url"] ?? .string("")])),
        "scope": .string("diagnostic_not_citation_evidence"),
        "status": .string(String((receipt["status"]?.stringValue ?? "failed").prefix(32))),
        "error_code": .string(String((receipt["error_code"]?.stringValue ?? "").prefix(80)))
      ])
    })
  }
}
