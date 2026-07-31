import CryptoKit
import Foundation

enum VoiceWhisperVerificationFailure: String, Codable, Equatable {
  case missing = "MISSING"
  case notAFile = "NOT_A_FILE"
  case sizeMismatch = "SIZE_MISMATCH"
  case sha256Mismatch = "SHA256_MISMATCH"
  case ioError = "IO_ERROR"
}

struct VoiceWhisperVerificationResult: Codable, Equatable {
  var valid: Bool
  var actualSizeBytes: Int64
  var actualSha256: String
  var failure: VoiceWhisperVerificationFailure?
  var detail: String

  init(
    valid: Bool,
    actualSizeBytes: Int64 = 0,
    actualSha256: String = "",
    failure: VoiceWhisperVerificationFailure? = nil,
    detail: String = ""
  ) {
    self.valid = valid
    self.actualSizeBytes = max(0, actualSizeBytes)
    self.actualSha256 = actualSha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    self.failure = failure
    self.detail = String(detail.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
  }
}

enum VoiceWhisperModelVerifier {
  static func verify(
    fileURL: URL,
    profile: VoiceWhisperModelProfile,
    fileManager: FileManager = .default
  ) -> VoiceWhisperVerificationResult {
    guard fileManager.fileExists(atPath: fileURL.path) else {
      return VoiceWhisperVerificationResult(valid: false, failure: .missing)
    }
    guard isRegularFile(fileURL: fileURL, fileManager: fileManager) else {
      return VoiceWhisperVerificationResult(valid: false, failure: .notAFile)
    }
    let actualSize = fileSize(fileURL: fileURL, fileManager: fileManager)
    let expectedSize = expectedSizeBytes(for: profile)
    if expectedSize > 0, actualSize != expectedSize {
      return VoiceWhisperVerificationResult(
        valid: false,
        actualSizeBytes: actualSize,
        failure: .sizeMismatch,
        detail: "Expected \(expectedSize) bytes but found \(actualSize)"
      )
    }
    do {
      let actualSha = try sha256(fileURL: fileURL)
      let expectedSha = profile.sha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      if expectedSha.isEmpty || actualSha == expectedSha {
        return VoiceWhisperVerificationResult(valid: true, actualSizeBytes: actualSize, actualSha256: actualSha)
      }
      return VoiceWhisperVerificationResult(
        valid: false,
        actualSizeBytes: actualSize,
        actualSha256: actualSha,
        failure: .sha256Mismatch,
        detail: "SHA-256 does not match the pinned model profile"
      )
    } catch {
      return VoiceWhisperVerificationResult(
        valid: false,
        actualSizeBytes: actualSize,
        failure: .ioError,
        detail: error.localizedDescription
      )
    }
  }

  static func sha256(fileURL: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: fileURL)
    defer { try? handle.close() }
    var hasher = SHA256()
    while true {
      let data = handle.readData(ofLength: 1024 * 1024)
      if data.isEmpty { break }
      hasher.update(data: data)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  static func expectedSizeBytes(for profile: VoiceWhisperModelProfile) -> Int64 {
    profile.expectedSizeBytes > 0 ? profile.expectedSizeBytes : profile.minimumUsableBytes
  }

  private static func fileSize(fileURL: URL, fileManager: FileManager) -> Int64 {
    guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
          let size = attributes[.size] as? NSNumber else {
      return 0
    }
    return size.int64Value
  }

  private static func isRegularFile(fileURL: URL, fileManager: FileManager) -> Bool {
    guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
          let type = attributes[.type] as? FileAttributeType else {
      return false
    }
    return type == .typeRegular
  }
}
