import Foundation

struct LocalModelVerifiedFileImportResult: Sendable {
  let profileId: String
  let profileName: String
  let destinationURL: URL
}

enum LocalModelVerifiedFileImportError: LocalizedError {
  case unsupportedFileType
  case notRegularFile
  case unsupportedArtifact(size: Int64, sha256: String)

  var errorDescription: String? {
    switch self {
    case .unsupportedFileType:
      return "Only GGUF model files can be imported"
    case .notRegularFile:
      return "The selected model is not a regular file"
    case .unsupportedArtifact(let size, let sha256):
      return "The GGUF file is not a trusted artifact (size: \(size), SHA-256: \(sha256))"
    }
  }
}

enum LocalModelVerifiedFileImporter {
  static func install(from sourceURL: URL) throws -> LocalModelVerifiedFileImportResult {
    let fileManager = FileManager.default
    let scoped = sourceURL.startAccessingSecurityScopedResource()
    defer {
      if scoped { sourceURL.stopAccessingSecurityScopedResource() }
    }

    guard sourceURL.pathExtension.caseInsensitiveCompare("gguf") == .orderedSame else {
      throw LocalModelVerifiedFileImportError.unsupportedFileType
    }
    let values = try sourceURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    guard values.isRegularFile == true else {
      throw LocalModelVerifiedFileImportError.notRegularFile
    }
    let size = Int64(values.fileSize ?? 0)
    let sha256 = try LocalModelRuntimeStorage.sha256(fileURL: sourceURL)
    guard let profile = LocalModelRuntimeCatalog.profiles().first(where: { profile in
      profile.downloadable &&
        profile.expectedModelFileBytes == size &&
        profile.sha256.caseInsensitiveCompare(sha256) == .orderedSame
    }) else {
      throw LocalModelVerifiedFileImportError.unsupportedArtifact(size: size, sha256: sha256)
    }

    let temporaryURL = fileManager.temporaryDirectory
      .appendingPathComponent("galaxyssi-model-import-\(UUID().uuidString)", isDirectory: false)
      .appendingPathExtension("gguf")
    try fileManager.copyItem(at: sourceURL, to: temporaryURL)
    defer { try? fileManager.removeItem(at: temporaryURL) }
    let destinationURL = try LocalModelRuntimeStorage().installVerifiedFile(
      temporaryURL,
      profile: profile,
      downloadURL: sourceURL
    )
    return LocalModelVerifiedFileImportResult(
      profileId: profile.id,
      profileName: profile.displayName,
      destinationURL: destinationURL
    )
  }
}
