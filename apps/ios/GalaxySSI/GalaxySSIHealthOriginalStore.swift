import CoreGraphics
import CryptoKit
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
struct GalaxySSIHealthOriginalStore {
  enum Kind: String, Codable, CaseIterable, Sendable { case image, pdf }
  enum Acquisition: String, Codable, Sendable { case camera, uploaded }
  struct Original: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let kind: Kind
    let fileExtension: String
    let importedAt: Date
    let bytes: Int
    let sha256: String
    var acquisition: Acquisition?

    var entryPath: String { "originals/" + id.uuidString.lowercased() + "." + fileExtension }
  }

  struct Listing {
    let originals: [Original]
    let unavailable: Int
    var removed: [Original] = []
    var pendingRemovals: Set<UUID> = []
  }

  struct RemovalPreview: Identifiable, Equatable {
    struct Link: Equatable { let record: UUID; let revision: Int }
    let original: Original
    let links: [Link]
    let secondary: [GalaxySSIHealthReportReview.Evidence]
    var id: UUID { original.id }
  }

  struct RemovalAudit: Codable, Identifiable {
    var id = UUID()
    let at: Date
    let linkedMeasurements: Int
  }

  enum RemovalOutcome { case removed, pendingCleanup }

  private struct RemovalLedger: Codable {
    var metadata: [Original] = []
    var pending: Set<UUID> = []
    var audit: [RemovalAudit] = []
  }

  struct ExportAttempt: Codable, Identifiable, Sendable {
    enum Outcome: String, Codable, Sendable { case prepared, verified, unverified }
    let id: UUID
    let at: Date
    let originals: [Original]
    let bytes: Int
    let sha256: String
    var outcome: Outcome
  }

  struct ScopedExport: Sendable {
    let file: URL
    let bytes: Int
    let sha256: String
    fileprivate let key: SymmetricKey
    fileprivate let binding: Data

    func read() throws -> Data {
      let handle = try FileHandle(forReadingFrom: file)
      defer { try? handle.close() }
      guard let sealed = try handle.read(upToCount: bytes + 29), sealed.count == bytes + 28 else {
        throw Failure.invalid
      }
      let data = try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key, authenticating: binding)
      guard data.count == bytes, GalaxySSIHealthOriginalStore.digest(data) == sha256 else { throw Failure.invalid }
      return data
    }

    func discard() { try? FileManager.default.removeItem(at: file) }
  }

  enum Failure: Error { case invalid, limit, stale, restoreBusy }

  final class RestoreLease {
    fileprivate let directory: URL
    fileprivate var held = true

    fileprivate init(directory: URL) { self.directory = directory }
  }

  struct SingleSaveReceipt: Codable {
    let at: Date
    let kind: Kind
    let bytes: Int
    let verified: Bool
  }

  nonisolated static let maximumFileBytes = 16 * 1024 * 1024
  private static let maximumZIPBytes = 64 * 1024 * 1024
  private let maximumHeaderBytes = 4_096
  let owner: String
  let secrets: GalaxySSISecretStore
  var fixtureDirectory: URL? = nil
  var restoreRecordsFile: URL? = nil

  func importFile(_ url: URL) throws {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let input = try FileHandle(forReadingFrom: url)
    defer { try? input.close() }
    let data = try input.read(upToCount: Self.maximumFileBytes + 1) ?? Data()
    guard data.count <= Self.maximumFileBytes else { throw Failure.limit }
    try store(data, name: url.lastPathComponent)
  }

  func store(_ data: Data, name: String, acquisition: Acquisition = .uploaded) throws {
    try withRestoreLease { lease in
      try reconcileRestores(lease: lease)
      try store(data, name: name, acquisition: acquisition, lease: lease)
    }
  }

  private func store(_ data: Data, name: String, acquisition: Acquisition, lease: RestoreLease) throws {
    guard !data.isEmpty, data.count <= Self.maximumFileBytes else { throw Failure.limit }
    let (kind, fileExtension) = try Self.format(of: data)
    let listing = try list(lease: lease)
    let digest = Self.digest(data)
    if listing.originals.contains(where: { $0.sha256 == digest }) { return }
    guard listing.originals.count + listing.unavailable < 500,
          listing.originals.reduce(data.count, { $0 + $1.bytes }) <= 512 * 1024 * 1024
    else { throw Failure.limit }
    let item = Original(id: UUID(), name: String(name.prefix(180)), kind: kind, fileExtension: fileExtension,
                        importedAt: Date(), bytes: data.count, sha256: digest, acquisition: acquisition)
    try writeOriginal(item, data: data, to: url(item.id))
  }

  private static func format(of data: Data) throws -> (Kind, String) {
    if data.starts(with: Data("%PDF-".utf8)),
       let provider = CGDataProvider(data: data as CFData),
       let pdf = CGPDFDocument(provider), pdf.numberOfPages > 0 || (pdf.isEncrypted && !pdf.isUnlocked) {
      return (.pdf, "pdf")
    } else if let image = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(image) > 0,
              let type = CGImageSourceGetType(image), let ext = UTType(type as String)?.preferredFilenameExtension,
              !ext.isEmpty, ext.utf8.count <= 8,
              ext.utf8.allSatisfy({ (48...57).contains($0) || (97...122).contains($0) }) {
      return (.image, ext)
    } else { throw Failure.invalid }
  }

  static func validateRestoreOriginal(_ item: Original, data: Data) throws {
    let (kind, ext) = try format(of: data)
    guard item.kind == kind, item.fileExtension == ext, item.bytes == data.count,
          item.sha256 == digest(data) else { throw Failure.invalid }
  }

  private func writeOriginal(_ item: Original, data: Data, to destination: URL) throws {
    let key = try key(create: true)
    guard let header = try AES.GCM.seal(JSONEncoder().encode(item), using: key,
                                       authenticating: binding(item.id, "header")).combined,
          header.count <= maximumHeaderBytes,
          let payload = try AES.GCM.seal(data, using: key, authenticating: binding(item.id, item.sha256)).combined
    else { throw Failure.invalid }
    var length = UInt32(header.count).bigEndian
    var file = withUnsafeBytes(of: &length) { Data($0) }
    file.append(header)
    file.append(payload)
    try file.write(to: destination, options: [.atomic, .completeFileProtection])
  }

  func stageRestore(_ files: [(Original, Data)], receipt: UUID, lease: RestoreLease) throws {
    try check(lease)
    guard !files.isEmpty else { return }
    let folder = try restoreRoot().appendingPathComponent(receipt.uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.complete])
    for (item, bytes) in files {
      try writeOriginal(item, data: bytes, to: folder.appendingPathComponent(item.id.uuidString))
    }
  }

  private func restoreRoot() throws -> URL {
    try directory().appendingPathComponent("restore-staging", isDirectory: true)
  }

  func withRestoreLease<T>(_ operation: (RestoreLease) throws -> T) throws -> T {
    let directory = try directory()
    let lock = directory.appendingPathComponent("restore.lock")
    let descriptor = try lock.withUnsafeFileSystemRepresentation { path in
      guard let path else { throw Failure.invalid }
      let fd = Darwin.open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, mode_t(0o600))
      guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
      return fd
    }
    defer { _ = Darwin.close(descriptor) }
    while Darwin.flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
      let code = errno
      if code == EINTR { continue }
      if code == EWOULDBLOCK || code == EAGAIN { throw Failure.restoreBusy }
      throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }
    let lease = RestoreLease(directory: directory)
    defer { lease.held = false }
    return try operation(lease)
  }

  private func check(_ lease: RestoreLease) throws {
    guard lease.held, lease.directory == (try directory()) else { throw Failure.stale }
  }

  func containsRestoreID(_ id: UUID, lease: RestoreLease) throws -> Bool {
    try check(lease)
    let ledger = try loadRemovals()
    if ledger.pending.contains(id) { return true }
    return FileManager.default.fileExists(atPath: try url(id).path)
  }

  func reconcileRestores(lease: RestoreLease) throws {
    try check(lease)
    let pending = try reconcileRemovals().pending
    let fm = FileManager.default
    let root = try restoreRoot()
    guard fm.fileExists(atPath: root.path) else { return }
    let folders = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard !folders.isEmpty else { return }
    let records = GalaxySSIHealthRecords(owner: owner, secrets: secrets, isolatedFile: restoreRecordsFile)
    let receipts = try records.load().restoreReceipts ?? []
    for folder in folders {
      guard let receipt = UUID(uuidString: folder.lastPathComponent) else { continue }
      let attributes = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      guard attributes.isDirectory == true, attributes.isSymbolicLink != true else { continue }
      if receipts.contains(receipt) {
        let entries = try fm.contentsOfDirectory(at: folder,
          includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        if entries.contains(where: { UUID(uuidString: $0.lastPathComponent).map(pending.contains) == true }) { continue }
        for entry in entries {
          guard let id = UUID(uuidString: entry.lastPathComponent) else { continue }
          try promoteRestoreFile(entry, id: id)
        }
      }
      try fm.removeItem(at: folder)
    }
  }

  private func promoteRestoreFile(_ entry: URL, id: UUID) throws {
    let attributes = try entry.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    guard attributes.isRegularFile == true, attributes.isSymbolicLink != true else { throw Failure.invalid }
    let handle = try FileHandle(forReadingFrom: entry)
    defer { try? handle.close() }
    let key = try key(create: false)
    let original = try readHeader(handle, id: id, key: key)
    _ = try verifiedPayload(handle, original: original, key: key)
    let length = try handle.offset()
    try handle.seek(toOffset: 0)
    guard length <= UInt64(Self.maximumFileBytes + maximumHeaderBytes + 32),
          let data = try handle.read(upToCount: Int(length)), data.count == Int(length)
    else { throw Failure.invalid }
    try data.write(to: url(id), options: [.atomic, .completeFileProtection])
  }

  func containsOriginalFile(_ id: UUID) throws -> Bool {
    FileManager.default.fileExists(atPath: try url(id).path)
  }

  func list() throws -> Listing {
    try withRestoreLease { lease in
      try reconcileRestores(lease: lease)
      return try list(lease: lease)
    }
  }

  func list(lease: RestoreLease) throws -> Listing {
    try check(lease)
    let ledger = try loadRemovals()
    let files = try FileManager.default.contentsOfDirectory(at: directory(), includingPropertiesForKeys: nil)
    let ids = Set(files.compactMap { UUID(uuidString: $0.lastPathComponent) }).subtracting(ledger.pending)
    let removed = ledger.metadata.filter { !ids.contains($0.id) }
    guard !ids.isEmpty else {
      return Listing(originals: [], unavailable: 0, removed: removed, pendingRemovals: ledger.pending)
    }
    let key = try key(create: false)
    let items: [Original] = ids.compactMap { id in
      try? withFile(id) { try readHeader($0, id: id, key: key) }
    }
    return Listing(originals: items.sorted { ($0.importedAt, $0.id.uuidString) > ($1.importedAt, $1.id.uuidString) },
                   unavailable: ids.count - items.count, removed: removed, pendingRemovals: ledger.pending)
  }

  func read(_ original: Original) throws -> Data {
    try withRestoreLease { lease in
      try reconcileRestores(lease: lease)
      return try read(original, lease: lease)
    }
  }

  func read(_ original: Original, lease: RestoreLease) throws -> Data {
    try check(lease)
    let pending = try loadRemovals().pending
    guard !pending.contains(original.id) else { throw Failure.stale }
    let key = try key(create: false)
    return try withFile(original.id) { file in
      guard try readHeader(file, id: original.id, key: key) == original else { throw Failure.stale }
      return try verifiedPayload(file, original: original, key: key)
    }
  }

  private func verifiedPayload(_ file: FileHandle, original: Original, key: SymmetricKey) throws -> Data {
    guard let payload = try file.read(upToCount: original.bytes + 29), payload.count == original.bytes + 28
    else { throw Failure.invalid }
    let data = try AES.GCM.open(AES.GCM.SealedBox(combined: payload), using: key,
                                authenticating: binding(original.id, original.sha256))
    guard data.count == original.bytes, Self.digest(data) == original.sha256 else { throw Failure.invalid }
    return data
  }

  func previewRemoval(_ original: Original) throws -> RemovalPreview {
    try withRestoreLease { lease in
      try reconcileRestores(lease: lease)
      return try previewRemoval(original, lease: lease)
    }
  }

  private func previewRemoval(_ original: Original, lease: RestoreLease) throws -> RemovalPreview {
    try check(lease)
    let pending = try loadRemovals().pending
    guard !pending.contains(original.id) else { throw Failure.stale }
    let key = try key(create: false)
    do {
      guard try withFile(original.id, { try readHeader($0, id: original.id, key: key) }) == original
      else { throw Failure.stale }
    } catch let error as CocoaError where Self.missingFile(error) { throw Failure.stale }
    let records = GalaxySSIHealthRecords(owner: owner, secrets: secrets, isolatedFile: restoreRecordsFile)
    let archive = try records.load()
    let current = archive.current
    let live = Set(current.map(\.id))
    let secondary = (archive.reportEvidence ?? []).filter {
      $0.source.original == original.id && $0.source.sha256 == original.sha256 && live.contains($0.target.record)
    }
    let targets = Set(secondary.map(\.target.record))
    let links = current.compactMap { reading -> RemovalPreview.Link? in
      let primary = reading.reportSource.map { $0.original == original.id && $0.sha256 == original.sha256 } == true
      guard primary || targets.contains(reading.id) else { return nil }
      return .init(record: reading.id, revision: reading.revision)
    }.sorted { $0.record.uuidString < $1.record.uuidString }
    return RemovalPreview(original: original, links: links, secondary: secondary)
  }

  @discardableResult
  func remove(_ preview: RemovalPreview) throws -> RemovalOutcome {
    try withRestoreLease { lease in
      try reconcileRestores(lease: lease)
      return try remove(preview, lease: lease)
    }
  }

  private func remove(_ preview: RemovalPreview, lease: RestoreLease) throws -> RemovalOutcome {
    guard try previewRemoval(preview.original, lease: lease) == preview else { throw Failure.stale }
    var ledger = try loadRemovals()
    guard ledger.pending.insert(preview.id).inserted else { throw Failure.stale }
    ledger.metadata.removeAll { $0.id == preview.id }
    ledger.metadata.insert(preview.original, at: 0)
    ledger.audit.insert(.init(at: Date(), linkedMeasurements: preview.links.count), at: 0)
    ledger.audit = Array(ledger.audit.prefix(100))
    // Commit the logical removal and audit before touching original bytes.
    try persistRemovals(ledger)
    guard let cleaned = try? reconcileRemovals(), !cleaned.pending.contains(preview.id) else { return .pendingCleanup }
    return .removed
  }

  func removalHistory() throws -> [RemovalAudit] { try loadRemovals().audit }

  private static func missingFile(_ error: CocoaError) -> Bool {
    error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile
  }

  private var removalBinding: Data { Data("galaxyssi.health.originals.removal.v1:\(owner)".utf8) }
  private func removalURL() throws -> URL { try directory().appendingPathComponent("removals-v1") }

  private func loadRemovals() throws -> RemovalLedger {
    let data: Data
    do { data = try Data(contentsOf: removalURL()) }
    catch let error as CocoaError where Self.missingFile(error) { return RemovalLedger() }
    let payload = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key(create: false),
                                  authenticating: removalBinding)
    return try JSONDecoder().decode(RemovalLedger.self, from: payload)
  }

  private func persistRemovals(_ ledger: RemovalLedger) throws {
    let payload = try JSONEncoder().encode(ledger)
    guard let sealed = try AES.GCM.seal(payload, using: key(create: false),
                                        authenticating: removalBinding).combined else { throw Failure.invalid }
    try sealed.write(to: removalURL(), options: [.atomic, .completeFileProtection])
  }

  private func reconcileRemovals() throws -> RemovalLedger {
    var ledger = try loadRemovals()
    guard !ledger.pending.isEmpty else { return ledger }
    let previous = ledger.pending
    let key = try key(create: false)
    for item in ledger.metadata where previous.contains(item.id) {
      do {
        if try withFile(item.id, { try readHeader($0, id: item.id, key: key) }) == item {
          try FileManager.default.removeItem(at: url(item.id))
        }
        ledger.pending.remove(item.id)
      } catch let error as CocoaError where Self.missingFile(error) {
        ledger.pending.remove(item.id)
      } catch {
        continue
      }
    }
    if previous != ledger.pending { try persistRemovals(ledger) }
    return ledger
  }

  func makeZIP(_ originals: [Original]) throws -> Data {
    guard !originals.isEmpty, originals.reduce(0, { $0 + $1.bytes }) <= Self.maximumZIPBytes else { throw Failure.limit }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let manifest = originals.map { ManifestEntry(original: $0, path: $0.entryPath) }
    var entries = [AgentRuntimeProjectArchiveEntry(path: "manifest.json", data: try encoder.encode(manifest))]
    for item in originals {
      entries.append(.init(path: item.entryPath, data: try read(item)))
    }
    return AgentRuntimeProjectArchiveBuilder.buildStoredZip(entries: entries)
  }

  func prepareExport(_ originals: [Original]) throws -> (Data, ExportAttempt) {
    let zip = try makeZIP(originals)
    var history = try exportHistory()
    let attempt = ExportAttempt(id: UUID(), at: Date(), originals: originals, bytes: zip.count,
                                sha256: Self.digest(zip), outcome: .prepared)
    let artifact = try artifactURL(attempt.id)
    guard let sealed = try AES.GCM.seal(zip, using: key(create: true),
                                        authenticating: artifactBinding(attempt)).combined else { throw Failure.invalid }
    try sealed.write(to: artifact, options: [.atomic, .completeFileProtection])
    do {
      history.insert(attempt, at: 0)
      try persistExportHistory(Array(history.prefix(50)))
    } catch {
      try? FileManager.default.removeItem(at: artifact)
      throw error
    }
    pruneArtifacts(history)
    return (zip, attempt)
  }

  func stageScopedExport(_ data: Data) throws -> ScopedExport {
    guard !data.isEmpty, data.count <= Self.maximumZIPBytes + 1024 * 1024 else { throw Failure.limit }
    let root = try directory().appendingPathComponent("scoped-exports-v1", isDirectory: true)
    let manager = FileManager.default
    try manager.createDirectory(at: root, withIntermediateDirectories: true,
                                attributes: [.protectionKey: FileProtectionType.complete])
    let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
    var occupied = 0
    for file in try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys)) {
      guard UUID(uuidString: file.lastPathComponent) != nil else { continue }
      let values = try file.resourceValues(forKeys: keys)
      if let date = values.contentModificationDate, Date().timeIntervalSince(date) > 86_400 {
        try manager.removeItem(at: file)
      } else { occupied += values.fileSize ?? 0 }
    }
    guard occupied + data.count + 28 <= 160 * 1024 * 1024 else { throw Failure.limit }
    let id = UUID()
    let hash = Self.digest(data)
    let binding = Data("galaxyssi.health.scoped-export.v1:\(owner):\(id):\(hash)".utf8)
    let key = try key(create: true)
    guard let sealed = try AES.GCM.seal(data, using: key, authenticating: binding).combined else { throw Failure.invalid }
    let file = root.appendingPathComponent(id.uuidString)
    try sealed.write(to: file, options: [.atomic, .completeFileProtection])
    return .init(file: file, bytes: data.count, sha256: hash, key: key, binding: binding)
  }

  func hasShareArtifact(_ attempt: ExportAttempt) -> Bool {
    guard let url = try? artifactURL(attempt.id) else { return false }
    return FileManager.default.fileExists(atPath: url.path)
  }

  func readShareArtifact(_ attempt: ExportAttempt) throws -> Data {
    guard try exportHistory().contains(where: {
      $0.id == attempt.id && $0.bytes == attempt.bytes && $0.sha256 == attempt.sha256
    }), (1...(Self.maximumZIPBytes + 2 * 1024 * 1024)).contains(attempt.bytes) else { throw Failure.stale }
    let file = try FileHandle(forReadingFrom: artifactURL(attempt.id))
    defer { try? file.close() }
    guard let sealed = try file.read(upToCount: attempt.bytes + 29), sealed.count == attempt.bytes + 28
    else { throw Failure.invalid }
    let zip = try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key(create: false),
                                 authenticating: artifactBinding(attempt))
    guard zip.count == attempt.bytes, Self.digest(zip) == attempt.sha256 else { throw Failure.invalid }
    return zip
  }

  private func artifactBinding(_ attempt: ExportAttempt) -> Data {
    Data("galaxyssi.health.originals.export-artifact.v1:\(owner):\(attempt.id):\(attempt.sha256)".utf8)
  }

  private func artifactDirectory() throws -> URL {
    let root = try directory().appendingPathComponent("export-artifacts-v1", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                            attributes: [.protectionKey: FileProtectionType.complete])
    return root
  }

  private func artifactURL(_ id: UUID) throws -> URL { try artifactDirectory().appendingPathComponent(id.uuidString) }

  private func pruneArtifacts(_ history: [ExportAttempt]) {
    guard let root = try? artifactDirectory(),
          let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
    else { return }
    let available = Set(files.compactMap { UUID(uuidString: $0.lastPathComponent) })
    var keep = Set<UUID>()
    var bytes = 0
    for entry in history where available.contains(entry.id) {
      if keep.count < 3, bytes + entry.bytes <= 128 * 1024 * 1024 {
        keep.insert(entry.id)
        bytes += entry.bytes
      }
    }
    for file in files {
      guard let id = UUID(uuidString: file.lastPathComponent), !keep.contains(id) else { continue }
      try? FileManager.default.removeItem(at: file)
    }
  }

  func exportHistory() throws -> [ExportAttempt] {
    let data: Data
    do { data = try Data(contentsOf: historyURL()) }
    catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { return [] }
    let plaintext = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key(create: false),
                                       authenticating: historyBinding)
    return try JSONDecoder().decode([ExportAttempt].self, from: plaintext)
  }

  func finishExport(id: UUID, verified: Bool) throws {
    var history = try exportHistory()
    guard let index = history.firstIndex(where: { $0.id == id }), history[index].outcome == .prepared else { return }
    history[index].outcome = verified ? .verified : .unverified
    try persistExportHistory(history)
  }

  nonisolated static func verifyDestination(_ url: URL, for attempt: ExportAttempt) throws -> Bool {
    try verifyDestination(url, bytes: attempt.bytes, sha256: attempt.sha256)
  }

  nonisolated static func verifyDestination(_ url: URL, bytes: Int, sha256: String) throws -> Bool {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    var coordinationError: NSError?
    var verification: Result<Bool, Error>?
    NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { resolved in
      verification = Result {
        let file = try FileHandle(forReadingFrom: resolved)
        defer { try? file.close() }
        var count = 0
        var hash = SHA256()
        while let block = try file.read(upToCount: 128 * 1024), !block.isEmpty {
          count += block.count
          guard count <= bytes else { return false }
          hash.update(data: block)
        }
        return count == bytes &&
          hash.finalize().map { String(format: "%02x", $0) }.joined() == sha256
      }
    }
    if let coordinationError { throw coordinationError }
    guard let verification else { throw Failure.invalid }
    return try verification.get()
  }

  func singleSaveHistory() throws -> [SingleSaveReceipt] {
    let data: Data
    do { data = try Data(contentsOf: singleSaveURL()) }
    catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { return [] }
    let plaintext = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key(create: false),
                                     authenticating: singleSaveBinding)
    return try JSONDecoder().decode([SingleSaveReceipt].self, from: plaintext)
  }

  func finishSingleSave(_ original: Original, destinationVerified: Bool) throws -> Bool {
    // A reimport is a different source even when it has the same bytes.
    let verified = destinationVerified && (try? read(original)) != nil
    let receipt = SingleSaveReceipt(at: Date(), kind: original.kind, bytes: original.bytes, verified: verified)
    let history = [receipt] + (try singleSaveHistory())
    let data = try JSONEncoder().encode(Array(history.prefix(50)))
    guard let sealed = try AES.GCM.seal(data, using: key(create: false),
                                        authenticating: singleSaveBinding).combined else { throw Failure.invalid }
    try sealed.write(to: singleSaveURL(), options: [.atomic, .completeFileProtection])
    return verified
  }

  private var singleSaveBinding: Data { Data("galaxyssi.health.originals.single-save.v1:\(owner)".utf8) }
  private func singleSaveURL() throws -> URL { try directory().appendingPathComponent("single-save-v1") }

  private var historyBinding: Data { Data("galaxyssi.health.originals.export-history.v1:\(owner)".utf8) }
  private func historyURL() throws -> URL { try directory().appendingPathComponent("export-history-v1") }

  private func persistExportHistory(_ history: [ExportAttempt]) throws {
    let data = try JSONEncoder().encode(history)
    guard let sealed = try AES.GCM.seal(data, using: key(create: true), authenticating: historyBinding).combined
    else { throw Failure.invalid }
    try sealed.write(to: historyURL(), options: [.atomic, .completeFileProtection])
  }

  private struct ManifestEntry: Encodable { let original: Original; let path: String }

  private func withFile<T>(_ id: UUID, _ body: (FileHandle) throws -> T) throws -> T {
    let file = try FileHandle(forReadingFrom: url(id))
    defer { try? file.close() }
    return try body(file)
  }

  private func readHeader(_ file: FileHandle, id: UUID, key: SymmetricKey) throws -> Original {
    guard let prefix = try file.read(upToCount: 4), prefix.count == 4 else { throw Failure.invalid }
    let size = prefix.reduce(0) { ($0 << 8) | Int($1) }
    guard (28...maximumHeaderBytes).contains(size), let header = try file.read(upToCount: size),
          header.count == size else { throw Failure.invalid }
    let decoded = try AES.GCM.open(AES.GCM.SealedBox(combined: header), using: key,
                                   authenticating: binding(id, "header"))
    let item = try JSONDecoder().decode(Original.self, from: decoded)
    guard item.id == id, (1...Self.maximumFileBytes).contains(item.bytes) else { throw Failure.invalid }
    return item
  }

  private func binding(_ id: UUID, _ purpose: String) -> Data {
    Data("galaxyssi.health.originals.v1:\(owner):\(id.uuidString):\(purpose)".utf8)
  }

  private func url(_ id: UUID) throws -> URL { try directory().appendingPathComponent(id.uuidString) }

  private func directory() throws -> URL {
    if let fixtureDirectory { return fixtureDirectory }
    let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                           appropriateFor: nil, create: true)
    var root = base.appendingPathComponent("HealthOriginals", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                            attributes: [.protectionKey: FileProtectionType.complete])
    var resources = URLResourceValues()
    resources.isExcludedFromBackup = true
    try root.setResourceValues(resources)
    let result = root.appendingPathComponent(Self.digest(Data(owner.utf8)), isDirectory: true)
    try FileManager.default.createDirectory(at: result, withIntermediateDirectories: true,
                                            attributes: [.protectionKey: FileProtectionType.complete])
    return result
  }

  private func key(create: Bool) throws -> SymmetricKey {
    let account = "health.originals.v1." + owner
    if let encoded = secrets.string(account: account) {
      guard let data = Data(base64Encoded: encoded), data.count == 32 else { throw Failure.invalid }
      return SymmetricKey(data: data)
    }
    guard create else { throw Failure.invalid }
    let key = SymmetricKey(size: .bits256)
    try secrets.setString(key.withUnsafeBytes { Data($0).base64EncodedString() }, account: account)
    return key
  }

  private nonisolated static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

extension GalaxySSIHealthOriginalStore {
  struct CropMetadata: Codable, Equatable {
    let revision: UUID
    let originalID: UUID
    let originalSHA256: String
    let bounds: CGRect
    let width: Int
    let height: Int
    let sha256: String
  }

  struct Crop: Codable {
    let metadata: CropMetadata
    let png: Data
  }

  func readCrop(for original: Original) throws -> Crop? {
    try decodeCrop(at: cropURL(original.id), for: original)
  }

  private func decodeCrop(at file: URL, for original: Original) throws -> Crop? {
    let data: Data
    do {
      let handle = try FileHandle(forReadingFrom: file)
      defer { try? handle.close() }
      data = try handle.read(upToCount: Self.maximumFileBytes + 4_097) ?? Data()
      guard data.count <= Self.maximumFileBytes + 4_096 else { throw Failure.limit }
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
      return nil
    }
    let decoded = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key(create: false),
                                   authenticating: cropBinding(original))
    let crop = try PropertyListDecoder().decode(Crop.self, from: decoded)
    guard crop.metadata.originalID == original.id, crop.metadata.originalSHA256 == original.sha256,
          GalaxySSIHealthCropEncoder.valid(crop.metadata.bounds),
          crop.png.count <= Self.maximumFileBytes, Self.digest(crop.png) == crop.metadata.sha256
    else { throw Failure.invalid }
    return crop
  }

  func saveCrop(_ output: GalaxySSIHealthCropEncoder.Output, for original: Original,
                replacing expected: UUID?) throws -> CropMetadata {
    guard original.kind == .image, GalaxySSIHealthCropEncoder.valid(output.bounds),
          (1...Self.maximumFileBytes).contains(output.png.count),
          let source = CGImageSourceCreateWithData(output.png as CFData, nil),
          let imageType = CGImageSourceGetType(source), imageType as String == UTType.png.identifier,
          CGImageSourceGetStatus(source) == .statusComplete,
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          image.width == output.width, image.height == output.height
    else { throw Failure.invalid }
    try recoverInterruptedCrops()
    _ = try read(original)
    guard try readCrop(for: original)?.metadata.revision == expected else { throw Failure.stale }
    let metadata = CropMetadata(revision: UUID(), originalID: original.id, originalSHA256: original.sha256,
                                bounds: output.bounds, width: output.width, height: output.height,
                                sha256: Self.digest(output.png))
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    let payload = try encoder.encode(Crop(metadata: metadata, png: output.png))
    guard let sealed = try AES.GCM.seal(payload, using: key(create: false),
                                        authenticating: cropBinding(original)).combined else { throw Failure.invalid }
    let target = try cropURL(original.id)
    let files = try FileManager.default.contentsOfDirectory(at: target.deletingLastPathComponent(),
                                                             includingPropertiesForKeys: [.fileSizeKey])
    let otherBytes = try files.filter { $0.lastPathComponent != target.lastPathComponent }.reduce(0) {
      $0 + (try $1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
    }
    guard otherBytes + sealed.count <= 256 * 1024 * 1024 else { throw Failure.limit }
    let staging = target.deletingLastPathComponent().appendingPathComponent(UUID().uuidString).appendingPathExtension("pending")
    defer { try? FileManager.default.removeItem(at: staging) }
    try sealed.write(to: staging, options: [.completeFileProtection, .withoutOverwriting])
    let handle = try FileHandle(forWritingTo: staging)
    do {
      try handle.synchronize()
      try handle.close()
    } catch {
      try? handle.close()
      throw error
    }
    guard try decodeCrop(at: staging, for: original)?.metadata == metadata else { throw Failure.invalid }
    // A single same-directory rename commits the authenticated crop and metadata together.
    try staging.withUnsafeFileSystemRepresentation { source in
      try target.withUnsafeFileSystemRepresentation { destination in
        guard let source, let destination else { throw Failure.invalid }
        if Darwin.rename(source, destination) != 0 {
          throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
      }
    }
    return metadata
  }

  func recoverInterruptedCrops() throws {
    let root = try cropDirectory()
    let files = try FileManager.default.contentsOfDirectory(at: root,
      includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    for file in files where file.pathExtension == "pending" &&
      UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil {
      let attributes = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
      guard attributes.isRegularFile == true, attributes.isSymbolicLink != true else { continue }
      try FileManager.default.removeItem(at: file)
    }
  }

  private func cropBinding(_ original: Original) -> Data {
    Data("galaxyssi.health.originals.crop.v1:\(owner):\(original.id):\(original.sha256)".utf8)
  }

  private func cropURL(_ id: UUID) throws -> URL {
    try cropDirectory().appendingPathComponent(id.uuidString)
  }

  private func cropDirectory() throws -> URL {
    let root = try directory().appendingPathComponent("report-crops-v1", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                            attributes: [.protectionKey: FileProtectionType.complete])
    return root
  }
}
