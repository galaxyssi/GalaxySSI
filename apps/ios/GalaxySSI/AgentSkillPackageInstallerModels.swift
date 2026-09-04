import CryptoKit
import Foundation

struct AgentSkillPackageInspection: Codable, Equatable {
  var manifest: AgentSkillManifest
  var entries: Set<String>
  var packageBytes: Int64
  var integrityVerified: Bool
  var signer: String

  init(
    manifest: AgentSkillManifest,
    entries: Set<String>,
    packageBytes: Int64,
    integrityVerified: Bool,
    signer: String = ""
  ) {
    self.manifest = manifest
    self.entries = entries
    self.packageBytes = max(packageBytes, 0)
    self.integrityVerified = integrityVerified
    self.signer = String(signer.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentSkillLimits.maxTitleCharacters))
  }

  enum CodingKeys: String, CodingKey {
    case manifest
    case entries
    case packageBytes = "package_bytes"
    case integrityVerified = "integrity_verified"
    case signer
  }
}

struct AgentSkillPackageError: LocalizedError, Equatable {
  var message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? {
    message
  }
}

enum AgentSkillPackageExporter {
  static func export(_ manifest: AgentSkillManifest) -> Data {
    let rawManifest = Data(AgentSkillManifestCodec.encode(manifest).utf8)
    let integrityDocument: AgentMcpJSONObject = [
      "manifest_sha256": .string(sha256(rawManifest)),
      "signer": .string("GalaxySSI local export")
    ]
    let integrity = AgentMcpJSONCodec.stringify(integrityDocument)
    return AgentRuntimeProjectArchiveBuilder.buildStoredZip(entries: [
      AgentRuntimeProjectArchiveEntry(path: AgentSkillPackageInstaller.manifestFile, data: rawManifest),
      AgentRuntimeProjectArchiveEntry(path: AgentSkillPackageInstaller.integrityFile, data: Data(integrity.utf8))
    ])
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

final class AgentSkillPackageInstaller {
  private let runtime: AgentSkillRuntime

  init(_ runtime: AgentSkillRuntime) {
    self.runtime = runtime
  }

  func inspect(_ packageData: Data) throws -> AgentSkillPackageInspection {
    guard packageData.count <= Self.maxPackageBytes else {
      throw AgentSkillPackageError("Skill package content exceeds its byte limit")
    }
    let files = try readArchive(packageData)
    guard let rawManifestData = files[Self.manifestFile],
          let rawManifest = String(data: rawManifestData, encoding: .utf8) else {
      throw AgentSkillPackageError("Skill package is missing \(Self.manifestFile)")
    }
    guard let manifest = AgentSkillManifestCodec.decode(rawManifest) else {
      throw AgentSkillPackageError("Skill manifest is malformed")
    }
    try runtime.validate(manifest).requireValid()
    guard Self.allowedPackageSources.contains(manifest.source) else {
      throw AgentSkillPackageError("Third-party Skill package declares an invalid installation source")
    }
    let integrity = try inspectIntegrity(files[Self.integrityFile], manifestData: rawManifestData)
    return AgentSkillPackageInspection(
      manifest: manifest,
      entries: Set(files.keys),
      packageBytes: Int64(packageData.count),
      integrityVerified: integrity.verified,
      signer: integrity.signer
    )
  }

  func install(_ packageData: Data, allowUnsignedLocalPackage: Bool = false) throws -> AgentSkillInstallation {
    let inspected = try inspect(packageData)
    if !inspected.integrityVerified && !allowUnsignedLocalPackage {
      throw AgentSkillPackageError("Unsigned Skill package requires explicit local-install approval")
    }
    return try runtime.install(inspected.manifest, enabled: false)
  }

  static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private struct ZipEntry {
    var path: String
    var directory: Bool
    var method: UInt16
    var uncompressedBytes: Int64
    var crc32: UInt32
    var dataOffset: Int
    var dataLength: Int
  }

  private func readArchive(_ data: Data) throws -> [String: Data] {
    let entries = try inspectZipData(data)
    var files: [String: Data] = [:]
    var expandedBytes: Int64 = 0
    for entry in entries where !entry.directory {
      guard files.count < Int(Self.maxEntries) else {
        throw AgentSkillPackageError("Skill package contains too many files")
      }
      guard files[entry.path] == nil else {
        throw AgentSkillPackageError("Duplicate Skill package entry: \(entry.path)")
      }
      try rejectExecutable(entry.path)
      let content = try extractEntry(entry, from: data)
      guard let nextBytes = checkedAdd(expandedBytes, Int64(content.count)),
            nextBytes <= Self.maxExpandedBytes else {
        throw AgentSkillPackageError("Expanded Skill package exceeds its byte limit")
      }
      expandedBytes = nextBytes
      files[entry.path] = content
    }
    return files
  }

  private func extractEntry(_ entry: ZipEntry, from data: Data) throws -> Data {
    guard entry.uncompressedBytes <= Int64(Self.maxEntryBytes),
          rangeFits(start: entry.dataOffset, length: entry.dataLength, in: data) else {
      throw AgentSkillPackageError("Skill package content exceeds its byte limit")
    }
    let raw = data.subdata(in: entry.dataOffset..<(entry.dataOffset + entry.dataLength))
    let content: Data
    switch entry.method {
    case 0:
      guard entry.dataLength <= Self.maxEntryBytes else {
        throw AgentSkillPackageError("Skill package content exceeds its byte limit")
      }
      content = raw
    case 8:
      do {
        content = try AgentMcpPackageInstaller.inflateDeflate(
          raw,
          expectedBytes: entry.uncompressedBytes,
          maxBytes: Self.maxEntryBytes
        )
      } catch {
        throw AgentSkillPackageError("Skill package ZIP entry could not be decompressed")
      }
    default:
      throw AgentSkillPackageError("Skill package ZIP compression method is not supported on iOS yet")
    }
    guard Int64(content.count) == entry.uncompressedBytes else {
      throw AgentSkillPackageError("Skill package entry size changed during extraction")
    }
    guard crc32(content) == entry.crc32 else {
      throw AgentSkillPackageError("Skill package entry CRC did not match")
    }
    return content
  }

  private func inspectIntegrity(_ data: Data?, manifestData: Data) throws -> (verified: Bool, signer: String) {
    guard let data else {
      return (false, "")
    }
    guard let object = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: data) else {
      throw AgentSkillPackageError("Integrity document is malformed")
    }
    let expectedHash = (object["manifest_sha256"]?.stringValue ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    if expectedHash.isEmpty {
      return (false, object["signer"]?.stringValue ?? "")
    }
    guard expectedHash == Self.sha256(manifestData) else {
      throw AgentSkillPackageError("Skill manifest integrity check failed")
    }
    return (true, object["signer"]?.stringValue ?? "")
  }

  private func inspectZipData(_ data: Data) throws -> [ZipEntry] {
    guard let eocdOffset = endOfCentralDirectoryOffset(data),
          let diskNumber = readUInt16LE(data, eocdOffset + 4),
          let centralDisk = readUInt16LE(data, eocdOffset + 6),
          let diskEntryCount = readUInt16LE(data, eocdOffset + 8),
          let totalEntryCount = readUInt16LE(data, eocdOffset + 10),
          let centralSizeValue = readUInt32LE(data, eocdOffset + 12),
          let centralOffsetValue = readUInt32LE(data, eocdOffset + 16) else {
      throw AgentSkillPackageError("ZIP central directory was not found")
    }
    guard diskNumber == 0, centralDisk == 0, diskEntryCount == totalEntryCount else {
      throw AgentSkillPackageError("Multi-disk Skill package archives are not supported")
    }
    guard totalEntryCount <= Self.maxEntries else {
      throw AgentSkillPackageError("Skill package contains too many files")
    }
    let centralOffset = Int(centralOffsetValue)
    let centralSize = Int(centralSizeValue)
    guard rangeFits(start: centralOffset, length: centralSize, in: data) else {
      throw AgentSkillPackageError("ZIP central directory is out of bounds")
    }

    var cursor = centralOffset
    var entries: [ZipEntry] = []
    for _ in 0..<Int(totalEntryCount) {
      guard readUInt32LE(data, cursor) == 0x02014b50,
            let flags = readUInt16LE(data, cursor + 8),
            let method = readUInt16LE(data, cursor + 10),
            let crc = readUInt32LE(data, cursor + 16),
            let compressed = readUInt32LE(data, cursor + 20),
            let uncompressed = readUInt32LE(data, cursor + 24),
            let nameLength = readUInt16LE(data, cursor + 28),
            let extraLength = readUInt16LE(data, cursor + 30),
            let commentLength = readUInt16LE(data, cursor + 32),
            let localOffsetValue = readUInt32LE(data, cursor + 42) else {
        throw AgentSkillPackageError("ZIP central directory entry is invalid")
      }
      guard flags & 0x0001 == 0 else {
        throw AgentSkillPackageError("Encrypted Skill package entries are not supported")
      }
      guard method == 0 || method == 8 else {
        throw AgentSkillPackageError("Skill package ZIP compression method is not supported on iOS yet")
      }
      let nameStart = cursor + 46
      let extraStart = nameStart + Int(nameLength)
      let commentStart = extraStart + Int(extraLength)
      let nextCursor = commentStart + Int(commentLength)
      guard rangeFits(start: nameStart, length: Int(nameLength), in: data),
            rangeFits(start: extraStart, length: Int(extraLength), in: data),
            rangeFits(start: commentStart, length: Int(commentLength), in: data),
            nextCursor <= centralOffset + centralSize else {
        throw AgentSkillPackageError("ZIP central directory entry is out of bounds")
      }
      guard let rawName = String(data: data.subdata(in: nameStart..<extraStart), encoding: .utf8) else {
        throw AgentSkillPackageError("ZIP entry name is not valid UTF-8")
      }
      let normalizedName = try normalizeEntry(rawName)
      let localOffset = Int(localOffsetValue)
      guard let dataOffset = zipEntryDataOffset(data, localOffset: localOffset),
            rangeFits(start: dataOffset, length: Int(compressed), in: data) else {
        throw AgentSkillPackageError("ZIP local entry is out of bounds")
      }
      entries.append(ZipEntry(
        path: normalizedName,
        directory: rawName.hasSuffix("/") || rawName.hasSuffix("\\"),
        method: method,
        uncompressedBytes: Int64(uncompressed),
        crc32: crc,
        dataOffset: dataOffset,
        dataLength: Int(compressed)
      ))
      cursor = nextCursor
    }
    return entries
  }

  private func normalizeEntry(_ rawName: String) throws -> String {
    let name = rawName
      .replacingOccurrences(of: "\\", with: "/")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .removingPrefix("./")
    let parts = name.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard !name.isEmpty,
          !name.hasPrefix("/"),
          name.range(of: #"^[A-Za-z]:.*"#, options: .regularExpression) == nil,
          !name.contains("%"),
          parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
      throw AgentSkillPackageError("Unsafe Skill package path: \(rawName)")
    }
    return name
  }

  private func rejectExecutable(_ name: String) throws {
    let lower = name.lowercased()
    if Self.executableExtensions.contains(where: { lower.hasSuffix($0) }) {
      throw AgentSkillPackageError("Executable content is not allowed in declarative Skill packages: \(name)")
    }
  }

  private func checkedAdd(_ left: Int64, _ right: Int64) -> Int64? {
    guard right >= 0, left <= Int64.max - right else {
      return nil
    }
    return left + right
  }

  private func readUInt16LE(_ data: Data, _ offset: Int) -> UInt16? {
    guard rangeFits(start: offset, length: 2, in: data) else { return nil }
    return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
  }

  private func readUInt32LE(_ data: Data, _ offset: Int) -> UInt32? {
    guard rangeFits(start: offset, length: 4, in: data) else { return nil }
    return UInt32(data[offset]) |
      (UInt32(data[offset + 1]) << 8) |
      (UInt32(data[offset + 2]) << 16) |
      (UInt32(data[offset + 3]) << 24)
  }

  private func rangeFits(start: Int, length: Int, in data: Data) -> Bool {
    start >= 0 && length >= 0 && start <= data.count && length <= data.count - start
  }

  private func endOfCentralDirectoryOffset(_ data: Data) -> Int? {
    guard data.count >= 22 else { return nil }
    let minimumOffset = max(0, data.count - 65_557)
    for offset in stride(from: data.count - 22, through: minimumOffset, by: -1) {
      if readUInt32LE(data, offset) == 0x06054b50 {
        return offset
      }
    }
    return nil
  }

  private func zipEntryDataOffset(_ data: Data, localOffset: Int) -> Int? {
    guard readUInt32LE(data, localOffset) == 0x04034b50,
          let nameLength = readUInt16LE(data, localOffset + 26),
          let extraLength = readUInt16LE(data, localOffset + 28) else {
      return nil
    }
    let dataOffset = localOffset + 30 + Int(nameLength) + Int(extraLength)
    return rangeFits(start: dataOffset, length: 0, in: data) ? dataOffset : nil
  }

  private func crc32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xffffffff
    for byte in data {
      let index = Int((crc ^ UInt32(byte)) & 0xff)
      crc = (crc >> 8) ^ Self.crc32Table[index]
    }
    return crc ^ 0xffffffff
  }

  static let manifestFile = "manifest.json"
  static let integrityFile = "integrity.json"
  static let maxPackageBytes = 16 * 1_024 * 1_024
  static let maxEntryBytes = 8 * 1_024 * 1_024
  static let maxExpandedBytes: Int64 = 24 * 1_024 * 1_024
  static let maxEntries = UInt16(128)

  private static let allowedPackageSources = Set(["third_party", "official_store", "repository", "url", "conversation"])
  private static let executableExtensions = Set([
    ".exe", ".dll", ".so", ".dylib", ".apk", ".jar", ".dex", ".class",
    ".sh", ".bash", ".cmd", ".bat", ".ps1", ".py", ".pyc", ".js", ".mjs",
    ".ts", ".kt", ".kts", ".java", ".rb", ".php", ".pl", ".lua", ".wasm"
  ])
  private static let crc32Table: [UInt32] = {
    (0..<256).map { value -> UInt32 in
      var crc = UInt32(value)
      for _ in 0..<8 {
        if crc & 1 == 1 {
          crc = (crc >> 1) ^ 0xedb88320
        } else {
          crc >>= 1
        }
      }
      return crc
    }
  }()
}

private extension String {
  func removingPrefix(_ prefix: String) -> String {
    hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
  }
}
