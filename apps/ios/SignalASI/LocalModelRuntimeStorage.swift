import CryptoKit
import Foundation

struct LocalModelInstallMetadata: Codable, Equatable {
  var profileId: String
  var repositoryId: String
  var fileName: String
  var sourceHub: LocalModelHubSource
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
    let key = safeComponent("\(profile.sourceHub.rawValue)_\(profile.repositoryId)_\(profile.fileName)_\(profile.sha256.prefix(12))")
    return rootURL
      .appendingPathComponent("Hub", isDirectory: true)
      .appendingPathComponent(key, isDirectory: false)
  }

  func metadataFileURL(for profile: LocalModelRuntimeProfile) -> URL {
    finalFileURL(for: profile)
      .deletingPathExtension()
      .appendingPathExtension("installation.json")
  }

  func stagingFileURL(for profile: LocalModelRuntimeProfile) -> URL {
    let key = safeComponent("\(profile.sourceHub.rawValue)_\(profile.repositoryId)_\(profile.fileName)_\(profile.sha256.prefix(12))")
    return rootURL
      .appendingPathComponent("Staging", isDirectory: true)
      .appendingPathComponent("\(key).part", isDirectory: false)
  }

  func resumeDataFileURL(for profile: LocalModelRuntimeProfile) -> URL {
    stagingFileURL(for: profile)
      .deletingPathExtension()
      .appendingPathExtension("resume")
  }

  func requiredDownloadBytes(for profile: LocalModelRuntimeProfile) -> Int64 {
    let partial = fileSize(stagingFileURL(for: profile))
    let remaining = max(0, profile.expectedModelFileBytes - partial)
    return safeAdd(remaining, 1_073_741_824)
  }

  func availableBytes() -> Int64 {
    let values = try? rootURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    return Int64(max(0, values?.volumeAvailableCapacityForImportantUsage ?? 0))
  }

  func inspect(_ profile: LocalModelRuntimeProfile) -> LocalModelStorageSnapshot {
    try? materializeBundledModelIfNeeded(profile)
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
      sourceHub: profile.sourceHub,
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
    guard profile.supportsIOSRuntime else {
      throw LocalModelRuntimeStorageError.unsupportedPlatform
    }
    let snapshot = inspect(profile)
    guard snapshot.installed, let file = snapshot.fileURL else {
      throw LocalModelRuntimeStorageError.modelNotInstalled
    }
    guard try Self.sha256(fileURL: file) == profile.sha256.lowercased() else {
      throw LocalModelRuntimeStorageError.sha256Mismatch
    }
    return file
  }

  private func materializeBundledModelIfNeeded(_ profile: LocalModelRuntimeProfile) throws {
    #if SIGNALASI_OFFLINE_BUNDLE
      let fileName = profile.fileName as NSString
      let extensionName = fileName.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
      guard profile.id == LocalModelRuntimeProfiles.LFM_2_5_350M_Q8_0.id,
            inspectExisting(profile).installed == false,
            let resource = Bundle.main.url(
              forResource: fileName.deletingPathExtension,
              withExtension: extensionName.isEmpty ? nil : extensionName,
              subdirectory: "local-models"
            ) else {
        return
      }
      let values = try resource.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
      guard values.isRegularFile == true,
            Int64(values.fileSize ?? 0) == profile.expectedModelFileBytes,
            try Self.sha256(fileURL: resource) == profile.sha256.lowercased() else {
        throw LocalModelRuntimeStorageError.sha256Mismatch
      }
      let staged = stagingFileURL(for: profile)
      try fileManager.createDirectory(at: staged.deletingLastPathComponent(), withIntermediateDirectories: true)
      try? fileManager.removeItem(at: staged)
      try fileManager.copyItem(at: resource, to: staged)
      _ = try installVerifiedFile(
        staged,
        profile: profile,
        downloadURL: URL(string: "bundle://signalasi/local-models/\(profile.fileName)")!
      )
    #endif
  }

  private func inspectExisting(_ profile: LocalModelRuntimeProfile) -> LocalModelStorageSnapshot {
    let file = finalFileURL(for: profile)
    let metadata = readMetadata(for: profile)
    guard let metadata else {
      return LocalModelStorageSnapshot(installed: false, fileURL: fileIfPresent(file), metadata: nil, detail: "Installed model metadata is missing")
    }
    guard metadata.matches(profile),
          let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
          values.isRegularFile == true,
          Int64(values.fileSize ?? 0) == profile.expectedModelFileBytes,
          Int64(((values.contentModificationDate?.timeIntervalSince1970 ?? 0) * 1_000).rounded()) == metadata.fileModifiedAtEpochMillis else {
      return LocalModelStorageSnapshot(installed: false, fileURL: fileIfPresent(file), metadata: metadata, detail: "Installed model metadata is invalid")
    }
    return LocalModelStorageSnapshot(installed: true, fileURL: file, metadata: metadata, detail: "")
  }

  func delete(_ profile: LocalModelRuntimeProfile) throws {
    try? fileManager.removeItem(at: finalFileURL(for: profile))
    try? fileManager.removeItem(at: metadataFileURL(for: profile))
    try? fileManager.removeItem(at: stagingFileURL(for: profile))
    try? fileManager.removeItem(at: resumeDataFileURL(for: profile))
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

  private func fileSize(_ url: URL) -> Int64 {
    let values = try? fileManager.attributesOfItem(atPath: url.path)
    return max(0, (values?[.size] as? NSNumber)?.int64Value ?? 0)
  }

  private func safeAdd(_ left: Int64, _ right: Int64) -> Int64 {
    Int64.max - left < right ? Int64.max : left + right
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
  case unsupportedPlatform

  var errorDescription: String? {
    switch self {
    case .modelNotInstalled:
      return "Local model is not installed"
    case .sha256Mismatch:
      return "Installed model failed SHA-256 verification"
    case .unsupportedPlatform:
      return "This model artifact is not supported by the iOS runtime"
    }
  }
}

private extension LocalModelInstallMetadata {
  func matches(_ profile: LocalModelRuntimeProfile) -> Bool {
    profileId == profile.id &&
      repositoryId == profile.repositoryId &&
      fileName == profile.fileName &&
      sourceHub == profile.sourceHub &&
      expectedSizeBytes == profile.expectedModelFileBytes &&
      sha256 == profile.sha256.lowercased()
  }
}
