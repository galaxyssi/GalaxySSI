import Foundation

enum VoiceWhisperModelStorageState: String, Codable, Equatable {
  case notInstalled = "NOT_INSTALLED"
  case checkingSpace = "CHECKING_SPACE"
  case downloadingPartial = "DOWNLOADING_PARTIAL"
  case paused = "PAUSED"
  case verifyingSize = "VERIFYING_SIZE"
  case verifyingSha256 = "VERIFYING_SHA256"
  case atomicInstalling = "ATOMIC_INSTALLING"
  case installedUncertified = "INSTALLED_UNCERTIFIED"
  case benchmarking = "BENCHMARKING"
  case certified = "CERTIFIED"
  case secondPassOnly = "SECOND_PASS_ONLY"
  case unsupported = "UNSUPPORTED"
  case failed = "FAILED"
}

enum VoiceWhisperModelInstallFailure: String, Codable, Equatable {
  case insufficientSpace = "INSUFFICIENT_SPACE"
  case sourceMissing = "SOURCE_MISSING"
  case sizeMismatch = "SIZE_MISMATCH"
  case sha256Mismatch = "SHA256_MISMATCH"
  case copyFailed = "COPY_FAILED"
  case atomicInstallFailed = "ATOMIC_INSTALL_FAILED"
  case metadataInvalid = "METADATA_INVALID"
  case modelInUse = "MODEL_IN_USE"
}

enum VoiceWhisperCertificationLevel: String, Codable, Equatable {
  case untested = "UNTESTED"
  case realtime = "REALTIME"
  case final = "FINAL"
  case secondPass = "SECOND_PASS"
  case remoteRecommended = "REMOTE_RECOMMENDED"
  case unsupported = "UNSUPPORTED"
}

struct VoiceWhisperModelInstallError: LocalizedError, Equatable {
  var failure: VoiceWhisperModelInstallFailure
  var message: String

  var errorDescription: String? { message }
}

struct VoiceWhisperModelInstallMetadata: Codable, Equatable {
  var profileId: String
  var fileName: String
  var expectedSizeBytes: Int64
  var sha256: String
  var catalogVersion: String
  var installedAtMillis: Int64
  var source: String
  var fileLastModifiedMillis: Int64
  var certification: VoiceWhisperCertificationLevel

  enum CodingKeys: String, CodingKey {
    case profileId
    case fileName
    case expectedSizeBytes
    case sha256
    case catalogVersion
    case installedAtMillis
    case source
    case fileLastModifiedMillis
    case certification
  }
}

struct VoiceWhisperModelStorageSnapshot: Equatable {
  var state: VoiceWhisperModelStorageState
  var fileURL: URL?
  var metadata: VoiceWhisperModelInstallMetadata?
  var failure: VoiceWhisperModelInstallFailure?
  var detail: String

  init(
    state: VoiceWhisperModelStorageState,
    fileURL: URL? = nil,
    metadata: VoiceWhisperModelInstallMetadata? = nil,
    failure: VoiceWhisperModelInstallFailure? = nil,
    detail: String = ""
  ) {
    self.state = state
    self.fileURL = fileURL
    self.metadata = metadata
    self.failure = failure
    self.detail = String(detail.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
  }

  var installed: Bool {
    [.installedUncertified, .certified, .secondPassOnly].contains(state)
  }
}

final class VoiceWhisperModelStorage {
  private let root: URL
  private let modelsRoot: URL
  private let stagingRoot: URL
  private let catalogVersion: String
  private let fileManager: FileManager
  private let clockMillis: () -> Int64

  init(
    rootDirectory: URL,
    catalogVersion: String = VoiceWhisperModelCatalog.catalogVersion,
    fileManager: FileManager = .default,
    clockMillis: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }
  ) {
    let normalizedRoot = rootDirectory.standardizedFileURL
    self.fileManager = fileManager
    self.root = normalizedRoot
    self.modelsRoot = normalizedRoot.appendingPathComponent("models", isDirectory: true)
    self.stagingRoot = normalizedRoot.appendingPathComponent("staging", isDirectory: true)
    self.catalogVersion = catalogVersion
    self.clockMillis = clockMillis
    try? fileManager.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
    try? fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
  }

  func finalFileURL(for profile: VoiceWhisperModelProfile) -> URL {
    modelDirectory(for: profile).appendingPathComponent(profile.fileName, isDirectory: false)
  }

  func metadataFileURL(for profile: VoiceWhisperModelProfile) -> URL {
    modelDirectory(for: profile).appendingPathComponent("installation.json", isDirectory: false)
  }

  func stagingFileURL(for profile: VoiceWhisperModelProfile) -> URL {
    stagingRoot.appendingPathComponent("\(profile.id)-\(profile.fileName).partial", isDirectory: false)
  }

  func requiredFreeBytes(for profile: VoiceWhisperModelProfile) -> Int64 {
    safeAdd(safeMultiply(VoiceWhisperModelVerifier.expectedSizeBytes(for: profile), 2), profile.minFreeStorageBytes)
  }

  func inspect(_ profile: VoiceWhisperModelProfile) -> VoiceWhisperModelStorageSnapshot {
    let fileURL = finalFileURL(for: profile)
    guard let metadata = readMetadata(for: profile) else {
      return VoiceWhisperModelStorageSnapshot(state: .notInstalled)
    }
    let actualSize = fileSize(fileURL)
    if !fileManager.fileExists(atPath: fileURL.path) ||
       actualSize != VoiceWhisperModelVerifier.expectedSizeBytes(for: profile) {
      return VoiceWhisperModelStorageSnapshot(
        state: .failed,
        fileURL: fileManager.fileExists(atPath: fileURL.path) ? fileURL : nil,
        metadata: metadata,
        failure: .sizeMismatch,
        detail: "Installed model size no longer matches its profile"
      )
    }
    if !metadataMatches(metadata, profile: profile) ||
       metadata.fileLastModifiedMillis != fileLastModifiedMillis(fileURL) {
      return VoiceWhisperModelStorageSnapshot(
        state: .failed,
        fileURL: fileURL,
        metadata: metadata,
        failure: .metadataInvalid,
        detail: "Installed model metadata is stale or invalid"
      )
    }
    return VoiceWhisperModelStorageSnapshot(
      state: state(for: metadata.certification),
      fileURL: fileURL,
      metadata: metadata
    )
  }

  func install(
    sourceFileURL: URL,
    profile: VoiceWhisperModelProfile,
    sourceLabel: String,
    availableBytes: Int64? = nil,
    beforeCommit: () throws -> Void = {}
  ) throws -> VoiceWhisperModelInstallMetadata {
    guard fileManager.fileExists(atPath: sourceFileURL.path) else {
      throw installError(.sourceMissing, "Model source file is missing")
    }
    let required = safeAdd(VoiceWhisperModelVerifier.expectedSizeBytes(for: profile), profile.minFreeStorageBytes)
    if let availableBytes, availableBytes >= 0, availableBytes < required {
      throw installError(.insufficientSpace, "Model install needs \(required) free bytes but only \(availableBytes) are available")
    }
    let staged = stagingFileURL(for: profile)
    try? fileManager.removeItem(at: staged)
    try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
    do {
      try fileManager.copyItem(at: sourceFileURL, to: staged)
    } catch {
      try? fileManager.removeItem(at: staged)
      throw installError(.copyFailed, "Could not stage the model")
    }
    let verification = VoiceWhisperModelVerifier.verify(fileURL: staged, profile: profile, fileManager: fileManager)
    guard verification.valid else {
      try? fileManager.removeItem(at: staged)
      throw verificationError(verification)
    }

    let destination = finalFileURL(for: profile)
    try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    do {
      try beforeCommit()
    } catch {
      try? fileManager.removeItem(at: staged)
      throw error
    }
    do {
      try replace(staged, destination: destination)
    } catch {
      try? fileManager.removeItem(at: staged)
      throw installError(.atomicInstallFailed, "Could not atomically install the verified model")
    }
    let metadata = VoiceWhisperModelInstallMetadata(
      profileId: profile.id,
      fileName: profile.fileName,
      expectedSizeBytes: VoiceWhisperModelVerifier.expectedSizeBytes(for: profile),
      sha256: profile.sha256.isEmpty ? verification.actualSha256 : profile.sha256,
      catalogVersion: catalogVersion,
      installedAtMillis: clockMillis(),
      source: String(sourceLabel.trimmingCharacters(in: .whitespacesAndNewlines).prefix(256)),
      fileLastModifiedMillis: fileLastModifiedMillis(destination),
      certification: .untested
    )
    try writeMetadata(metadata, for: profile)
    return metadata
  }

  func verifyForNativeLoad(_ profile: VoiceWhisperModelProfile) -> VoiceWhisperVerificationResult {
    let snapshot = inspect(profile)
    guard snapshot.installed, let fileURL = snapshot.fileURL else {
      return VoiceWhisperVerificationResult(
        valid: false,
        failure: .missing,
        detail: snapshot.detail.isEmpty ? "Model is not installed" : snapshot.detail
      )
    }
    return VoiceWhisperModelVerifier.verify(fileURL: fileURL, profile: profile, fileManager: fileManager)
  }

  func invalidate(_ profile: VoiceWhisperModelProfile) {
    try? fileManager.removeItem(at: metadataFileURL(for: profile))
    try? fileManager.removeItem(at: finalFileURL(for: profile))
  }

  func updateCertification(
    _ profile: VoiceWhisperModelProfile,
    certification: VoiceWhisperCertificationLevel
  ) throws {
    let snapshot = inspect(profile)
    guard snapshot.installed, var metadata = snapshot.metadata else {
      throw installError(.metadataInvalid, "Cannot certify a model that is not installed")
    }
    metadata.certification = certification
    try writeMetadata(metadata, for: profile)
  }

  @discardableResult
  func delete(_ profile: VoiceWhisperModelProfile, active: Bool = false) throws -> Bool {
    if active {
      throw installError(.modelInUse, "Model is currently loaded")
    }
    let directory = modelDirectory(for: profile)
    let existed = fileManager.fileExists(atPath: directory.path) || fileManager.fileExists(atPath: stagingFileURL(for: profile).path)
    try? fileManager.removeItem(at: stagingFileURL(for: profile))
    try? fileManager.removeItem(at: directory)
    return existed
  }

  @discardableResult
  func cleanupStalePartials(maxAgeMillis: Int64) -> Int {
    let threshold = clockMillis() - max(0, maxAgeMillis)
    guard let enumerator = fileManager.enumerator(at: stagingRoot, includingPropertiesForKeys: [.contentModificationDateKey]) else {
      return 0
    }
    var removed = 0
    for case let url as URL in enumerator where url.lastPathComponent.hasSuffix(".partial") {
      if fileLastModifiedMillis(url) < threshold, (try? fileManager.removeItem(at: url)) != nil {
        removed += 1
      }
    }
    return removed
  }

  private func modelDirectory(for profile: VoiceWhisperModelProfile) -> URL {
    modelsRoot.appendingPathComponent(profile.id, isDirectory: true)
  }

  private func readMetadata(for profile: VoiceWhisperModelProfile) -> VoiceWhisperModelInstallMetadata? {
    let fileURL = metadataFileURL(for: profile)
    guard let data = try? Data(contentsOf: fileURL) else { return nil }
    return try? JSONDecoder().decode(VoiceWhisperModelInstallMetadata.self, from: data)
  }

  private func writeMetadata(
    _ metadata: VoiceWhisperModelInstallMetadata,
    for profile: VoiceWhisperModelProfile
  ) throws {
    let fileURL = metadataFileURL(for: profile)
    try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try JSONEncoder().encode(metadata)
    try data.write(to: fileURL, options: .atomic)
  }

  private func replace(_ staged: URL, destination: URL) throws {
    if fileManager.fileExists(atPath: destination.path) {
      _ = try fileManager.replaceItemAt(destination, withItemAt: staged, backupItemName: nil, options: .usingNewMetadataOnly)
    } else {
      try fileManager.moveItem(at: staged, to: destination)
    }
  }

  private func metadataMatches(
    _ metadata: VoiceWhisperModelInstallMetadata,
    profile: VoiceWhisperModelProfile
  ) -> Bool {
    metadata.profileId == profile.id &&
      metadata.fileName == profile.fileName &&
      metadata.expectedSizeBytes == VoiceWhisperModelVerifier.expectedSizeBytes(for: profile) &&
      (profile.sha256.isEmpty || metadata.sha256 == profile.sha256) &&
      metadata.catalogVersion == catalogVersion
  }

  private func state(for certification: VoiceWhisperCertificationLevel) -> VoiceWhisperModelStorageState {
    switch certification {
    case .untested:
      return .installedUncertified
    case .realtime, .final:
      return .certified
    case .secondPass:
      return .secondPassOnly
    case .remoteRecommended, .unsupported:
      return .unsupported
    }
  }

  private func verificationError(_ result: VoiceWhisperVerificationResult) -> VoiceWhisperModelInstallError {
    switch result.failure {
    case .sizeMismatch:
      return installError(.sizeMismatch, result.detail)
    case .sha256Mismatch:
      return installError(.sha256Mismatch, result.detail)
    case .missing, .notAFile, .ioError, nil:
      return installError(.sourceMissing, result.detail.isEmpty ? "Model verification failed" : result.detail)
    }
  }

  private func installError(
    _ failure: VoiceWhisperModelInstallFailure,
    _ message: String
  ) -> VoiceWhisperModelInstallError {
    VoiceWhisperModelInstallError(failure: failure, message: message)
  }

  private func fileSize(_ fileURL: URL) -> Int64 {
    guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
          let size = attributes[.size] as? NSNumber else {
      return 0
    }
    return size.int64Value
  }

  private func fileLastModifiedMillis(_ fileURL: URL) -> Int64 {
    guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
          let date = attributes[.modificationDate] as? Date else {
      return 0
    }
    return Int64(date.timeIntervalSince1970 * 1_000)
  }

  private func safeMultiply(_ value: Int64, _ multiplier: Int64) -> Int64 {
    let result = value.multipliedReportingOverflow(by: multiplier)
    return result.overflow ? Int64.max : result.partialValue
  }

  private func safeAdd(_ left: Int64, _ right: Int64) -> Int64 {
    let result = left.addingReportingOverflow(right)
    return result.overflow ? Int64.max : result.partialValue
  }
}
