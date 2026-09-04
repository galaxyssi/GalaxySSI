import Foundation

final class GalaxySSILinkOutboxPayloadStore {
  static let fileBackedWireThresholdBytes = 64 * 1024

  private let rootURL: URL
  private let fileManager: FileManager

  init(rootURL: URL? = nil, fileManager: FileManager = .default) {
    self.fileManager = fileManager
    self.rootURL = (rootURL ?? Self.defaultRootURL(fileManager: fileManager)).standardizedFileURL
  }

  static func defaultRootURL(fileManager: FileManager = .default) -> URL {
    let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
    return baseURL.appendingPathComponent("galaxyssi-link-outbox-v1", isDirectory: true)
  }

  func reference(
    messageId: String,
    wirePayload: String
  ) -> (wirePayload: String, wirePayloadFile: String?) {
    let data = Data(wirePayload.utf8)
    guard data.count > Self.fileBackedWireThresholdBytes else {
      return (wirePayload, nil)
    }
    do {
      try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
      let name = fileName(for: messageId)
      let temporary = rootURL.appendingPathComponent(".\(name).tmp", isDirectory: false)
      let target = rootURL.appendingPathComponent(name, isDirectory: false)
      try data.write(to: temporary, options: [.atomic])
      if fileManager.fileExists(atPath: target.path) {
        try fileManager.removeItem(at: target)
      }
      try fileManager.moveItem(at: temporary, to: target)
      return ("", name)
    } catch {
      return (wirePayload, nil)
    }
  }

  func resolve(inline wirePayload: String, fileName: String?) -> String {
    if !wirePayload.isEmpty {
      return wirePayload
    }
    guard let fileName,
          fileName.range(of: fileNamePattern, options: .regularExpression) != nil else {
      return ""
    }
    let target = rootURL.appendingPathComponent(fileName, isDirectory: false).standardizedFileURL
    guard target.path.hasPrefix(rootURL.path + pathSeparator),
          fileManager.fileExists(atPath: target.path) else {
      return ""
    }
    return (try? String(contentsOf: target, encoding: .utf8)) ?? ""
  }

  func delete(fileName: String?) {
    guard let fileName,
          fileName.range(of: fileNamePattern, options: .regularExpression) != nil else {
      return
    }
    let target = rootURL.appendingPathComponent(fileName, isDirectory: false).standardizedFileURL
    guard target.path.hasPrefix(rootURL.path + pathSeparator) else { return }
    try? fileManager.removeItem(at: target)
  }

  func clear() {
    try? fileManager.removeItem(at: rootURL)
  }

  private func fileName(for messageId: String) -> String {
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
    let clean = messageId.unicodeScalars.map { scalar in
      allowed.contains(scalar) ? String(scalar) : "_"
    }
    .joined()
    .trimmingCharacters(in: CharacterSet(charactersIn: "._-").union(.whitespacesAndNewlines))
    .ifBlank(UUID().uuidString)
    return "\(String(clean.prefix(120))).json"
  }

  private let fileNamePattern = #"^[A-Za-z0-9._-]{1,160}\.json$"#
  private let pathSeparator = "/"
}
