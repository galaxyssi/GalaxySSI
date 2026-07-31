import Foundation

enum PcmWaveFileAdapter {
  static func write(
    snapshot: PcmSnapshot,
    directory: URL,
    stem: String,
    fileManager: FileManager = .default
  ) throws -> URL {
    precondition(!snapshot.samples.isEmpty, "PCM snapshot is empty")
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    let safeStem = sanitizedStem(stem)
    let target = directory.appendingPathComponent("\(safeStem).wav")
    let temporary = directory.appendingPathComponent("\(safeStem).wav.partial")
    let data = waveData(snapshot: snapshot)
    try data.write(to: temporary, options: .atomic)
    if fileManager.fileExists(atPath: target.path) {
      try fileManager.removeItem(at: target)
    }
    try fileManager.moveItem(at: temporary, to: target)
    return target
  }

  static func waveData(snapshot: PcmSnapshot) -> Data {
    let dataByteCount = snapshot.samples.count * 2
    var data = Data()
    data.appendAscii("RIFF")
    data.appendLe32(UInt32(36 + dataByteCount))
    data.appendAscii("WAVEfmt ")
    data.appendLe32(16)
    data.appendLe16(1)
    data.appendLe16(1)
    data.appendLe32(UInt32(max(1, snapshot.sampleRateHz)))
    data.appendLe32(UInt32(max(1, snapshot.sampleRateHz) * 2))
    data.appendLe16(2)
    data.appendLe16(16)
    data.appendAscii("data")
    data.appendLe32(UInt32(dataByteCount))
    snapshot.samples.forEach { data.appendLe16(UInt16(bitPattern: $0)) }
    return data
  }

  private static func sanitizedStem(_ value: String) -> String {
    let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
    let safe = value.map { allowed.contains($0) ? $0 : "_" }
    let trimmed = String(safe.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "voice" : trimmed
  }
}

private extension Data {
  mutating func appendAscii(_ value: String) {
    append(contentsOf: value.utf8)
  }

  mutating func appendLe16(_ value: UInt16) {
    append(UInt8(value & 0xff))
    append(UInt8((value >> 8) & 0xff))
  }

  mutating func appendLe32(_ value: UInt32) {
    append(UInt8(value & 0xff))
    append(UInt8((value >> 8) & 0xff))
    append(UInt8((value >> 16) & 0xff))
    append(UInt8((value >> 24) & 0xff))
  }
}
