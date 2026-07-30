import Foundation

struct AgentNativeToolPersistentStores {
  var replayStore: AgentNativeToolReplayStore
  var auditStore: AgentNativeToolAuditStore
}

struct AgentNativeToolDefaultStorePaths: Equatable {
  static let directoryName = "agent-native-tools"
  static let replayFileName = "replay_entries.json"
  static let auditFileName = "audit_records.json"

  var rootURL: URL

  var replayFileURL: URL {
    rootURL.appendingPathComponent(Self.replayFileName)
  }

  var auditFileURL: URL {
    rootURL.appendingPathComponent(Self.auditFileName)
  }

  static func applicationSupportRootURL(fileManager: FileManager = .default) -> URL {
    let base = fileManager
      .urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first ?? fileManager.temporaryDirectory
    return base
      .appendingPathComponent("SignalASI", isDirectory: true)
      .appendingPathComponent(directoryName, isDirectory: true)
  }
}

enum AgentNativeToolDefaultStores {
  static func makePersistentStores(
    rootURL: URL = AgentNativeToolDefaultStorePaths.applicationSupportRootURL(),
    fileManager: FileManager = .default,
    nowMillis: @escaping () -> Int64 = {
      Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    }
  ) -> AgentNativeToolPersistentStores {
    let paths = AgentNativeToolDefaultStorePaths(rootURL: rootURL)
    return AgentNativeToolPersistentStores(
      replayStore: FileAgentNativeToolReplayStore(
        fileURL: paths.replayFileURL,
        fileManager: fileManager,
        nowMillis: nowMillis
      ),
      auditStore: FileAgentNativeToolAuditStore(
        fileURL: paths.auditFileURL,
        fileManager: fileManager
      )
    )
  }
}
