import CryptoKit
import Foundation
import Security

enum GalaxySSIHealthPortableBackup {
  static let maximumFileBytes = 48 * 1024 * 1024
  private static let maximumSourceBytes = 32 * 1024 * 1024
  private static let magic = Data("GalaxySSI-Health-Backup-v1\n".utf8)
  private static let saltSize = 16
  private static let iterationsV1 = 600_000

  enum Failure: Error { case invalid, limit, stale, password }

  struct Summary: Sendable, Equatable {
    let readings: Int
    let originals: Int
    let tables: Int
    let links: Int
    let missing: Int
    let estimatedBytes: Int
    let start: Date?
    let end: Date?
  }

  struct Plan: Equatable {
    let summary: Summary
    let readingVersions: [String]
    let originalDigests: [String]
    let tableDigests: [String]
  }

  private struct OriginalFile: Codable {
    let manifest: GalaxySSIHealthOriginalStore.Original
    let bytes: Data?
  }

  private struct Payload: Codable {
    let readings: [GalaxySSIHealthReading]
    let originals: [OriginalFile]
    let tables: [GalaxySSIHealthTableImport.Batch]
    let unreadableOriginals: Int
  }

  @MainActor
  static func plan(records: GalaxySSIHealthRecords, originals: GalaxySSIHealthOriginalStore) throws -> Plan {
    let archive = try records.load()
    let listing = try originals.list()
    return makePlan(archive.current, listing: listing, tables: archivedTables(archive.tableBatches ?? []))
  }

  @MainActor
  static func prepare(_ expected: Plan, records: GalaxySSIHealthRecords,
                      originals: GalaxySSIHealthOriginalStore) throws -> (Data, Summary) {
    let archive = try records.load()
    let readings = archive.current
    let listing = try originals.list()
    let tables = archivedTables(archive.tableBatches ?? [])
    guard makePlan(readings, listing: listing, tables: tables) == expected else { throw Failure.stale }
    guard expected.summary.estimatedBytes <= maximumSourceBytes, readings.count <= 10_000 else { throw Failure.limit }
    let files = listing.originals.map { OriginalFile(manifest: $0, bytes: try? originals.read($0)) }
    let payload = Payload(readings: readings, originals: files, tables: tables,
                          unreadableOriginals: listing.unavailable)
    let summary = try validate(payload)
    let data = try JSONEncoder().encode(payload)
    guard data.count <= maximumFileBytes - magic.count - saltSize - 28 else { throw Failure.limit }
    return (data, summary)
  }

  static func seal(_ plaintext: Data, password: String) throws -> Data {
    guard plaintext.count <= maximumFileBytes - magic.count - saltSize - 28 else { throw Failure.limit }
    var salt = Data(count: saltSize)
    let status = salt.withUnsafeMutableBytes { buffer -> OSStatus in
      guard let address = buffer.baseAddress else { return errSecParam }
      return SecRandomCopyBytes(kSecRandomDefault, saltSize, address)
    }
    guard status == errSecSuccess else { throw Failure.invalid }
    let header = magic + salt
    let key = try key(password, salt: salt)
    try Task.checkCancellation()
    guard let sealed = try AES.GCM.seal(plaintext, using: key, authenticating: header).combined else { throw Failure.invalid }
    return header + sealed
  }

  static func verify(_ archive: Data, password: String) throws -> Summary {
    let headerCount = magic.count + saltSize
    guard archive.count <= maximumFileBytes, archive.count > headerCount + 28, archive.starts(with: magic)
    else { throw Failure.invalid }
    let header = Data(archive.prefix(headerCount))
    let salt = Data(header.suffix(saltSize))
    let key = try key(password, salt: salt)
    try Task.checkCancellation()
    let box = try AES.GCM.SealedBox(combined: Data(archive.dropFirst(headerCount)))
    let plaintext = try AES.GCM.open(box, using: key, authenticating: header)
    try Task.checkCancellation()
    return try validate(JSONDecoder().decode(Payload.self, from: plaintext))
  }

  private static func key(_ password: String, salt: Data) throws -> SymmetricKey {
    guard password.count >= 8, password.utf8.count <= 1_024 else { throw Failure.password }
    return SymmetricKey(data: try GalaxySSIBackupManager.pbkdf2SHA256(
      password: password, salt: salt, iterations: iterationsV1, keyByteCount: 32))
  }

  private static func archivedTables(_ tables: [GalaxySSIHealthTableImport.Batch]) -> [GalaxySSIHealthTableImport.Batch] {
    tables.filter { !$0.data.isEmpty }
  }

  private static func makePlan(_ readings: [GalaxySSIHealthReading], listing: GalaxySSIHealthOriginalStore.Listing,
                               tables: [GalaxySSIHealthTableImport.Batch]) -> Plan {
    let hashes = tables.map { ($0.id, digest($0.data)) }
    let present = Dictionary(hashes, uniquingKeysWith: { first, _ in first })
    let links = readings.compactMap(\.tableSource)
    let absent = Set(links.filter { present[$0.batch] != $0.sha256 }.map(\.batch)).count
    let size = listing.originals.reduce(0) { $0 + $1.bytes } + tables.reduce(0) { $0 + $1.data.count }
    let summary = Summary(readings: readings.count, originals: listing.originals.count, tables: tables.count,
                          links: links.count, missing: listing.unavailable + absent, estimatedBytes: size,
                          start: readings.last?.measuredAt, end: readings.first?.measuredAt)
    return Plan(summary: summary,
      readingVersions: readings.map { "\($0.id):\($0.revision)" },
      originalDigests: listing.originals.map { "\($0.id):\($0.sha256)" },
      tableDigests: hashes.map { "\($0.0):\($0.1)" })
  }

  private static func validate(_ payload: Payload) throws -> Summary {
    guard payload.readings.count <= 10_000, payload.originals.count <= 500, payload.tables.count <= 30,
          (0...500).contains(payload.unreadableOriginals),
          Set(payload.readings.map(\.id)).count == payload.readings.count,
          Set(payload.originals.map { $0.manifest.id }).count == payload.originals.count,
          Set(payload.tables.map(\.id)).count == payload.tables.count,
          payload.readings.allSatisfy({ $0.revision > 0 && !$0.deleted && $0.isValid }) else { throw Failure.invalid }
    var size = 0
    var missing = payload.unreadableOriginals
    for entry in payload.originals {
      guard (1...GalaxySSIHealthOriginalStore.maximumFileBytes).contains(entry.manifest.bytes) else { throw Failure.invalid }
      if let data = entry.bytes {
        guard data.count == entry.manifest.bytes, digest(data) == entry.manifest.sha256 else { throw Failure.invalid }
        size += data.count
      } else { missing += 1 }
    }
    var tables: [UUID: String] = [:]
    for batch in payload.tables {
      guard (1...GalaxySSIHealthTableImport.maximumBytes).contains(batch.data.count) else { throw Failure.invalid }
      tables[batch.id] = digest(batch.data)
      size += batch.data.count
    }
    guard size <= maximumSourceBytes else { throw Failure.limit }
    let links = payload.readings.compactMap(\.tableSource)
    missing += Set(links.filter { tables[$0.batch] != $0.sha256 }.map(\.batch)).count
    let dates = payload.readings.map(\.measuredAt)
    return Summary(readings: payload.readings.count, originals: payload.originals.count, tables: payload.tables.count,
                   links: links.count, missing: missing, estimatedBytes: size, start: dates.min(), end: dates.max())
  }

  private static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
