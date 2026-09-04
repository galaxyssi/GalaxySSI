import Foundation

enum VoiceWhisperLegacyMigrationState: String, Codable, Equatable {
  case notFound = "NOT_FOUND"
  case migrated = "MIGRATED"
  case alreadyInstalled = "ALREADY_INSTALLED"
  case rejected = "REJECTED"
}

struct VoiceWhisperLegacyMigrationResult: Equatable {
  var state: VoiceWhisperLegacyMigrationState
  var sourceURL: URL?
  var failure: VoiceWhisperModelInstallFailure?
  var detail: String

  init(
    state: VoiceWhisperLegacyMigrationState,
    sourceURL: URL? = nil,
    failure: VoiceWhisperModelInstallFailure? = nil,
    detail: String = ""
  ) {
    self.state = state
    self.sourceURL = sourceURL
    self.failure = failure
    self.detail = String(detail.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
  }
}

enum VoiceWhisperLegacyMigration {
  static func migrate(
    profile: VoiceWhisperModelProfile,
    candidates: [URL],
    storage: VoiceWhisperModelStorage,
    fileManager: FileManager = .default,
    deleteMigratedSource: Bool = false
  ) -> VoiceWhisperLegacyMigrationResult {
    if storage.inspect(profile).installed {
      return VoiceWhisperLegacyMigrationResult(state: .alreadyInstalled)
    }

    let existing = regularFiles(from: candidates, fileManager: fileManager)
    if existing.isEmpty {
      return VoiceWhisperLegacyMigrationResult(state: .notFound)
    }

    var lastFailure: VoiceWhisperLegacyMigrationResult?
    for candidate in existing {
      do {
        _ = try storage.install(
          sourceFileURL: candidate,
          profile: profile,
          sourceLabel: "legacy:\(candidate.lastPathComponent)"
        )
        if deleteMigratedSource {
          try? fileManager.removeItem(at: candidate)
        }
        return VoiceWhisperLegacyMigrationResult(state: .migrated, sourceURL: candidate)
      } catch let error as VoiceWhisperModelInstallError {
        lastFailure = VoiceWhisperLegacyMigrationResult(
          state: .rejected,
          sourceURL: candidate,
          failure: error.failure,
          detail: error.localizedDescription
        )
      } catch {
        lastFailure = VoiceWhisperLegacyMigrationResult(
          state: .rejected,
          sourceURL: candidate,
          failure: .copyFailed,
          detail: error.localizedDescription
        )
      }
    }

    return lastFailure ?? VoiceWhisperLegacyMigrationResult(state: .notFound)
  }

  private static func regularFiles(from candidates: [URL], fileManager: FileManager) -> [URL] {
    var seen = Set<String>()
    var files: [URL] = []
    for candidate in candidates {
      let key = canonicalPath(for: candidate, fileManager: fileManager)
      guard seen.insert(key).inserted else { continue }
      guard isRegularFile(candidate, fileManager: fileManager) else { continue }
      files.append(candidate)
    }
    return files
  }

  private static func canonicalPath(for url: URL, fileManager: FileManager) -> String {
    let path = url.path
    if let destination = try? fileManager.destinationOfSymbolicLink(atPath: path) {
      return URL(fileURLWithPath: destination).standardizedFileURL.path
    }
    return url.standardizedFileURL.path
  }

  private static func isRegularFile(_ url: URL, fileManager: FileManager) -> Bool {
    guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
          let type = attributes[.type] as? FileAttributeType else {
      return false
    }
    return type == .typeRegular
  }
}
