import CryptoKit
import Foundation

enum AgentDesktopArtifactActionError: Error, Equatable {
  case invalid(String)
  case unavailable(String)
  case unsafeArchive(String)
}

struct AgentZipPreviewEntry: Equatable {
  var path: String
  var sizeBytes: Int64

  var displayText: String {
    sizeBytes >= 0 ? "\(path)  \(AgentDesktopArtifactStore.humanSize(sizeBytes))" : path
  }
}

enum AgentDesktopArtifactActions {
  static let maximumTextPreviewBytes = 1 * 1_024 * 1_024
  static let maximumArchiveEntries = 500
  static let maximumExtractedBytes: Int64 = 128 * 1_024 * 1_024

  static func readTextPreview(source: URL, maximumBytes: Int = maximumTextPreviewBytes) throws -> String {
    let data = try Data(contentsOf: source)
    guard data.count <= maximumBytes else {
      throw AgentDesktopArtifactActionError.invalid("File is too large to preview")
    }
    guard !data.contains(0) else {
      throw AgentDesktopArtifactActionError.invalid("Binary file cannot be shown as text")
    }
    guard let text = String(data: data, encoding: .utf8) else {
      throw AgentDesktopArtifactActionError.invalid("File is not valid UTF-8 text")
    }
    return text
  }

  static func archivePreview(source: URL, maximumEntries: Int = maximumArchiveEntries) throws -> [String] {
    try inspectZip(source: source, maximumEntries: maximumEntries).map(\.displayText)
  }

  static func extractZip(source: URL, to destinationRoot: URL) throws -> [URL] {
    let entries = try inspectZip(source: source, maximumEntries: maximumArchiveEntries)
    let data = try Data(contentsOf: source)
    var created: [URL] = []
    var extractedBytes: Int64 = 0
    for entry in entries {
      let parts = try safeArchiveParts(entry.path)
      let target = parts.reduce(destinationRoot.standardizedFileURL) { partial, segment in
        partial.appendingPathComponent(segment, isDirectory: false)
      }.standardizedFileURL
      guard target.path.hasPrefix(destinationRoot.standardizedFileURL.path + "/") else {
        throw AgentDesktopArtifactActionError.unsafeArchive("Archive entry escapes the destination")
      }
      let entryData = try extract(entry, from: data)
      extractedBytes += Int64(entryData.count)
      guard extractedBytes <= maximumExtractedBytes else {
        throw AgentDesktopArtifactActionError.unsafeArchive("Archive expands beyond the safety limit")
      }
      try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
      try entryData.write(to: target, options: [.atomic])
      created.append(target)
    }
    return created
  }

  static func extractStoredZip(source: URL, to destinationRoot: URL) throws -> [URL] {
    try extractZip(source: source, to: destinationRoot)
  }

  static func compressToStoredZip(source: URL, displayName: String? = nil) throws -> Data {
    guard FileManager.default.fileExists(atPath: source.path) else {
      throw AgentDesktopArtifactActionError.unavailable("Source file is unavailable")
    }
    let data = try Data(contentsOf: source)
    let name = AgentDesktopArtifactStore.safeFileName(displayName ?? source.lastPathComponent)
    return AgentRuntimeProjectArchiveBuilder.buildStoredZip(entries: [
      AgentRuntimeProjectArchiveEntry(path: name, data: data)
    ])
  }

  static func copyToUserSelectedDestination(source: URL, destination: URL) throws {
    guard FileManager.default.fileExists(atPath: source.path) else {
      throw AgentDesktopArtifactActionError.unavailable("Source file is unavailable")
    }
    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: destination.path) {
      try FileManager.default.removeItem(at: destination)
    }
    try FileManager.default.copyItem(at: source, to: destination)
  }

  static func sha256(source: URL) throws -> String {
    let data = try Data(contentsOf: source)
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func inspectZip(source: URL, maximumEntries: Int) throws -> [StoredZipEntry] {
    guard source.pathExtension.lowercased() == "zip" else {
      throw AgentDesktopArtifactActionError.invalid("This archive format cannot be previewed")
    }
    let data = try Data(contentsOf: source)
    guard let eocd = endOfCentralDirectoryOffset(in: data),
          let disk = data.uint16LE(at: eocd + 4),
          let centralDisk = data.uint16LE(at: eocd + 6),
          let diskEntries = data.uint16LE(at: eocd + 8),
          let entryCount = data.uint16LE(at: eocd + 10),
          let centralSize = data.uint32LE(at: eocd + 12),
          let centralOffset = data.uint32LE(at: eocd + 16) else {
      throw AgentDesktopArtifactActionError.unsafeArchive("ZIP central directory was not found")
    }
    guard disk == 0, centralDisk == 0, diskEntries == entryCount else {
      throw AgentDesktopArtifactActionError.unsafeArchive("Multi-disk ZIP archives are not supported")
    }
    guard entryCount != UInt16.max, centralSize != UInt32.max, centralOffset != UInt32.max else {
      throw AgentDesktopArtifactActionError.unsafeArchive("ZIP64 archives are not supported")
    }
    let count = Int(entryCount)
    guard count <= maximumEntries else {
      throw AgentDesktopArtifactActionError.unsafeArchive("Archive contains too many files")
    }
    let directoryOffset = Int(centralOffset)
    let directorySize = Int(centralSize)
    guard data.rangeFits(start: directoryOffset, length: directorySize) else {
      throw AgentDesktopArtifactActionError.unsafeArchive("ZIP central directory is truncated")
    }

    var cursor = directoryOffset
    var entries: [StoredZipEntry] = []
    var seen = Set<String>()
    for _ in 0..<count {
      guard data.uint32LE(at: cursor) == 0x02014b50,
            let flags = data.uint16LE(at: cursor + 8),
            let method = data.uint16LE(at: cursor + 10),
            let crc32 = data.uint32LE(at: cursor + 16),
            let compressedSize = data.uint32LE(at: cursor + 20),
            let uncompressedSize = data.uint32LE(at: cursor + 24),
            let nameLength = data.uint16LE(at: cursor + 28),
            let extraLength = data.uint16LE(at: cursor + 30),
            let commentLength = data.uint16LE(at: cursor + 32),
            let localOffset = data.uint32LE(at: cursor + 42) else {
        throw AgentDesktopArtifactActionError.unsafeArchive("ZIP central directory entry is invalid")
      }
      guard flags & 0x0001 == 0 else {
        throw AgentDesktopArtifactActionError.unsafeArchive("Encrypted ZIP entries are not supported")
      }
      guard method == 0 || method == 8 else {
        throw AgentDesktopArtifactActionError.unsafeArchive("ZIP compression method is not supported")
      }
      let nameStart = cursor + 46
      let nameEnd = nameStart + Int(nameLength)
      let next = nameEnd + Int(extraLength) + Int(commentLength)
      guard next <= directoryOffset + directorySize,
            data.rangeFits(start: nameStart, length: Int(nameLength)),
            let rawPath = String(data: data.subdata(in: nameStart..<nameEnd), encoding: .utf8) else {
        throw AgentDesktopArtifactActionError.unsafeArchive("ZIP entry header is truncated")
      }
      let isDirectory = rawPath.hasSuffix("/") || rawPath.hasSuffix("\\")
      let cleanPath = try safeArchiveParts(rawPath).joined(separator: "/")
      guard seen.insert(cleanPath).inserted else {
        throw AgentDesktopArtifactActionError.unsafeArchive("Archive contains duplicate entries")
      }
      if !isDirectory {
        guard Int64(uncompressedSize) <= maximumExtractedBytes else {
          throw AgentDesktopArtifactActionError.unsafeArchive("Archive entry exceeds the safety limit")
        }
        let dataOffset = try localDataOffset(data, at: Int(localOffset))
        let dataLength = Int(compressedSize)
        guard data.rangeFits(start: dataOffset, length: dataLength) else {
          throw AgentDesktopArtifactActionError.unsafeArchive("ZIP entry data is truncated")
        }
        entries.append(StoredZipEntry(
          path: cleanPath,
          sizeBytes: Int64(uncompressedSize),
          method: method,
          crc32: crc32,
          dataRange: dataOffset..<(dataOffset + dataLength)
        ))
      }
      cursor = next
    }
    return entries
  }

  private static func extract(_ entry: StoredZipEntry, from archive: Data) throws -> Data {
    let raw = archive.subdata(in: entry.dataRange)
    let content: Data
    switch entry.method {
    case 0:
      content = raw
    case 8:
      do {
        content = try AgentMcpPackageInstaller.inflateDeflate(
          raw,
          expectedBytes: entry.sizeBytes,
          maxBytes: Int(maximumExtractedBytes)
        )
      } catch {
        throw AgentDesktopArtifactActionError.unsafeArchive("ZIP entry could not be decompressed")
      }
    default:
      throw AgentDesktopArtifactActionError.unsafeArchive("ZIP compression method is not supported")
    }
    guard Int64(content.count) == entry.sizeBytes, crc32(content) == entry.crc32 else {
      throw AgentDesktopArtifactActionError.unsafeArchive("ZIP entry integrity check failed")
    }
    return content
  }

  private static func localDataOffset(_ data: Data, at offset: Int) throws -> Int {
    guard data.uint32LE(at: offset) == 0x04034b50,
          let nameLength = data.uint16LE(at: offset + 26),
          let extraLength = data.uint16LE(at: offset + 28) else {
      throw AgentDesktopArtifactActionError.unsafeArchive("ZIP local entry is invalid")
    }
    let result = offset + 30 + Int(nameLength) + Int(extraLength)
    guard result >= offset, result <= data.count else {
      throw AgentDesktopArtifactActionError.unsafeArchive("ZIP local entry is truncated")
    }
    return result
  }

  private static func endOfCentralDirectoryOffset(in data: Data) -> Int? {
    guard data.count >= 22 else { return nil }
    let lowerBound = max(0, data.count - 22 - 65_535)
    for offset in stride(from: data.count - 22, through: lowerBound, by: -1) {
      if data.uint32LE(at: offset) == 0x06054b50 { return offset }
    }
    return nil
  }

  private static func crc32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in data {
      crc ^= UInt32(byte)
      for _ in 0..<8 {
        crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
      }
    }
    return ~crc
  }

  private static func safeArchiveParts(_ path: String) throws -> [String] {
    let normalized = path.replacingOccurrences(of: "\\", with: "/")
    guard !normalized.hasPrefix("/"),
      normalized.range(of: #"^[A-Za-z]:"# , options: .regularExpression) == nil else {
      throw AgentDesktopArtifactActionError.unsafeArchive("Archive entry uses an absolute path")
    }
    let parts = normalized.split(separator: "/").map(String.init).filter { !$0.isEmpty }
    guard !parts.isEmpty, parts.allSatisfy({ $0 != "." && $0 != ".." }) else {
      throw AgentDesktopArtifactActionError.unsafeArchive("Archive entry uses unsafe path segments")
    }
    return parts.map { AgentDesktopArtifactStore.safeFileName($0) }
  }
}

private struct StoredZipEntry: Equatable {
  var path: String
  var sizeBytes: Int64
  var method: UInt16
  var crc32: UInt32
  var dataRange: Range<Int>

  var displayText: String {
    sizeBytes >= 0 ? "\(path)  \(AgentDesktopArtifactStore.humanSize(sizeBytes))" : path
  }
}

private extension Data {
  func rangeFits(start: Int, length: Int) -> Bool {
    start >= 0 && length >= 0 && start <= count && length <= count - start
  }

  func uint16LE(at offset: Int) -> UInt16? {
    guard rangeFits(start: offset, length: 2) else { return nil }
    return UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
  }

  func uint32LE(at offset: Int) -> UInt32? {
    guard rangeFits(start: offset, length: 4) else { return nil }
    return UInt32(self[offset]) |
      UInt32(self[offset + 1]) << 8 |
      UInt32(self[offset + 2]) << 16 |
      UInt32(self[offset + 3]) << 24
  }
}
