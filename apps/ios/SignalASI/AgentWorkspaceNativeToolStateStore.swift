import Foundation

struct AgentWorkspaceNativeToolStoredEntry: Codable, Equatable {
  var type: AgentWorkspaceEntryType
  var dataBase64: String
  var modifiedAtMillis: Int64

  init(type: AgentWorkspaceEntryType, data: Data, modifiedAtMillis: Int64) {
    self.type = type
    self.dataBase64 = data.base64EncodedString()
    self.modifiedAtMillis = modifiedAtMillis
  }

  enum CodingKeys: String, CodingKey {
    case type
    case dataBase64 = "data_base64"
    case modifiedAtMillis = "modified_at_millis"
  }

  func data() -> Data? {
    Data(base64Encoded: dataBase64)
  }
}

protocol AgentWorkspaceNativeToolStateStore {
  func load() -> [String: [String: AgentWorkspaceNativeToolStoredEntry]]
  func save(_ workspaces: [String: [String: AgentWorkspaceNativeToolStoredEntry]])
  func clear()
}

final class FileAgentWorkspaceNativeToolStateStore: AgentWorkspaceNativeToolStateStore {
  private let fileURL: URL
  private let fileManager: FileManager
  private let lock = NSLock()
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(fileURL: URL, fileManager: FileManager = .default) {
    self.fileURL = fileURL
    self.fileManager = fileManager
  }

  func load() -> [String: [String: AgentWorkspaceNativeToolStoredEntry]] {
    lock.lock()
    defer { lock.unlock() }
    guard fileManager.fileExists(atPath: fileURL.path),
          let data = try? Data(contentsOf: fileURL) else {
      return [:]
    }
    return (try? decoder.decode([String: [String: AgentWorkspaceNativeToolStoredEntry]].self, from: data)) ?? [:]
  }

  func save(_ workspaces: [String: [String: AgentWorkspaceNativeToolStoredEntry]]) {
    lock.lock()
    defer { lock.unlock() }
    do {
      let directory = fileURL.deletingLastPathComponent()
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
      let data = try encoder.encode(workspaces)
      try data.write(to: fileURL, options: .atomic)
    } catch {
      // Workspace persistence must not break native tool execution.
    }
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    try? fileManager.removeItem(at: fileURL)
  }
}
