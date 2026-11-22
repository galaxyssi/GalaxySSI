import Foundation
import UniformTypeIdentifiers

enum AgentPeerAttachmentPreview {
  enum Failure: Error, Equatable { case unreadable, failed }

  struct Lease {
    let file: URL
    let directory: URL
  }

  static func mimeType(name: String, declared: String) -> String {
    let value = declared.components(separatedBy: ";").first?
      .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    let generic = ["", "application/octet-stream", "binary/octet-stream", "*/*"].contains(value)
    if value == "application/x-pdf" || generic && name.lowercased().hasSuffix(".pdf") { return "application/pdf" }
    return generic ? "application/octet-stream" : value
  }

  static func previewName(name: String, declared: String) -> String {
    let candidate = AgentDesktopArtifactStore.safeFileName(name)
    let safe = [".", ".."].contains(candidate) ? "GalaxySSI-attachment" : candidate
    let mime = mimeType(name: name, declared: declared)
    if mime == "application/pdf" {
      return URL(fileURLWithPath: safe).deletingPathExtension().lastPathComponent + ".pdf"
    }
    if URL(fileURLWithPath: safe).pathExtension.isEmpty,
       let suffix = UTType(mimeType: mime)?.preferredFilenameExtension {
      return safe + "." + suffix
    }
    return safe
  }

  static func prepare(source: URL, name: String, declared: String,
                      temporaryDirectory: URL = FileManager.default.temporaryDirectory) throws -> Lease {
    let manager = FileManager.default
    guard source.isFileURL, manager.isReadableFile(atPath: source.path),
          let values = try? source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
          values.isRegularFile == true, values.isSymbolicLink != true else { throw Failure.unreadable }
    let root = temporaryDirectory.appendingPathComponent("galaxyssi-peer-previews", isDirectory: true)
    var directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
    do {
      try manager.createDirectory(at: directory, withIntermediateDirectories: true,
        attributes: [.protectionKey: FileProtectionType.complete])
      var attributes = URLResourceValues()
      attributes.isExcludedFromBackup = true
      try directory.setResourceValues(attributes)
      let file = directory.appendingPathComponent(previewName(name: name, declared: declared))
      try manager.copyItem(at: source, to: file)
      try manager.setAttributes([.protectionKey: FileProtectionType.complete, .posixPermissions: 0o400], ofItemAtPath: file.path)
      return Lease(file: file, directory: directory)
    } catch {
      try? manager.removeItem(at: directory)
      throw manager.isReadableFile(atPath: source.path) ? Failure.failed : Failure.unreadable
    }
  }

  static func release(_ lease: Lease) {
    // Only remove the UUID-scoped preview directory, never its original attachment.
    guard lease.directory.deletingLastPathComponent().lastPathComponent == "galaxyssi-peer-previews",
          UUID(uuidString: lease.directory.lastPathComponent) != nil,
          lease.file.deletingLastPathComponent() == lease.directory else { return }
    try? FileManager.default.removeItem(at: lease.directory)
  }
}
