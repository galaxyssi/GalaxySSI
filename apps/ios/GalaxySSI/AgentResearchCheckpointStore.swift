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

@MainActor
struct AgentResearchCheckpointStore {
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

  func remove(conversation: String) { destroy(prefix: prefix + Self.digest(conversation) + ".") }
  func remove(conversation: String, turn: String, source: UUID) {
    GalaxySSIEncryptedUserDefaultsStore.destroy(defaults: defaults, key: key(conversation, turn, source), secrets: secrets)
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

  private var prefix: String { "agent.research-checkpoints.v1." + Self.digest(owner) + "." }
  func key(_ conversation: String, _ turn: String, _ source: UUID) -> String {
    prefix + Self.digest(conversation) + "." + Self.digest(turn) + "." + Self.digest(source.uuidString.lowercased())
  }

  private static func digest(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}
