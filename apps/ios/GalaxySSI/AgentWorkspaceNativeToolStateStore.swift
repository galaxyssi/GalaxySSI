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

protocol AgentWorkspaceNativeToolCheckedStateStore: AgentWorkspaceNativeToolStateStore {
  func loadChecked() throws -> [String: [String: AgentWorkspaceNativeToolStoredEntry]]
  func saveChecked(_ workspaces: [String: [String: AgentWorkspaceNativeToolStoredEntry]]) throws
}

final class FileAgentWorkspaceNativeToolStateStore: AgentWorkspaceNativeToolCheckedStateStore {
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
    (try? loadChecked()) ?? [:]
  }

  func loadChecked() throws -> [String: [String: AgentWorkspaceNativeToolStoredEntry]] {
    lock.lock()
    defer { lock.unlock() }
    return try loadUnlocked()
  }

  private func loadUnlocked() throws -> [String: [String: AgentWorkspaceNativeToolStoredEntry]] {
    let data: Data
    do {
      data = try Data(contentsOf: fileURL)
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      return [:]
    }
    return try decoder.decode([String: [String: AgentWorkspaceNativeToolStoredEntry]].self, from: data)
  }

  func save(_ workspaces: [String: [String: AgentWorkspaceNativeToolStoredEntry]]) {
    try? saveChecked(workspaces)
  }

  func saveChecked(_ workspaces: [String: [String: AgentWorkspaceNativeToolStoredEntry]]) throws {
    lock.lock()
    defer { lock.unlock() }
    _ = try loadUnlocked()
    let directory = fileURL.deletingLastPathComponent()
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
    let data = try encoder.encode(workspaces)
    try data.write(to: fileURL, options: .atomic)
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    try? fileManager.removeItem(at: fileURL)
  }
}
