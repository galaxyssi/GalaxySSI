import CryptoKit
import Foundation

struct LocalModelInstallMetadata: Codable, Equatable {
  var profileId: String
  var repositoryId: String
  var fileName: String
  var expectedSizeBytes: Int64
  var sha256: String
  var installedAtEpochMillis: Int64
  var sourceURL: String
  var fileModifiedAtEpochMillis: Int64
}

struct LocalModelStorageSnapshot: Equatable {
  var installed: Bool
  var fileURL: URL?
  var metadata: LocalModelInstallMetadata?
  var detail: String
}

final class LocalModelRuntimeStorage {
  private let fileManager: FileManager
  private let rootURL: URL

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
    let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
    rootURL = support.appendingPathComponent("SignalASI/LocalModels", isDirectory: true)
  }

  func finalFileURL(for profile: LocalModelRuntimeProfile) -> URL {
    let key = safeComponent("\(profile.repositoryId)_\(profile.fileName)_\(profile.sha256.prefix(12))")
    return rootURL
      .appendingPathComponent("Hub", isDirectory: true)
      .appendingPathComponent(key, isDirectory: false)
  }

  func metadataFileURL(for profile: LocalModelRuntimeProfile) -> URL {
    finalFileURL(for: profile)
      .deletingPathExtension()
      .appendingPathExtension("installation.json")
  }

  func availableBytes() -> Int64 {
    let values = try? rootURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    return Int64(max(0, values?.volumeAvailableCapacityForImportantUsage ?? 0))
  }

  func inspect(_ profile: LocalModelRuntimeProfile) -> LocalModelStorageSnapshot {
    let file = finalFileURL(for: profile)
    let metadata = readMetadata(for: profile)
    guard let metadata else {
      return LocalModelStorageSnapshot(
        installed: false,
        fileURL: fileIfPresent(file),
        metadata: nil,
        detail: "Installed model metadata is missing"
      )
    }
    guard metadata.matches(profile),
          let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
          values.isRegularFile == true,
          Int64(values.fileSize ?? 0) == profile.expectedModelFileBytes,
          Int64(((values.contentModificationDate?.timeIntervalSince1970 ?? 0) * 1_000).rounded()) == metadata.fileModifiedAtEpochMillis else {
      return LocalModelStorageSnapshot(
        installed: false,
        fileURL: fileIfPresent(file),
        metadata: metadata,
        detail: "Installed model metadata is invalid"
      )
    }
    return LocalModelStorageSnapshot(installed: true, fileURL: file, metadata: metadata, detail: "")
  }

  func installVerifiedFile(
    _ temporaryURL: URL,
    profile: LocalModelRuntimeProfile,
    downloadURL: URL
  ) throws -> URL {
    let destination = finalFileURL(for: profile)
    try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? fileManager.removeItem(at: destination)
    try fileManager.moveItem(at: temporaryURL, to: destination)
    let modifiedAt = fileModifiedEpochMillis(destination)
    let metadata = LocalModelInstallMetadata(
      profileId: profile.id,
      repositoryId: profile.repositoryId,
      fileName: profile.fileName,
      expectedSizeBytes: profile.expectedModelFileBytes,
      sha256: profile.sha256,
      installedAtEpochMillis: Int64(Date().timeIntervalSince1970 * 1_000),
      sourceURL: String(downloadURL.absoluteString.prefix(1_024)),
      fileModifiedAtEpochMillis: modifiedAt
    )
    let metadataURL = metadataFileURL(for: profile)
    let data = try JSONEncoder().encode(metadata)
    try data.write(to: metadataURL, options: .atomic)
    return destination
  }

  func verifyForNativeLoad(_ profile: LocalModelRuntimeProfile) throws -> URL {
    let snapshot = inspect(profile)
    guard snapshot.installed, let file = snapshot.fileURL else {
      throw LocalModelRuntimeStorageError.modelNotInstalled
    }
    guard try Self.sha256(fileURL: file) == profile.sha256.lowercased() else {
      throw LocalModelRuntimeStorageError.sha256Mismatch
    }
    return file
  }

  func delete(_ profile: LocalModelRuntimeProfile) throws {
    try? fileManager.removeItem(at: finalFileURL(for: profile))
    try? fileManager.removeItem(at: metadataFileURL(for: profile))
  }

  static func sha256(fileURL: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: fileURL)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
      hasher.update(data: chunk)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  private func readMetadata(for profile: LocalModelRuntimeProfile) -> LocalModelInstallMetadata? {
    guard let data = try? Data(contentsOf: metadataFileURL(for: profile)) else { return nil }
    return try? JSONDecoder().decode(LocalModelInstallMetadata.self, from: data)
  }

  private func fileIfPresent(_ url: URL) -> URL? {
    fileManager.fileExists(atPath: url.path) ? url : nil
  }

  private func fileModifiedEpochMillis(_ url: URL) -> Int64 {
    guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
          let date = values.contentModificationDate else {
      return 0
    }
    return Int64((date.timeIntervalSince1970 * 1_000).rounded())
  }

  private func safeComponent(_ value: String) -> String {
    let scalars = value.unicodeScalars.map { scalar -> Character in
      let number = scalar.value
      let allowed = number == 46 || number == 45 || number == 95 ||
        (48...57).contains(number) || (65...90).contains(number) || (97...122).contains(number)
      return allowed ? Character(scalar) : "_"
    }
    return String(scalars).isEmpty ? "model.gguf" : String(scalars)
  }
}

enum LocalModelRuntimeStorageError: LocalizedError {
  case modelNotInstalled
  case sha256Mismatch

  var errorDescription: String? {
    switch self {
    case .modelNotInstalled:
      return "Local model is not installed"
    case .sha256Mismatch:
      return "Installed model failed SHA-256 verification"
    }
  }
}

private extension LocalModelInstallMetadata {
  func matches(_ profile: LocalModelRuntimeProfile) -> Bool {
    profileId == profile.id &&
      repositoryId == profile.repositoryId &&
      fileName == profile.fileName &&
      expectedSizeBytes == profile.expectedModelFileBytes &&
      sha256 == profile.sha256.lowercased()
  }
}
