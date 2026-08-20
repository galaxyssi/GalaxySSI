import CryptoKit
import Foundation

final class AgentIOSRuntimePackInstaller {
  private let packsRootURL: URL
  private let fileManager: FileManager
  private let hostVersionCode: Int64
  private let signatureVerifier: (AgentRuntimePackManifest) -> Bool

  init(
    runtimeRootURL: URL = AgentIOSDefaultOnDeviceRuntimeProvider.defaultRuntimeRootURL(),
    fileManager: FileManager = .default,
    hostVersionCode: Int64 = AgentIOSRuntimePackInstaller.defaultHostVersionCode(),
    signatureVerifier: @escaping (AgentRuntimePackManifest) -> Bool = { manifest in
      AgentIOSRuntimePackTrust.verify(manifest: manifest)
    }
  ) {
    self.packsRootURL = runtimeRootURL.appendingPathComponent("packs", isDirectory: true)
    self.fileManager = fileManager
    self.hostVersionCode = max(hostVersionCode, 1)
    self.signatureVerifier = signatureVerifier
  }

  func install(
    source: URL,
    onProgress: (AgentRuntimePackInstallProgress) -> Void = { _ in }
  ) throws -> AgentRuntimePackInstallResult {
    try fileManager.createDirectory(at: packsRootURL, withIntermediateDirectories: true)
    let sourceBytes = try fileSize(source)
    guard (1...AgentRuntimePackArchiveReader.maximumArchiveBytes).contains(sourceBytes) else {
      throw AgentRuntimePackArchiveError("Runtime pack archive exceeds the size limit")
    }
    let operationId = UUID().uuidString.lowercased()
    let importedArchive = packsRootURL.appendingPathComponent(".import-\(operationId).sarpack")
    onProgress(AgentRuntimePackInstallProgress(
      stage: .preparing,
      totalBytes: sourceBytes
    ))
    defer { try? fileManager.removeItem(at: importedArchive) }

    try fileManager.copyItem(at: source, to: importedArchive)
    onProgress(AgentRuntimePackInstallProgress(
      stage: .copying,
      processedBytes: sourceBytes,
      totalBytes: sourceBytes
    ))
    return try installArchive(importedArchive, onProgress: onProgress)
  }

  func uninstall(packId: String) throws -> Bool {
    guard AgentRuntimePackCatalogPolicy.requiredPacks.contains(packId) else {
      throw AgentRuntimePackArchiveError("Runtime pack id is not supported")
    }
    let directory = packsRootURL.appendingPathComponent(packId, isDirectory: true)
    guard fileManager.fileExists(atPath: directory.path) else { return false }
    let installedPacks = AgentRuntimePackCatalogPolicy.requiredPacks.compactMap { id -> AgentRuntimePackManifest? in
      try? manifest(at: packsRootURL.appendingPathComponent(id, isDirectory: true))
    }
    if installedPacks.contains(where: { $0.dependencies.contains(packId) }) {
      throw AgentRuntimePackArchiveError("Another runtime pack depends on \(packId)")
    }
    let quarantine = packsRootURL.appendingPathComponent(".remove-\(packId)-\(UUID().uuidString)")
    try fileManager.moveItem(at: directory, to: quarantine)
    try fileManager.removeItem(at: quarantine)
    return true
  }

  func installedManifest(packId: String) -> AgentRuntimePackManifest? {
    guard AgentRuntimePackCatalogPolicy.requiredPacks.contains(packId) else { return nil }
    do {
      let manifest = try validatePack(at: packsRootURL.appendingPathComponent(packId, isDirectory: true))
      try validateInstalledDependencies(for: manifest)
      return manifest
    } catch {
      return nil
    }
  }

  func status(packId: String) -> AgentRuntimePackStatus {
    guard AgentRuntimePackCatalogPolicy.requiredPacks.contains(packId) else {
      return AgentRuntimePackStatus(
        id: packId,
        state: .invalid,
        reason: "Runtime pack id is not supported"
      )
    }
    let directory = packsRootURL.appendingPathComponent(packId, isDirectory: true)
    guard fileManager.fileExists(atPath: directory.path) else {
      return AgentRuntimePackStatus(
        id: packId,
        state: .notInstalled,
        reason: "Runtime pack is not installed"
      )
    }
    let decodedManifest = try? manifest(at: directory)
    do {
      let verifiedManifest = try validatePack(at: directory)
      try validateInstalledDependencies(for: verifiedManifest)
      return AgentRuntimePackStatus(
        id: packId,
        state: .ready,
        reason: "",
        manifest: verifiedManifest
      )
    } catch {
      return AgentRuntimePackStatus(
        id: packId,
        state: .invalid,
        reason: error.localizedDescription.ifBlank("Runtime pack integrity verification failed"),
        manifest: decodedManifest
      )
    }
  }

  private func installArchive(
    _ archive: URL,
    onProgress: (AgentRuntimePackInstallProgress) -> Void
  ) throws -> AgentRuntimePackInstallResult {
    let operationId = UUID().uuidString.lowercased()
    let staging = packsRootURL.appendingPathComponent(".stage-\(operationId)", isDirectory: true)
    var backup: URL?
    var destination: URL?
    var activated = false
    defer { try? fileManager.removeItem(at: staging) }
    do {
      try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
      let extractedBytes = try AgentRuntimePackArchiveReader.extract(
        archive: archive,
        to: staging,
        fileManager: fileManager
      ) { processedBytes in
        onProgress(AgentRuntimePackInstallProgress(
          stage: .extracting,
          processedBytes: processedBytes,
          totalBytes: -1
        ))
      }
      let archiveBytes = try fileSize(archive)
      onProgress(AgentRuntimePackInstallProgress(
        stage: .verifying,
        processedBytes: archiveBytes,
        totalBytes: archiveBytes
      ))
      let stagedManifest = try validatePack(at: staging)
      guard archiveBytes <= stagedManifest.archiveSizeBytes + archiveSizeTolerance,
            extractedBytes <= stagedManifest.installedSizeBytes + installSizeTolerance else {
        throw AgentRuntimePackArchiveError("Runtime pack content exceeds its signed size")
      }

      let target = packsRootURL.appendingPathComponent(stagedManifest.id, isDirectory: true)
      let previous = packsRootURL.appendingPathComponent(
        ".backup-\(stagedManifest.id)-\(operationId)",
        isDirectory: true
      )
      destination = target
      backup = previous
      let replacingExisting = fileManager.fileExists(atPath: target.path)
      onProgress(AgentRuntimePackInstallProgress(
        stage: .activating,
        processedBytes: archiveBytes,
        totalBytes: archiveBytes
      ))
      if replacingExisting {
        try fileManager.moveItem(at: target, to: previous)
      }
      try fileManager.moveItem(at: staging, to: target)
      activated = true

      let installedManifest = try validatePack(at: target)
      try validateInstalledDependencies(for: installedManifest)
      try? fileManager.removeItem(at: previous)
      onProgress(AgentRuntimePackInstallProgress(
        stage: .completed,
        processedBytes: archiveBytes,
        totalBytes: archiveBytes
      ))
      return AgentRuntimePackInstallResult(
        packId: installedManifest.id,
        version: installedManifest.version,
        state: .ready,
        installedBytes: extractedBytes,
        replacedExisting: replacingExisting
      )
    } catch {
      if activated, let destination {
        try? fileManager.removeItem(at: destination)
      }
      if let backup, let destination,
         fileManager.fileExists(atPath: backup.path),
         !fileManager.fileExists(atPath: destination.path) {
        try? fileManager.moveItem(at: backup, to: destination)
      }
      throw error
    }
  }

  private func validatePack(at directory: URL) throws -> AgentRuntimePackManifest {
    let manifest = try self.manifest(at: directory)
    guard AgentRuntimePackCatalogPolicy.requiredPacks.contains(manifest.id) else {
      throw AgentRuntimePackArchiveError("Runtime pack id is not supported")
    }
    guard matches(manifest.version, #"^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9._-]+)?$"#),
          manifest.formatVersion == 1,
          manifest.architecture.isEmpty == false,
          AgentRuntimePackCatalogPolicy.defaultSupportedArchitectures.contains(manifest.architecture) else {
      throw AgentRuntimePackArchiveError("Runtime pack manifest is incompatible with this iOS device")
    }
    guard matches(manifest.imageSha256.lowercased(), #"^[a-f0-9]{64}$"#),
          manifest.installedSizeBytes > 0,
          manifest.installedSizeBytes <= AgentRuntimePackArchiveReader.maximumExpandedBytes,
          manifest.archiveSizeBytes > 0,
          manifest.archiveSizeBytes <= AgentRuntimePackArchiveReader.maximumArchiveBytes,
          manifest.minimumHostVersionCode <= hostVersionCode,
          manifest.guestApiVersion == AgentRuntimeGuestProtocol.version else {
      throw AgentRuntimePackArchiveError("Runtime pack manifest metadata is invalid")
    }
    guard matches(manifest.signatureKeyId.lowercased(), #"^[a-f0-9]{64}$"#),
          !manifest.signature.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          signatureVerifier(manifest) else {
      throw AgentRuntimePackArchiveError("Runtime pack signature is not trusted")
    }
    let dependencies = Set(manifest.dependencies)
    guard dependencies.count == manifest.dependencies.count,
          manifest.dependencies.allSatisfy({
            AgentRuntimePackCatalogPolicy.requiredPacks.contains($0) && $0 != manifest.id
          }) else {
      throw AgentRuntimePackArchiveError("Runtime pack dependencies are invalid")
    }
    let requiredCapabilities = AgentRuntimePackCatalogPolicy.requiredPackCapabilities[manifest.id] ?? []
    guard requiredCapabilities.isSubset(of: Set(manifest.capabilities)) else {
      throw AgentRuntimePackArchiveError("Runtime pack is missing required capabilities")
    }
    let imageURL = directory.appendingPathComponent(manifest.imageFile, isDirectory: false)
    guard isSafeRelativePath(manifest.imageFile),
          fileManager.fileExists(atPath: imageURL.path) else {
      throw AgentRuntimePackArchiveError("Runtime pack image is missing")
    }
    let imageData = try Data(contentsOf: imageURL, options: [.mappedIfSafe])
    let imageHash = SHA256.hash(data: imageData).map { String(format: "%02x", $0) }.joined()
    guard imageHash.caseInsensitiveCompare(manifest.imageSha256) == .orderedSame else {
      throw AgentRuntimePackArchiveError("Runtime pack image digest did not match")
    }
    return manifest
  }

  private func validateInstalledDependencies(for manifest: AgentRuntimePackManifest) throws {
    for dependency in manifest.dependencies {
      let dependencyURL = packsRootURL.appendingPathComponent(dependency, isDirectory: true)
      let dependencyManifest = try validatePack(at: dependencyURL)
      guard dependencyManifest.id == dependency else {
        throw AgentRuntimePackArchiveError("Runtime pack dependency id does not match its directory")
      }
    }
  }

  private func manifest(at directory: URL) throws -> AgentRuntimePackManifest {
    let manifestURL = directory.appendingPathComponent("manifest.json", isDirectory: false)
    guard fileManager.fileExists(atPath: manifestURL.path) else {
      throw AgentRuntimePackArchiveError("Runtime pack manifest is missing")
    }
    do {
      return try JSONDecoder().decode(
        AgentRuntimePackManifest.self,
        from: Data(contentsOf: manifestURL)
      )
    } catch {
      throw AgentRuntimePackArchiveError("Runtime pack manifest is malformed")
    }
  }

  private func fileSize(_ url: URL) throws -> Int64 {
    let attributes = try fileManager.attributesOfItem(atPath: url.path)
    guard let size = (attributes[.size] as? NSNumber)?.int64Value else {
      throw AgentRuntimePackArchiveError("Runtime pack file size is unavailable")
    }
    return size
  }

  private func isSafeRelativePath(_ value: String) -> Bool {
    let parts = value.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    return !value.isEmpty && !value.contains("\\") && !value.hasPrefix("/") &&
      value.range(of: #"^[A-Za-z]:"#, options: .regularExpression) == nil &&
      parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
  }

  private func matches(_ value: String, _ pattern: String) -> Bool {
    value.range(of: pattern, options: .regularExpression) != nil
  }

  static func defaultHostVersionCode(bundle: Bundle = .main) -> Int64 {
    let raw = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? ""
    return max(Int64(raw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1, 1)
  }

  private let installSizeTolerance: Int64 = 16 * 1_024 * 1_024
  private let archiveSizeTolerance: Int64 = 4 * 1_024 * 1_024
}
