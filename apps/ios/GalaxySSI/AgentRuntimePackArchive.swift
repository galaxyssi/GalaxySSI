import Foundation

struct AgentRuntimePackArchiveEntry: Equatable {
  var path: String
  var isDirectory: Bool
  var method: UInt16
  var uncompressedBytes: Int64
  var crc32: UInt32
  var dataRange: Range<Int>
}

struct AgentRuntimePackArchiveError: LocalizedError, Equatable {
  var message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? { message }
}

enum AgentRuntimePackArchiveReader {
  static let maximumEntries = 2_048
  static let maximumArchiveBytes: Int64 = 6 * 1_024 * 1_024 * 1_024
  static let maximumExpandedBytes: Int64 = 12 * 1_024 * 1_024 * 1_024

  static func extract(
    archive: URL,
    to destination: URL,
    fileManager: FileManager = .default,
    onProgress: (Int64) -> Void = { _ in }
  ) throws -> Int64 {
    let attributes = try fileManager.attributesOfItem(atPath: archive.path)
    let archiveBytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
    guard (1...maximumArchiveBytes).contains(archiveBytes) else {
      throw AgentRuntimePackArchiveError("Runtime pack archive exceeds the size limit")
    }
    let data = try Data(contentsOf: archive, options: [.mappedIfSafe])
    guard Int64(data.count) == archiveBytes else {
      throw AgentRuntimePackArchiveError("Runtime pack archive changed while it was being read")
    }
    let entries = try inspect(data)
    try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
    var expandedBytes: Int64 = 0
    for entry in entries {
      let target = entry.path.split(separator: "/").reduce(destination) { partial, segment in
        partial.appendingPathComponent(String(segment), isDirectory: false)
      }
      if entry.isDirectory {
        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        continue
      }
      let content = try extractEntry(entry, from: data)
      let nextBytes = expandedBytes <= Int64.max - Int64(content.count)
        ? expandedBytes + Int64(content.count)
        : Int64.max
      guard nextBytes <= maximumExpandedBytes else {
        throw AgentRuntimePackArchiveError("Runtime pack content exceeds the size limit")
      }
      expandedBytes = nextBytes
      try fileManager.createDirectory(
        at: target.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try content.write(to: target, options: [.atomic])
      onProgress(expandedBytes)
    }
    guard fileManager.fileExists(atPath: destination.appendingPathComponent("manifest.json").path) else {
      throw AgentRuntimePackArchiveError("Runtime pack manifest is missing")
    }
    return expandedBytes
  }

  static func inspect(_ data: Data) throws -> [AgentRuntimePackArchiveEntry] {
    guard let endOffset = endOfCentralDirectoryOffset(in: data),
          let disk = uint16(data, at: endOffset + 4),
          let centralDisk = uint16(data, at: endOffset + 6),
          let diskCount = uint16(data, at: endOffset + 8),
          let entryCount = uint16(data, at: endOffset + 10),
          let centralSize = uint32(data, at: endOffset + 12),
          let centralOffset = uint32(data, at: endOffset + 16) else {
      throw AgentRuntimePackArchiveError("ZIP central directory was not found")
    }
    guard disk == 0, centralDisk == 0, diskCount == entryCount else {
      throw AgentRuntimePackArchiveError("Multi-disk runtime pack archives are not supported")
    }
    guard entryCount > 0, Int(entryCount) <= maximumEntries else {
      throw AgentRuntimePackArchiveError("Runtime pack contains too many files")
    }
    let directoryStart = Int(centralOffset)
    let directoryLength = Int(centralSize)
    guard rangeFits(start: directoryStart, length: directoryLength, in: data) else {
      throw AgentRuntimePackArchiveError("ZIP central directory is out of bounds")
    }

    var entries: [AgentRuntimePackArchiveEntry] = []
    var seen = Set<String>()
    var cursor = directoryStart
    for _ in 0..<Int(entryCount) {
      guard uint32(data, at: cursor) == 0x02014b50,
            let flags = uint16(data, at: cursor + 8),
            let method = uint16(data, at: cursor + 10),
            let crc = uint32(data, at: cursor + 16),
            let compressedSize = uint32(data, at: cursor + 20),
            let uncompressedSize = uint32(data, at: cursor + 24),
            let nameLength = uint16(data, at: cursor + 28),
            let extraLength = uint16(data, at: cursor + 30),
            let commentLength = uint16(data, at: cursor + 32),
            let externalAttributes = uint32(data, at: cursor + 38),
            let localOffset = uint32(data, at: cursor + 42) else {
        throw AgentRuntimePackArchiveError("ZIP central directory entry is invalid")
      }
      guard flags & 0x0001 == 0, flags & 0x0008 == 0 else {
        throw AgentRuntimePackArchiveError("Encrypted or streaming ZIP entries are not supported")
      }
      guard method == 0 || method == 8 else {
        throw AgentRuntimePackArchiveError("Runtime pack ZIP compression method is not supported")
      }
      let nameStart = cursor + 46
      let extraStart = nameStart + Int(nameLength)
      let commentStart = extraStart + Int(extraLength)
      let nextCursor = commentStart + Int(commentLength)
      guard nextCursor <= directoryStart + directoryLength,
            rangeFits(start: nameStart, length: Int(nameLength), in: data),
            rangeFits(start: extraStart, length: Int(extraLength), in: data),
            rangeFits(start: commentStart, length: Int(commentLength), in: data),
            let rawName = String(data: data.subdata(in: nameStart..<extraStart), encoding: .utf8) else {
        throw AgentRuntimePackArchiveError("Runtime pack ZIP entry name is invalid")
      }
      let (path, isDirectory) = try normalizePath(rawName)
      guard seen.insert(path).inserted else {
        throw AgentRuntimePackArchiveError("Runtime pack contains a duplicate entry: \(path)")
      }
      let unixMode = (externalAttributes >> 16) & 0xF000
      guard unixMode != 0xA000 else {
        throw AgentRuntimePackArchiveError("Runtime pack symbolic links are not supported")
      }
      let dataOffset = try localDataOffset(data, at: Int(localOffset))
      let compressedLength = Int(compressedSize)
      guard rangeFits(start: dataOffset, length: compressedLength, in: data) else {
        throw AgentRuntimePackArchiveError("Runtime pack ZIP entry is out of bounds")
      }
      entries.append(AgentRuntimePackArchiveEntry(
        path: path,
        isDirectory: isDirectory,
        method: method,
        uncompressedBytes: Int64(uncompressedSize),
        crc32: crc,
        dataRange: dataOffset..<(dataOffset + compressedLength)
      ))
      cursor = nextCursor
    }
    return entries
  }

  private static func extractEntry(
    _ entry: AgentRuntimePackArchiveEntry,
    from data: Data
  ) throws -> Data {
    guard entry.uncompressedBytes <= maximumExpandedBytes,
          rangeFits(start: entry.dataRange.lowerBound, length: entry.dataRange.count, in: data) else {
      throw AgentRuntimePackArchiveError("Runtime pack entry exceeds the size limit")
    }
    let compressed = data.subdata(in: entry.dataRange)
    let content: Data
    switch entry.method {
    case 0:
      content = compressed
    case 8:
      do {
        content = try AgentMcpPackageInstaller.inflateDeflate(
          compressed,
          expectedBytes: entry.uncompressedBytes,
          maxBytes: Int(maximumExpandedBytes)
        )
      } catch {
        throw AgentRuntimePackArchiveError("Runtime pack ZIP entry could not be decompressed")
      }
    default:
      throw AgentRuntimePackArchiveError("Runtime pack ZIP compression method is not supported")
    }
    guard Int64(content.count) == entry.uncompressedBytes else {
      throw AgentRuntimePackArchiveError("Runtime pack entry size changed during extraction")
    }
    guard crc32(content) == entry.crc32 else {
      throw AgentRuntimePackArchiveError("Runtime pack entry CRC did not match")
    }
    return content
  }

  private static func normalizePath(_ raw: String) throws -> (String, Bool) {
    let isDirectory = raw.hasSuffix("/")
    guard !raw.contains("\\"), !raw.contains("%"), !raw.hasPrefix("/"),
          raw.range(of: #"^[A-Za-z]:"#, options: .regularExpression) == nil else {
      throw AgentRuntimePackArchiveError("Runtime pack contains an unsafe path")
    }
    let parts = raw.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    let meaningfulParts = isDirectory ? parts.dropLast() : parts[...]
    guard !meaningfulParts.isEmpty,
          meaningfulParts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
      throw AgentRuntimePackArchiveError("Runtime pack contains an unsafe path")
    }
    return (meaningfulParts.joined(separator: "/") + (isDirectory ? "/" : ""), isDirectory)
  }

  private static func localDataOffset(_ data: Data, at offset: Int) throws -> Int {
    guard uint32(data, at: offset) == 0x04034b50,
          let nameLength = uint16(data, at: offset + 26),
          let extraLength = uint16(data, at: offset + 28) else {
      throw AgentRuntimePackArchiveError("Runtime pack ZIP local entry is invalid")
    }
    let result = offset + 30 + Int(nameLength) + Int(extraLength)
    guard result >= offset, result <= data.count else {
      throw AgentRuntimePackArchiveError("Runtime pack ZIP local entry is out of bounds")
    }
    return result
  }

  private static func endOfCentralDirectoryOffset(in data: Data) -> Int? {
    guard data.count >= 22 else { return nil }
    let lowerBound = max(0, data.count - 22 - 65_535)
    for offset in stride(from: data.count - 22, through: lowerBound, by: -1) {
      if uint32(data, at: offset) == 0x06054b50 {
        return offset
      }
    }
    return nil
  }

  private static func rangeFits(start: Int, length: Int, in data: Data) -> Bool {
    start >= 0 && length >= 0 && start <= data.count && length <= data.count - start
  }

  private static func uint16(_ data: Data, at offset: Int) -> UInt16? {
    guard rangeFits(start: offset, length: 2, in: data) else { return nil }
    return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
  }

  private static func uint32(_ data: Data, at offset: Int) -> UInt32? {
    guard rangeFits(start: offset, length: 4, in: data) else { return nil }
    return UInt32(data[offset]) |
      UInt32(data[offset + 1]) << 8 |
      UInt32(data[offset + 2]) << 16 |
      UInt32(data[offset + 3]) << 24
  }

  private static func crc32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in data {
      crc ^= UInt32(byte)
      for _ in 0..<8 {
        crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
      }
    }
    return crc ^ 0xFFFF_FFFF
  }
}
