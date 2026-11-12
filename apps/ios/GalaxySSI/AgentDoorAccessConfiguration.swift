import Foundation

struct AgentDoorAccessConfiguration: Equatable {
  static let skillID = "com.galaxyssi.skill.door_access"
  static let toolID = "galaxyssi.door_access.open_panel"

  enum Command: Equatable { case list, open(String) }
  struct Target: Codable, Equatable, Identifiable {
    let id: String
    let service_name: String
    let display_name: String
    let commands: [String]
  }
  private struct Wire: Decodable {
    let version: Int
    let default_door: String
    let default_open_commands: [String]
    let list_commands: [String]
    let doors: [Target]
  }

  let targets: [Target]
  let version: String
  private let commands: [String: Command]

  init?(_ manifest: AgentSkillManifest) {
    guard manifest.id == Self.skillID, manifest.nativeTools == [Self.toolID], manifest.permissions.isEmpty,
          manifest.resources.isEmpty, manifest.mcpCatalogIds.isEmpty, manifest.steps.count == 1,
          let step = manifest.steps.first, step.toolId == Self.toolID, step.dependsOn.isEmpty,
          let raw = step.input["door_config"]?.objectValue else { return nil }
    let data = Data(AgentMcpJSONCodec.stringify(raw).utf8)
    guard data.count <= 64 * 1_024, let wire = try? JSONDecoder().decode(Wire.self, from: data), wire.version == 1,
          (1...32).contains(wire.doors.count),
          Set(wire.doors.map(\.id)).count == wire.doors.count,
          Set(wire.doors.map(\.service_name)).count == wire.doors.count,
          wire.doors.contains(where: { $0.id == wire.default_door }),
          wire.doors.allSatisfy({ target in
            target.id.range(of: #"\A[A-Za-z0-9._-]{1,64}\z"#, options: .regularExpression) != nil &&
              !target.service_name.isBlank && target.service_name.utf16.count <= 100 &&
              !target.display_name.isBlank && target.display_name.utf16.count <= 100
          }) else { return nil }
    var map: [String: Command] = [:]
    var total = 0
    func add(_ aliases: [String], _ command: Command) -> Bool {
      total += aliases.count
      guard total <= 512, (1...128).contains(aliases.count) else { return false }
      for original in aliases {
        let name = Self.normalized(original)
        guard original.utf16.count <= 80, !name.isEmpty, map[name] == nil || map[name] == command else { return false }
        map[name] = command
      }
      return true
    }
    guard add(wire.list_commands, .list), add(wire.default_open_commands, .open(wire.default_door)),
          wire.doors.allSatisfy({ add($0.commands, .open($0.id)) }) else { return nil }
    targets = wire.doors
    version = manifest.version
    commands = map
  }

  func command(_ request: String) -> Command? {
    guard request.utf16.count <= 80 else { return nil }
    return commands[Self.normalized(request)]
  }

  static func enabled(in store: AgentSkillStore = UserDefaultsAgentSkillStore(),
                      automatic: Bool = false) -> Self? {
    let candidates = store.list().filter { $0.id == skillID && $0.enabled && (!automatic || $0.autoInvoke) }
    guard let latest = candidates.map(\.installedAtMillis).max() else { return nil }
    let current = candidates.filter { $0.installedAtMillis == latest }
    guard current.count == 1, let installation = current.first else { return nil }
    return Self(installation.manifest)
  }

  private static func normalized(_ value: String) -> String {
    let variants: [Character: Character] = [
      "\u{958B}": "\u{5F00}", "\u{9580}": "\u{95E8}", "\u{5340}": "\u{533A}", "\u{55AE}": "\u{5355}",
      "\u{5E6B}": "\u{5E2E}", "\u{555F}": "\u{542F}", "\u{68DF}": "\u{680B}", "\u{83EF}": "\u{534E}",
      "\u{6F64}": "\u{6DA6}", "\u{5834}": "\u{573A}", "\u{5B78}": "\u{5B66}", "\u{5074}": "\u{4FA7}"
    ]
    return String(value.lowercased(with: Locale(identifier: "en_US_POSIX")).map { variants[$0] ?? $0 })
      .replacingOccurrences(of: "[\\s\\uFF0C,\\u3002.!\\uFF01?\\uFF1F;\\uFF1B]+", with: "", options: .regularExpression)
  }
}
