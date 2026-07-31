import Foundation

final class FileAgentMcpStore: AgentMcpStore {
  private let connectionsFileURL: URL
  private let secretsDirectoryURL: URL
  private let fileManager: FileManager
  private let lock = NSRecursiveLock()

  init(
    rootURL: URL,
    connectionsFileName: String = "connections.json",
    secretsDirectoryName: String = "secrets",
    fileManager: FileManager = .default
  ) {
    let root = rootURL.standardizedFileURL
    self.connectionsFileURL = root.appendingPathComponent(connectionsFileName, isDirectory: false)
    self.secretsDirectoryURL = root.appendingPathComponent(secretsDirectoryName, isDirectory: true)
    self.fileManager = fileManager
  }

  init(
    connectionsFileURL: URL,
    secretsDirectoryURL: URL,
    fileManager: FileManager = .default
  ) {
    self.connectionsFileURL = connectionsFileURL.standardizedFileURL
    self.secretsDirectoryURL = secretsDirectoryURL.standardizedFileURL
    self.fileManager = fileManager
  }

  static func defaultRootURL(
    storageRootURL: URL = AgentNativeToolDefaultStorePaths.applicationSupportRootURL()
  ) -> URL {
    storageRootURL.appendingPathComponent("mcp", isDirectory: true)
  }

  static func defaultConnectionsFileURL(rootURL: URL) -> URL {
    rootURL.appendingPathComponent("connections.json", isDirectory: false)
  }

  func list() -> [AgentMcpConnection] {
    synchronized {
      readConnections().sorted {
        let left = $0.displayName.lowercased()
        let right = $1.displayName.lowercased()
        if left == right { return $0.id < $1.id }
        return left < right
      }
    }
  }

  func upsert(_ connection: AgentMcpConnection) {
    synchronized {
      var connections = Dictionary(uniqueKeysWithValues: readConnections().map { ($0.id, $0) })
      connections[connection.id] = connection
      writeConnections(Array(connections.values))
    }
  }

  func delete(id: String) -> Bool {
    synchronized {
      var connections = Dictionary(uniqueKeysWithValues: readConnections().map { ($0.id, $0) })
      let removed = connections.removeValue(forKey: id) != nil
      guard removed else { return false }
      writeConnections(Array(connections.values))
      removeFile(secretsFileURL(id: id))
      return true
    }
  }

  func readSecrets(id: String) -> [String: String] {
    synchronized {
      let fileURL = secretsFileURL(id: id)
      guard fileManager.fileExists(atPath: fileURL.path),
            let document = try? String(contentsOf: fileURL, encoding: .utf8) else {
        return [:]
      }
      return AgentMcpConnectionCodec.decodeSecrets(document)
    }
  }

  func writeSecrets(id: String, values: [String: String]) {
    synchronized {
      write(
        AgentMcpConnectionCodec.encodeSecrets(values),
        to: secretsFileURL(id: id)
      )
    }
  }

  func clearSecrets(id: String) {
    synchronized {
      removeFile(secretsFileURL(id: id))
    }
  }

  func clear() {
    synchronized {
      writeConnections([])
      removeDirectory(secretsDirectoryURL)
    }
  }

  private func readConnections() -> [AgentMcpConnection] {
    guard fileManager.fileExists(atPath: connectionsFileURL.path),
          let document = try? String(contentsOf: connectionsFileURL, encoding: .utf8) else {
      return []
    }
    return AgentMcpConnectionCodec.decode(document)
  }

  private func writeConnections(_ connections: [AgentMcpConnection]) {
    write(AgentMcpConnectionCodec.encode(connections), to: connectionsFileURL)
  }

  private func write(_ document: String, to fileURL: URL) {
    do {
      try fileManager.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try document.write(to: fileURL, atomically: true, encoding: .utf8)
    } catch {
      return
    }
  }

  private func removeFile(_ fileURL: URL) {
    guard fileManager.fileExists(atPath: fileURL.path) else { return }
    try? fileManager.removeItem(at: fileURL)
  }

  private func removeDirectory(_ directoryURL: URL) {
    guard fileManager.fileExists(atPath: directoryURL.path) else { return }
    try? fileManager.removeItem(at: directoryURL)
  }

  private func secretsFileURL(id: String) -> URL {
    let digest = AgentMcpJSONCodec.sha256(["id": .string(id)])
    return secretsDirectoryURL.appendingPathComponent("\(digest).json", isDirectory: false)
  }

  private func synchronized<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }
}
