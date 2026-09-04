import Foundation

protocol AgentIOSSelfEvolutionTaskStoring {
  func save(_ task: AgentIOSSelfEvolutionTask) throws
  func get(_ taskId: String) throws -> AgentIOSSelfEvolutionTask?
  func list(limit: Int) throws -> [AgentIOSSelfEvolutionTask]
}

final class AgentIOSFileSelfEvolutionTaskStore: AgentIOSSelfEvolutionTaskStoring {
  private struct Snapshot: Codable {
    var formatVersion: Int
    var tasks: [AgentIOSSelfEvolutionTask]
  }

  private let fileURL: URL
  private let fileManager: FileManager
  private let lock = NSLock()

  init(
    fileURL: URL = AgentIOSFileSelfEvolutionTaskStore.defaultFileURL(),
    fileManager: FileManager = .default
  ) {
    self.fileURL = fileURL
    self.fileManager = fileManager
  }

  static func defaultFileURL(
    storageRootURL: URL = AgentNativeToolDefaultStorePaths.applicationSupportRootURL()
  ) -> URL {
    storageRootURL
      .appendingPathComponent("self-evolution", isDirectory: true)
      .appendingPathComponent("tasks.json", isDirectory: false)
  }

  func save(_ task: AgentIOSSelfEvolutionTask) throws {
    try locked {
      var tasks = try load()
      tasks.removeAll { $0.taskId == task.taskId }
      tasks.append(task)
      try persist(tasks)
    }
  }

  func get(_ taskId: String) throws -> AgentIOSSelfEvolutionTask? {
    try locked {
      try load().first { $0.taskId == taskId }
    }
  }

  func list(limit: Int = 100) throws -> [AgentIOSSelfEvolutionTask] {
    try locked {
      try load()
        .sorted {
          if $0.updatedAtMillis != $1.updatedAtMillis {
            return $0.updatedAtMillis > $1.updatedAtMillis
          }
          return $0.taskId < $1.taskId
        }
        .prefix(max(1, min(limit, 500)))
        .map { $0 }
    }
  }

  private func load() throws -> [AgentIOSSelfEvolutionTask] {
    guard fileManager.fileExists(atPath: fileURL.path) else {
      return []
    }
    let data = try Data(contentsOf: fileURL)
    guard !data.isEmpty else {
      return []
    }
    let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
    guard snapshot.formatVersion == formatVersion else {
      throw AgentIOSSelfEvolutionStoreError.invalidFormat
    }
    return snapshot.tasks.filter {
      $0.protocolId == AgentIOSSelfEvolutionNativeToolCatalog.protocolId &&
        $0.executionTarget == "ios" &&
        AgentIOSSelfEvolutionPolicy.isValidTaskId($0.taskId)
    }
  }

  private func persist(_ tasks: [AgentIOSSelfEvolutionTask]) throws {
    try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let snapshot = Snapshot(
      formatVersion: formatVersion,
      tasks: tasks.sorted {
        if $0.updatedAtMillis != $1.updatedAtMillis {
          return $0.updatedAtMillis > $1.updatedAtMillis
        }
        return $0.taskId < $1.taskId
      }
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(snapshot).write(to: fileURL, options: [.atomic])
  }

  private func locked<T>(_ action: () throws -> T) throws -> T {
    lock.lock()
    defer { lock.unlock() }
    return try action()
  }

  private let formatVersion = 1
}

enum AgentIOSSelfEvolutionStoreError: LocalizedError, Equatable {
  case invalidFormat

  var errorDescription: String? {
    switch self {
    case .invalidFormat:
      return "iOS self-evolution task store format is unsupported"
    }
  }
}
