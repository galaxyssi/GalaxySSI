import Foundation

final class VoiceWhisperBenchmarkStore {
  private let fileURL: URL
  private let fileManager: FileManager
  private let lock = NSLock()

  init(fileURL: URL, fileManager: FileManager = .default) {
    self.fileURL = fileURL.standardizedFileURL
    self.fileManager = fileManager
  }

  func find(_ key: VoiceWhisperBenchmarkKey) -> VoiceWhisperBenchmarkRecord? {
    locked {
      readAll().first { $0.certification.key == key }
    }
  }

  func latestForProfile(_ profileId: String) -> VoiceWhisperBenchmarkRecord? {
    let cleanProfileId = profileId.trimmingCharacters(in: .whitespacesAndNewlines)
    return locked {
      readAll()
        .filter { $0.certification.key.modelProfileId == cleanProfileId }
        .max { $0.certification.createdAtEpochMillis < $1.certification.createdAtEpochMillis }
    }
  }

  func save(_ record: VoiceWhisperBenchmarkRecord) throws {
    try locked {
      var records = readAll().filter {
        $0.certification.key.stableId != record.certification.key.stableId
      }
      records.append(record)
      let bounded = Array(
        records
          .sorted { $0.certification.createdAtEpochMillis > $1.certification.createdAtEpochMillis }
          .prefix(Self.maxRecords)
      )
      try writeAll(bounded)
    }
  }

  func removeForProfile(_ profileId: String) throws {
    let cleanProfileId = profileId.trimmingCharacters(in: .whitespacesAndNewlines)
    try locked {
      try writeAll(readAll().filter { $0.certification.key.modelProfileId != cleanProfileId })
    }
  }

  func clear() {
    locked {
      try? fileManager.removeItem(at: fileURL)
      try? fileManager.removeItem(at: partialFileURL)
    }
  }

  private func readAll() -> [VoiceWhisperBenchmarkRecord] {
    guard fileManager.fileExists(atPath: fileURL.path),
      let data = try? Data(contentsOf: fileURL),
      let document = try? JSONDecoder().decode(Document.self, from: data),
      document.schemaVersion == Self.schemaVersion else {
      return []
    }
    return Array(document.records.prefix(Self.maxRecords))
  }

  private func writeAll(_ records: [VoiceWhisperBenchmarkRecord]) throws {
    let directory = fileURL.deletingLastPathComponent()
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    try? fileManager.removeItem(at: partialFileURL)
    let document = Document(
      schemaVersion: Self.schemaVersion,
      records: Array(records.prefix(Self.maxRecords))
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(document)
    try data.write(to: partialFileURL, options: [.atomic])
    if fileManager.fileExists(atPath: fileURL.path) {
      _ = try fileManager.replaceItemAt(fileURL, withItemAt: partialFileURL, backupItemName: nil, options: .usingNewMetadataOnly)
    } else {
      try fileManager.moveItem(at: partialFileURL, to: fileURL)
    }
  }

  private var partialFileURL: URL {
    fileURL.deletingLastPathComponent()
      .appendingPathComponent("\(fileURL.lastPathComponent).partial", isDirectory: false)
  }

  private func locked<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }

  private struct Document: Codable {
    var schemaVersion: Int
    var records: [VoiceWhisperBenchmarkRecord]
  }

  private static let schemaVersion = 1
  private static let maxRecords = 64
}
