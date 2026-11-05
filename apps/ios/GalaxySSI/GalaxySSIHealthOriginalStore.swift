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

  enum Failure: Error { case invalid, limit, stale }

  nonisolated static let maximumFileBytes = 16 * 1024 * 1024
  private static let maximumZIPBytes = 64 * 1024 * 1024
  private let maximumHeaderBytes = 4_096
  let owner: String
  let secrets: GalaxySSISecretStore
  var fixtureDirectory: URL? = nil

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
    guard !data.isEmpty, data.count <= Self.maximumFileBytes else { throw Failure.limit }
    let kind: Kind
    let fileExtension: String
    if data.starts(with: Data("%PDF-".utf8)),
       let provider = CGDataProvider(data: data as CFData),
       let pdf = CGPDFDocument(provider), pdf.numberOfPages > 0 || (pdf.isEncrypted && !pdf.isUnlocked) {
      kind = .pdf
      fileExtension = "pdf"
    } else if let image = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(image) > 0,
              let type = CGImageSourceGetType(image), let ext = UTType(type as String)?.preferredFilenameExtension,
              !ext.isEmpty, ext.utf8.count <= 8,
              ext.utf8.allSatisfy({ (48...57).contains($0) || (97...122).contains($0) }) {
      kind = .image
      fileExtension = ext
    } else { throw Failure.invalid }
    let listing = try list()
    let digest = Self.digest(data)
    if listing.originals.contains(where: { $0.sha256 == digest }) { return }
    guard listing.originals.count + listing.unavailable < 500,
          listing.originals.reduce(data.count, { $0 + $1.bytes }) <= 512 * 1024 * 1024
    else { throw Failure.limit }
    let item = Original(id: UUID(), name: String(name.prefix(180)), kind: kind, fileExtension: fileExtension,
                        importedAt: Date(), bytes: data.count, sha256: digest, acquisition: acquisition)
    let key = try key(create: true)
    guard let header = try AES.GCM.seal(JSONEncoder().encode(item), using: key,
                                       authenticating: binding(item.id, "header")).combined,
          header.count <= maximumHeaderBytes,
          let payload = try AES.GCM.seal(data, using: key, authenticating: binding(item.id, digest)).combined
    else { throw Failure.invalid }
    var length = UInt32(header.count).bigEndian
    var file = withUnsafeBytes(of: &length) { Data($0) }
    file.append(header)
    file.append(payload)
    try file.write(to: url(item.id), options: [.atomic, .completeFileProtection])
  }

  func containsOriginalFile(_ id: UUID) throws -> Bool {
    FileManager.default.fileExists(atPath: try url(id).path)
  }

  func list() throws -> Listing {
    let files = try FileManager.default.contentsOfDirectory(at: directory(), includingPropertiesForKeys: nil)
    let ids = files.compactMap { UUID(uuidString: $0.lastPathComponent) }
    guard !ids.isEmpty else { return Listing(originals: [], unavailable: 0) }
    let key = try key(create: false)
    let items: [Original] = ids.compactMap { id in
      try? withFile(id) { try readHeader($0, id: id, key: key) }
    }
    return Listing(originals: items.sorted { ($0.importedAt, $0.id.uuidString) > ($1.importedAt, $1.id.uuidString) },
                   unavailable: ids.count - items.count)
  }

  func read(_ original: Original) throws -> Data {
    let key = try key(create: false)
    return try withFile(original.id) { file in
      guard try readHeader(file, id: original.id, key: key) == original,
            let payload = try file.read(upToCount: original.bytes + 29), payload.count == original.bytes + 28
      else { throw Failure.stale }
      let data = try AES.GCM.open(AES.GCM.SealedBox(combined: payload), using: key,
                                  authenticating: binding(original.id, original.sha256))
      guard data.count == original.bytes, Self.digest(data) == original.sha256 else { throw Failure.invalid }
      return data
    }
  }

  func remove(_ original: Original) throws {
    let key = try key(create: false)
    guard try withFile(original.id, { try readHeader($0, id: original.id, key: key) }) == original
    else { throw Failure.stale }
    try FileManager.default.removeItem(at: url(original.id))
    let crop = try cropURL(original.id)
    if FileManager.default.fileExists(atPath: crop.path) { try FileManager.default.removeItem(at: crop) }
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
          guard count <= attempt.bytes else { return false }
          hash.update(data: block)
        }
        return count == attempt.bytes &&
          hash.finalize().map { String(format: "%02x", $0) }.joined() == attempt.sha256
      }
    }
    if let coordinationError { throw coordinationError }
    guard let verification else { throw Failure.invalid }
    return try verification.get()
  }

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

  private static func digest(_ data: Data) -> String {
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
