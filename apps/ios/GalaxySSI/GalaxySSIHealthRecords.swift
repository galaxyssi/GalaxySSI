import CryptoKit
import Foundation

enum GalaxySSIHealthMetric: String, Codable, CaseIterable, Identifiable {
  case bloodPressure, glucose, weight, heartRate

  var id: String { rawValue }
  var unit: String {
    switch self {
    case .bloodPressure: return "mmHg"
    case .glucose: return "mmol/L"
    case .weight: return "kg"
    case .heartRate: return "bpm"
    }
  }
}

struct GalaxySSIHealthReading: Codable, Identifiable, Equatable {
  var id = UUID()
  var revision = 0
  var metric: GalaxySSIHealthMetric
  var measuredAt = Date()
  var value: Decimal
  var diastolic: Decimal?
  var pulse: Decimal?
  var conditions = ""
  var notes = ""
  var deleted = false

  var isValid: Bool {
    func positive(_ number: Decimal) -> Bool {
      !number.isNaN && number > 0
    }
    guard positive(value), measuredAt.timeIntervalSinceReferenceDate.isFinite,
          conditions.utf8.count <= 512, notes.utf8.count <= 4096 else { return false }
    if metric == .bloodPressure {
      guard let diastolic, positive(diastolic), value > diastolic else { return false }
      return pulse.map(positive) ?? true
    }
    return diastolic == nil && pulse == nil
  }

  func sameMeasurement(as other: Self) -> Bool {
    metric == other.metric && abs(measuredAt.timeIntervalSince(other.measuredAt)) < 60 &&
      value == other.value && diastolic == other.diastolic && pulse == other.pulse
  }
}

struct GalaxySSIHealthDraft: Codable, Identifiable {
  var id = UUID()
  var existing: GalaxySSIHealthReading?
  var metric: GalaxySSIHealthMetric = .bloodPressure
  var measuredAt = Date()
  var value = ""
  var diastolic = ""
  var pulse = ""
  var conditions = ""
  var notes = ""

  var fitsStorageLimits: Bool {
    [value, diastolic, pulse].allSatisfy { $0.utf8.count <= 128 } &&
      conditions.utf8.count <= 512 && notes.utf8.count <= 4096
  }
}

@MainActor
struct GalaxySSIHealthRecords {
  enum Failure: Error {
    case invalid, stale, duplicate, unavailable
  }

  struct Archive: Codable {
    var version = 1
    var revisions: [GalaxySSIHealthReading] = []
    var draft: GalaxySSIHealthDraft?

    var current: [GalaxySSIHealthReading] {
      var seen = Set<UUID>()
      return revisions.reversed().filter { seen.insert($0.id).inserted && !$0.deleted }
        .sorted { ($0.measuredAt, $0.id.uuidString) > ($1.measuredAt, $1.id.uuidString) }
    }
  }

  let owner: String
  let secrets: GalaxySSISecretStore
  var isolatedFile: URL? = nil

  private var context: Data { Data("galaxyssi.health.records.v1:\(owner)".utf8) }
  private var account: String { "health.records.v1." + owner }
  private var file: URL {
    get throws {
      if let isolatedFile { return isolatedFile }
      let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                             appropriateFor: nil, create: true)
      let directory = base.appendingPathComponent("HealthRecords", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                              attributes: [.protectionKey: FileProtectionType.complete])
      var excludedDirectory = directory
      var resources = URLResourceValues()
      resources.isExcludedFromBackup = true
      try excludedDirectory.setResourceValues(resources)
      let name = SHA256.hash(data: context).map { String(format: "%02x", $0) }.joined()
      return directory.appendingPathComponent(name)
    }
  }

  func load() throws -> Archive {
    let data: Data
    do { data = try Data(contentsOf: file) }
    catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
      return Archive()
    }
    let box = try AES.GCM.SealedBox(combined: data)
    let archive = try JSONDecoder().decode(Archive.self,
      from: AES.GCM.open(box, using: key(create: false), authenticating: context))
    guard archive.version == 1 else { throw Failure.unavailable }
    return archive
  }

  func storeDraft(_ draft: GalaxySSIHealthDraft) throws {
    guard draft.fitsStorageLimits else { throw Failure.invalid }
    var archive = try load()
    archive.draft = draft
    try persist(archive)
  }

  func discardDraft(id: UUID) throws {
    var archive = try load()
    guard archive.draft?.id == id else { return }
    archive.draft = nil
    try persist(archive)
  }

  func write(_ input: GalaxySSIHealthReading, allowDuplicate: Bool = false, draftId: UUID? = nil) throws {
    guard input.isValid else { throw Failure.invalid }
    var archive = try load()
    let latest = archive.revisions.last { $0.id == input.id }
    guard (latest?.revision ?? 0) == input.revision, latest?.deleted != true,
          !input.deleted || latest != nil else { throw Failure.stale }
    if !input.deleted && !allowDuplicate &&
        archive.current.contains(where: { $0.id != input.id && $0.sameMeasurement(as: input) }) {
      throw Failure.duplicate
    }
    var revision = input
    revision.revision += 1
    archive.revisions.append(revision)
    if let draftId, archive.draft?.id == draftId { archive.draft = nil }
    try persist(archive)
  }

  private func persist(_ archive: Archive) throws {
    let payload = try JSONEncoder().encode(archive)
    guard let sealed = try AES.GCM.seal(payload, using: key(create: true),
                                        authenticating: context).combined else { throw Failure.unavailable }
    try sealed.write(to: file, options: [.atomic, .completeFileProtection])
  }

  private func key(create: Bool) throws -> SymmetricKey {
    if let encoded = secrets.string(account: account) {
      guard let data = Data(base64Encoded: encoded), data.count == 32 else { throw Failure.unavailable }
      return SymmetricKey(data: data)
    }
    guard create else { throw Failure.unavailable }
    let key = SymmetricKey(size: .bits256)
    try secrets.setString(key.withUnsafeBytes { Data($0).base64EncodedString() }, account: account)
    return key
  }
}
