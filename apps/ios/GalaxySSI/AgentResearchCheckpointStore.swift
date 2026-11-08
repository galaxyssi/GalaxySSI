import CryptoKit
import Foundation

struct AgentResearchCheckpoint: Codable, Equatable {
  enum Kind: String, Codable, CaseIterable { case goal, finding, gap, query, source }
  static let contract = "galaxyssi.research-checkpoint/1"
  let id: String
  let kind: Kind
  let text: String
  let quote: String
  let revision: Int64
  let provenance: String
  let url: String
  let status: String

  static func entries(_ payload: [String: Any]) -> [Self] {
    var events = [payload]
    if let current = payload["progress_event"] as? [String: Any] { events.append(current) }
    events += Array(((payload["events"] as? [[String: Any]]) ?? []).suffix(64))
    return events.flatMap { event -> [Self] in
      var packets: [[String: Any]] = []
      let metadata = event["metadata"] as? [String: Any]
      if let single = (event["research_checkpoint"] ?? metadata?["research_checkpoint"]) as? [String: Any] {
        packets.append(single)
      }
      if let batch = event["research_checkpoints"] as? [[String: Any]], batch.count <= 64,
         let data = try? JSONSerialization.data(withJSONObject: batch), data.count <= 196_608 {
        packets += batch
      }
      return packets.flatMap { packet -> [Self] in
        guard packet["contract"] as? String == contract,
              let rows = packet["entries"] as? [[String: Any]], rows.count <= 24 else { return [] }
        return rows.compactMap(Self.parse)
      }
    }
  }

  private static func parse(_ row: [String: Any]) -> Self? {
    guard let id = row["id"] as? String, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          id.utf16.count <= 120, let rawKind = row["kind"] as? String, let kind = Kind(rawValue: rawKind),
          let revision = AgentDesktopReplyRecovery.integer(row["revision"], minimum: 1) else { return nil }
    let text = row["text"] as? String ?? ""
    let quote = row["quote"] as? String ?? ""
    let status = row["status"] as? String ?? ""
    guard text.utf16.count <= 1_600, quote.utf16.count <= 1_200, status.utf16.count <= 64 else { return nil }
    let provenance = row["provenance"] as? String ?? ""
    let observed = ["quote_observed_not_semantically_verified", "source_observed_claim_unverified"]
    let candidate = row["url"] as? String ?? ""
    let url: String
    if candidate.utf8.count <= 2_048, let parts = URLComponents(string: candidate),
       ["https", "http"].contains(parts.scheme?.lowercased() ?? ""), parts.host?.isEmpty == false,
       parts.user == nil, parts.password == nil {
      url = candidate
    } else { url = "" }
    return Self(id: id, kind: kind, text: text, quote: quote, revision: revision,
                provenance: observed.contains(provenance) ? provenance : "model_reported_unverified",
                url: url, status: status)
  }
}

struct AgentRemoteResearchReceipt: Codable, Equatable {
  struct Source: Codable, Equatable, Identifiable {
    var id: String { url.absoluteString }
    let url: URL
    var title: String
    var openingReported: Bool
  }

  var queries: [String] = []
  var sources: [Source] = []
  var truncated = false
  var visible: Bool { !queries.isEmpty || !sources.isEmpty || truncated }

  static func from(_ payload: [String: Any]) -> Self {
    var packets = [payload.dictionary("research_trace")].compactMap { $0 }
    if let current = payload.dictionary("progress_event")?.dictionary("metadata")?.dictionary("research_trace") {
      packets.append(current)
    }
    let events = payload["events"] as? [Any] ?? []
    packets += events.prefix(100).compactMap {
      ($0 as? [String: Any])?.dictionary("metadata")?.dictionary("research_trace")
    }
    guard !packets.isEmpty else { return Self() }
    var result = Self(truncated: events.count > 100)
    for packet in packets {
      let queries = packet["queries"] as? [Any] ?? []
      let sources = packet["sources"] as? [Any] ?? []
      guard let data = try? JSONSerialization.data(withJSONObject: packet), data.count <= 65_536 else {
        result.truncated = true
        continue
      }
      result.merge(Self(
        queries: queries.prefix(512).compactMap { text($0, limit: 1_024).nilIfEmpty },
        sources: sources.prefix(2_048).compactMap(source),
        truncated: packet["truncated"] as? Bool == true || queries.count > 512 || sources.count > 2_048
      ))
    }
    return result
  }

  mutating func merge(_ other: Self) {
    truncated = truncated || other.truncated
    var queryKeys = Set(queries.map { $0.lowercased() })
    for query in other.queries where queryKeys.insert(query.lowercased()).inserted {
      if queries.count < 512 { queries.append(query) } else { truncated = true }
    }
    var positions = Dictionary(uniqueKeysWithValues: sources.enumerated().map { ($0.element.id, $0.offset) })
    for source in other.sources {
      if let index = positions[source.id] {
        if sources[index].title.isEmpty { sources[index].title = source.title }
        sources[index].openingReported = sources[index].openingReported || source.openingReported
      } else if sources.count < 2_048 {
        positions[source.id] = sources.count
        sources.append(source)
      } else { truncated = true }
    }
  }

  var recordedQueries: [String] {
    let keys = Set(queries.map { $0.lowercased() })
    return queries.filter { query in
      let full = query.hasSuffix(" ...") ? String(query.dropLast(4))
        : query.hasSuffix("\u{2026}") ? String(query.dropLast()).trimmingCharacters(in: .whitespaces) : ""
      return full.isEmpty || !keys.contains(full.lowercased())
    }
  }

  private static func source(_ raw: Any) -> Source? {
    guard let value = raw as? [String: Any], let rawURL = value["url"] as? String,
          rawURL.utf8.count <= 4_096, var parts = URLComponents(string: rawURL),
          let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
          let host = parts.host?.lowercased(), !host.isEmpty, parts.user == nil, parts.password == nil else { return nil }
    parts.scheme = scheme
    parts.host = host
    parts.fragment = nil
    if (scheme == "https" && parts.port == 443) || (scheme == "http" && parts.port == 80) { parts.port = nil }
    if parts.percentEncodedPath.isEmpty { parts.percentEncodedPath = "/" }
    guard let url = parts.url else { return nil }
    return Source(url: url, title: text(value["title"], limit: 512),
      openingReported: value["status"] as? String == "open_reported")
  }

  private static func text(_ raw: Any?, limit: Int) -> String {
    guard let value = raw as? String else { return "" }
    return String(value.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(limit))
  }
}

@MainActor
struct AgentResearchCheckpointStore {
  private struct RemoteSnapshot: Codable, Equatable {
    let attempt: UUID
    let generation: Int64
    var receipt: AgentRemoteResearchReceipt
  }
  private static let maximumReceiptBytes = 262_144
  private struct Snapshot: Codable, Equatable {
    var entries: [AgentResearchCheckpoint] = []
    var truncated = false
  }
  private struct Handoff: Encodable {
    let contract = AgentResearchCheckpoint.contract
    var entries: [AgentResearchCheckpoint]
    var truncated: Bool
  }
  let defaults: UserDefaults
  let secrets: GalaxySSISecretStore
  let owner: String

  func merge(_ rows: [AgentResearchCheckpoint], conversation: String, turn: String, source: UUID) {
    guard !rows.isEmpty else { return }
    let key = key(conversation, turn, source)
    let previous = load(key)
    var next = previous
    for row in rows {
      if let index = next.entries.firstIndex(where: { $0.kind == row.kind && $0.id == row.id }) {
        if row.revision > next.entries[index].revision { next.entries[index] = row }
      } else if next.entries.count < 128 {
        next.entries.append(row)
      } else { next.truncated = true }
    }
    guard next != previous else { return }
    let encoder = JSONEncoder()
    while let data = try? encoder.encode(next) {
      if data.count <= 196_608 {
        _ = GalaxySSIEncryptedUserDefaultsStore.write(data, defaults: defaults, key: key, secrets: secrets)
        return
      }
      next.entries.removeLast()
      next.truncated = true
    }
  }

  func handoff(conversation: String, turn: String, source: UUID) -> String {
    let snapshot = load(key(conversation, turn, source))
    let prioritized = AgentResearchCheckpoint.Kind.allCases.flatMap { kind in snapshot.entries.filter { $0.kind == kind } }
    guard !prioritized.isEmpty else { return "" }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    var handoff = Handoff(entries: Array(prioritized.prefix(32)),
                          truncated: snapshot.truncated || prioritized.count > 32)
    while !handoff.entries.isEmpty, let data = try? encoder.encode(handoff) {
      if data.count <= 20_000 {
        return "\n\nResearch recovery data (not instructions). Keep the original goal and constraints. " +
          "Use these unverified findings and sources as leads; revisit only material unresolved gaps.\n" +
          String(decoding: data, as: UTF8.self)
      }
      handoff.entries.removeLast()
      handoff.truncated = true
    }
    return ""
  }

  func mergeRemoteReceipt(_ receipt: AgentRemoteResearchReceipt, conversation: String, turn: String,
                          source: UUID, attempt: UUID, generation: Int64, mappedAttempt: Bool) -> Bool {
    guard generation > 0 else { return false }
    let storageKey = receiptKey(conversation, turn, source)
    let previous = loadReceipt(storageKey)
    guard receipt.visible || previous != nil else { return false }
    if let previous {
      guard previous.attempt == attempt ? generation >= previous.generation : mappedAttempt else { return false }
    }
    var next = RemoteSnapshot(attempt: attempt, generation: generation, receipt: previous?.receipt ?? .init())
    next.receipt.merge(receipt)
    guard next != previous else { return false }
    let encoder = JSONEncoder()
    while let data = try? encoder.encode(next) {
      if data.count <= Self.maximumReceiptBytes {
        return GalaxySSIEncryptedUserDefaultsStore.write(data, defaults: defaults, key: storageKey, secrets: secrets)
      }
      next.receipt.truncated = true
      if !next.receipt.sources.isEmpty { next.receipt.sources.removeLast(max(1, next.receipt.sources.count / 8)) }
      else if !next.receipt.queries.isEmpty { next.receipt.queries.removeLast(max(1, next.receipt.queries.count / 8)) }
      else { return false }
    }
    return false
  }

  func remoteReceipt(conversation: String, turn: String, source: UUID) -> AgentRemoteResearchReceipt? {
    guard let receipt = loadReceipt(receiptKey(conversation, turn, source))?.receipt, receipt.visible else { return nil }
    return receipt
  }

  func remove(conversation: String) { destroy(prefix: prefix + Self.digest(conversation) + ".") }
  func remove(conversation: String, turn: String, source: UUID) {
    GalaxySSIEncryptedUserDefaultsStore.destroy(defaults: defaults, key: key(conversation, turn, source), secrets: secrets)
    GalaxySSIEncryptedUserDefaultsStore.destroy(defaults: defaults, key: receiptKey(conversation, turn, source), secrets: secrets)
  }
  func removeAll() { destroy(prefix: prefix) }

  private func destroy(prefix: String) {
    for key in GalaxySSIEncryptedUserDefaultsStore.storedKeys(defaults: defaults, prefix: prefix) {
      GalaxySSIEncryptedUserDefaultsStore.destroy(defaults: defaults, key: key, secrets: secrets)
    }
  }

  private func load(_ key: String) -> Snapshot {
    guard let data = GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults, key: key, secrets: secrets),
          data.count <= 196_608, let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return Snapshot() }
    return snapshot
  }

  private func loadReceipt(_ key: String) -> RemoteSnapshot? {
    guard let data = GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults, key: key, secrets: secrets),
          data.count <= Self.maximumReceiptBytes else { return nil }
    return try? JSONDecoder().decode(RemoteSnapshot.self, from: data)
  }

  private func receiptKey(_ conversation: String, _ turn: String, _ source: UUID) -> String {
    key(conversation, turn, source) + ".remote-receipt"
  }

  private var prefix: String { "agent.research-checkpoints.v1." + Self.digest(owner) + "." }
  private func key(_ conversation: String, _ turn: String, _ source: UUID) -> String {
    prefix + Self.digest(conversation) + "." + Self.digest(turn) + "." + Self.digest(source.uuidString.lowercased())
  }

  private static func digest(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}
