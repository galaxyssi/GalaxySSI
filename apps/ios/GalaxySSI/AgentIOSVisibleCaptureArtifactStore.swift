import Foundation

struct AgentIOSVisibleCaptureArtifactStore {
  var rootURL: URL
  var fileManager: FileManager

  init(rootURL: URL? = nil, fileManager: FileManager = .default) {
    self.fileManager = fileManager
    self.rootURL = (rootURL ?? Self.defaultRootURL(fileManager: fileManager)).standardizedFileURL
  }

  static func defaultRootURL(fileManager: FileManager = .default) -> URL {
    let baseURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
    return baseURL
      .appendingPathComponent("galaxyssi", isDirectory: true)
      .appendingPathComponent("visible-capture", isDirectory: true)
  }

  func makeArtifactURL(
    kind: AgentIOSVisibleCaptureKind,
    fileExtension: String,
    requestId: String
  ) throws -> URL {
    try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    let suffix = sanitized(requestId).prefix(72)
    let cleanExtension = sanitized(fileExtension).prefix(12)
    let resolvedExtension = cleanExtension.isEmpty ? "bin" : String(cleanExtension)
    let resolvedSuffix = suffix.isEmpty ? UUID().uuidString : String(suffix)
    let name = "\(kind.rawValue)-\(resolvedSuffix)-\(UUID().uuidString).\(resolvedExtension)"
    return rootURL.appendingPathComponent(name, isDirectory: false).standardizedFileURL
  }

  func fileSize(_ fileURL: URL) throws -> Int64 {
    let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
    return (attributes[.size] as? NSNumber)?.int64Value ?? 0
  }

  private func sanitized(_ value: String) -> String {
    let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
    return String(value.map { allowed.contains($0) ? $0 : "-" })
      .trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
  }
}
