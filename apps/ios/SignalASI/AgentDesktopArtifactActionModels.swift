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
    try inspectStoredZip(source: source, maximumEntries: maximumEntries).map(\.displayText)
  }

  static func extractStoredZip(source: URL, to destinationRoot: URL) throws -> [URL] {
    let entries = try inspectStoredZip(source: source, maximumEntries: maximumArchiveEntries)
    let data = try Data(contentsOf: source)
    var created: [URL] = []
    var extractedBytes: Int64 = 0
    for entry in entries {
      guard let range = entry.dataRange else {
        continue
      }
      let parts = try safeArchiveParts(entry.path)
      let target = parts.reduce(destinationRoot.standardizedFileURL) { partial, segment in
        partial.appendingPathComponent(segment, isDirectory: false)
      }.standardizedFileURL
      guard target.path.hasPrefix(destinationRoot.standardizedFileURL.path + "/") else {
        throw AgentDesktopArtifactActionError.unsafeArchive("Archive entry escapes the destination")
      }
      let entryData = data.subdata(in: range)
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

  private static func inspectStoredZip(source: URL, maximumEntries: Int) throws -> [StoredZipEntry] {
    guard source.pathExtension.lowercased() == "zip" else {
      throw AgentDesktopArtifactActionError.invalid("This archive format cannot be previewed")
    }
    let data = try Data(contentsOf: source)
    var entries: [StoredZipEntry] = []
    var offset = 0
    while offset + 30 <= data.count && entries.count < maximumEntries {
      guard data.uint32LE(at: offset) == 0x04034b50 else {
        break
      }
      let flags = data.uint16LE(at: offset + 6)
      let method = data.uint16LE(at: offset + 8)
      let compressedSize = Int(data.uint32LE(at: offset + 18))
      let uncompressedSize = Int64(data.uint32LE(at: offset + 22))
      let nameLength = Int(data.uint16LE(at: offset + 26))
      let extraLength = Int(data.uint16LE(at: offset + 28))
      guard flags & 0x0008 == 0 else {
        throw AgentDesktopArtifactActionError.unsafeArchive("ZIP data descriptors are not supported")
      }
      guard method == 0 else {
        throw AgentDesktopArtifactActionError.unsafeArchive("Only stored ZIP entries can be inspected on-device")
      }
      let nameStart = offset + 30
      let nameEnd = nameStart + nameLength
      let dataStart = nameEnd + extraLength
      let dataEnd = dataStart + compressedSize
      guard nameEnd <= data.count, dataEnd <= data.count,
        let path = String(data: data.subdata(in: nameStart..<nameEnd), encoding: .utf8) else {
        throw AgentDesktopArtifactActionError.unsafeArchive("ZIP entry header is truncated")
      }
      let cleanPath = try safeArchiveParts(path).joined(separator: "/")
      if !cleanPath.hasSuffix("/") {
        entries.append(
          StoredZipEntry(path: cleanPath, sizeBytes: uncompressedSize, dataRange: dataStart..<dataEnd)
        )
      }
      offset = dataEnd
    }
    return entries
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
  var dataRange: Range<Int>?

  var displayText: String {
    sizeBytes >= 0 ? "\(path)  \(AgentDesktopArtifactStore.humanSize(sizeBytes))" : path
  }
}

private extension Data {
  func uint16LE(at offset: Int) -> UInt16 {
    UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
  }

  func uint32LE(at offset: Int) -> UInt32 {
    UInt32(self[offset]) |
      UInt32(self[offset + 1]) << 8 |
      UInt32(self[offset + 2]) << 16 |
      UInt32(self[offset + 3]) << 24
  }
}
