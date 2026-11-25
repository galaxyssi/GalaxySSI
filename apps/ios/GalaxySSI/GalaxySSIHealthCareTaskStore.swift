import CryptoKit
import Foundation

enum GalaxySSIHealthCareTaskStore {
  static func fileURL(records: GalaxySSIHealthRecords) -> URL {
    if let isolated = records.isolatedFile { return isolated.appendingPathExtension("care-tasks") }
    let root = FileAgentWorkspaceStore.defaultStorageRootURL().deletingLastPathComponent()
      .appendingPathComponent("health-discussion-tasks", isDirectory: true)
    let name = SHA256.hash(data: context(records.owner)).map { String(format: "%02x", $0) }.joined()
    return root.appendingPathComponent(name + ".sealed")
  }

  static func make(records: GalaxySSIHealthRecords) -> FileAgentWorkspaceStore {
    let aad = context(records.owner)
    let account = "health.discussion.tasks.v1." + records.owner
    func key(create: Bool) throws -> SymmetricKey {
      if let encoded = records.secrets.string(account: account) {
        guard let data = Data(base64Encoded: encoded), data.count == 32 else {
          throw GalaxySSIHealthRecords.Failure.unavailable
        }
        return SymmetricKey(data: data)
      }
      guard create else { throw GalaxySSIHealthRecords.Failure.unavailable }
      let key = SymmetricKey(size: .bits256)
      try records.secrets.setString(key.withUnsafeBytes { Data($0).base64EncodedString() }, account: account)
      return key
    }
    return FileAgentWorkspaceStore(fileURL: fileURL(records: records), readFile: { url in
      let encrypted = try Data(contentsOf: url)
      return try AES.GCM.open(AES.GCM.SealedBox(combined: encrypted), using: key(create: false), authenticating: aad)
    }, writeFile: { data, url in
      if records.isolatedFile == nil {
        var directory = url.deletingLastPathComponent()
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
      }
      guard let sealed = try AES.GCM.seal(data, using: key(create: true), authenticating: aad).combined else {
        throw GalaxySSIHealthRecords.Failure.unavailable
      }
      try sealed.write(to: url, options: [.atomic, .completeFileProtection])
    })
  }

  private static func context(_ owner: String) -> Data {
    Data("galaxyssi.health.discussion.tasks.v1:\(owner)".utf8)
  }
}
