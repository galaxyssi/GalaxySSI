import Foundation

enum AgentIOSWorldVerifierKind: String, Codable, CaseIterable, Identifiable {
  case foregroundScreen = "foreground_screen"
  case visibleText = "visible_text"
  case appFile = "app_file"
  case userDefault = "user_default"

  var id: String { rawValue }
}

struct AgentIOSWorldVerifier: Codable, Equatable, Identifiable {
  var id: String
  var kind: AgentIOSWorldVerifierKind
  var target: String
  var operation: String
  var expected: String

  init(
    id: String = UUID().uuidString,
    kind: AgentIOSWorldVerifierKind,
    target: String,
    operation: String = "contains",
    expected: String = ""
  ) {
    self.id = id
    self.kind = kind
    self.target = String(target.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1_000))
    self.operation = operation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    self.expected = String(expected.prefix(4_000))
  }
}

struct AgentIOSWorldTask: Codable, Equatable, Identifiable {
  var id: String
  var instruction: String
  var verifiers: [AgentIOSWorldVerifier]
  var source: String
  var importedAtMillis: Int64
}

struct AgentIOSWorldObservation: Codable, Equatable {
  var foregroundScreen: String
  var visibleTexts: [String]
  var capturedAtMillis: Int64
}

struct AgentIOSWorldVerifierResult: Codable, Equatable, Identifiable {
  var id: String { verifierId }
  var verifierId: String
  var passed: Bool
  var actual: String
  var reason: String
}

struct AgentIOSWorldResult: Codable, Equatable, Identifiable {
  var id: String
  var taskId: String
  var runId: String
  var passed: Bool
  var verifierResults: [AgentIOSWorldVerifierResult]
  var completedAtMillis: Int64
}

enum AgentIOSWorldCodec {
  static func decodeTasks(_ data: Data, source: String = "import") throws -> [AgentIOSWorldTask] {
    let object = try JSONSerialization.jsonObject(with: data)
    let rawTasks: [[String: Any]]
    if let values = object as? [[String: Any]] {
      rawTasks = values
    } else if let root = object as? [String: Any], let values = root["tasks"] as? [[String: Any]] {
      rawTasks = values
    } else {
      throw CocoaError(.fileReadCorruptFile)
    }
    return rawTasks.compactMap { raw in
      let id = (raw["task_id"] as? String) ?? (raw["id"] as? String) ?? UUID().uuidString
      let instruction = ((raw["instruction"] as? String) ?? (raw["goal"] as? String) ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let rawVerifiers = (raw["verifiers"] as? [[String: Any]]) ?? (raw["success_criteria"] as? [[String: Any]]) ?? []
      let verifiers = rawVerifiers.compactMap(decodeVerifier)
      guard !instruction.isEmpty, !verifiers.isEmpty else { return nil }
      return AgentIOSWorldTask(
        id: String(id.prefix(240)),
        instruction: String(instruction.prefix(8_000)),
        verifiers: Array(verifiers.prefix(64)),
        source: String(source.prefix(240)),
        importedAtMillis: AgentEvalClock.nowMillis()
      )
    }
  }

  private static func decodeVerifier(_ raw: [String: Any]) -> AgentIOSWorldVerifier? {
    let kindValue = ((raw["kind"] as? String) ?? (raw["type"] as? String) ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let aliases: [String: AgentIOSWorldVerifierKind] = [
      "foreground_screen": .foregroundScreen,
      "foreground_package": .foregroundScreen,
      "visible_text": .visibleText,
      "app_file": .appFile,
      "user_default": .userDefault,
      "system_setting": .userDefault
    ]
    guard let kind = aliases[kindValue] else { return nil }
    return AgentIOSWorldVerifier(
      id: (raw["id"] as? String) ?? UUID().uuidString,
      kind: kind,
      target: (raw["target"] as? String) ?? (raw["key"] as? String) ?? "",
      operation: (raw["operator"] as? String) ?? (raw["operation"] as? String) ?? "contains",
      expected: (raw["expected"] as? String) ?? (raw["value"] as? String) ?? ""
    )
  }
}

final class AgentIOSWorldStore {
  private struct State: Codable {
    var tasks: [String: AgentIOSWorldTask] = [:]
    var results: [String: AgentIOSWorldResult] = [:]
  }

  static let defaultKey = "galaxyssi-ios-world-v1"
  private let defaults: UserDefaults
  private let secrets: GalaxySSISecretStore
  private let key: String
  private let lock = NSRecursiveLock()

  init(
    defaults: UserDefaults = .standard,
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared,
    key: String = AgentIOSWorldStore.defaultKey
  ) {
    self.defaults = defaults
    self.secrets = secrets
    self.key = key
  }

  func importTasks(_ tasks: [AgentIOSWorldTask]) -> Int {
    locked {
      var state = load()
      tasks.forEach { state.tasks[$0.id] = $0 }
      state.tasks = Dictionary(uniqueKeysWithValues: state.tasks.values
        .sorted { $0.importedAtMillis > $1.importedAtMillis }.prefix(2_000).map { ($0.id, $0) })
      save(state)
      return tasks.count
    }
  }

  func tasks(limit: Int = 2_000) -> [AgentIOSWorldTask] {
    locked { Array(load().tasks.values.sorted { $0.importedAtMillis > $1.importedAtMillis }.prefix(max(1, limit))) }
  }

  func matchingTask(instruction: String) -> AgentIOSWorldTask? {
    let normalized = Self.normalize(instruction)
    return tasks().first { task in
      normalized == Self.normalize(task.instruction) || normalized.contains("[iosworld:\(task.id.lowercased())]")
    }
  }

  func saveResult(_ result: AgentIOSWorldResult) {
    locked {
      var state = load()
      state.results[result.id] = result
      state.results = Dictionary(uniqueKeysWithValues: state.results.values
        .sorted { $0.completedAtMillis > $1.completedAtMillis }.prefix(2_000).map { ($0.id, $0) })
      save(state)
    }
  }

  func results(limit: Int = 200) -> [AgentIOSWorldResult] {
    locked { Array(load().results.values.sorted { $0.completedAtMillis > $1.completedAtMillis }.prefix(max(1, limit))) }
  }

  private func load() -> State {
    guard let data = GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults, key: key, secrets: secrets),
          let state = try? JSONDecoder().decode(State.self, from: data) else { return State() }
    return state
  }

  private func save(_ state: State) {
    guard let data = try? JSONEncoder().encode(state) else { return }
    _ = GalaxySSIEncryptedUserDefaultsStore.write(data, defaults: defaults, key: key, secrets: secrets)
  }

  private func locked<T>(_ work: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return work()
  }

  private static func normalize(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
  }
}

final class AgentIOSWorldBridge {
  static let shared = AgentIOSWorldBridge()

  private let lock = NSRecursiveLock()
  private var screenProvider: () -> AgentScreenContext = {
    AgentScreenContext(foregroundApp: "GalaxySSI iOS", pageTitle: "Agent")
  }
  private var store = AgentIOSWorldStore()

  private init() {}

  func install(screenProvider: @escaping () -> AgentScreenContext) {
    lock.lock()
    self.screenProvider = screenProvider
    lock.unlock()
  }

  func verify(run: AgentRecordedRun) -> AgentIOSWorldResult? {
    guard let task = store.matchingTask(instruction: run.originalRequest) else { return nil }
    let context = locked { screenProvider() }
    let observation = AgentIOSWorldObservation(
      foregroundScreen: [context.foregroundApp, context.activityName, context.pageTitle]
        .filter { !$0.isBlank }.joined(separator: " / "),
      visibleTexts: context.visibleTexts,
      capturedAtMillis: AgentEvalClock.nowMillis()
    )
    let results = task.verifiers.map { verify($0, observation: observation) }
    let result = AgentIOSWorldResult(
      id: UUID().uuidString,
      taskId: task.id,
      runId: run.runId,
      passed: !results.isEmpty && results.allSatisfy(\.passed),
      verifierResults: results,
      completedAtMillis: observation.capturedAtMillis
    )
    store.saveResult(result)
    return result
  }

  private func verify(_ verifier: AgentIOSWorldVerifier, observation: AgentIOSWorldObservation) -> AgentIOSWorldVerifierResult {
    let actual: String
    switch verifier.kind {
    case .foregroundScreen:
      actual = observation.foregroundScreen
    case .visibleText:
      actual = observation.visibleTexts.joined(separator: "\n")
    case .appFile:
      actual = fileValue(verifier.target)
    case .userDefault:
      actual = UserDefaults.standard.object(forKey: verifier.target).map(String.init(describing:)) ?? ""
    }
    let passed = compare(actual: actual, expected: verifier.expected, operation: verifier.operation)
    return AgentIOSWorldVerifierResult(
      verifierId: verifier.id,
      passed: passed,
      actual: String(actual.prefix(4_000)),
      reason: passed ? "verified" : "programmatic_verifier_failed"
    )
  }

  private func fileValue(_ path: String) -> String {
    let fileManager = FileManager.default
    let roots = [
      fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
      fileManager.urls(for: .documentDirectory, in: .userDomainMask).first,
      fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first,
      fileManager.temporaryDirectory
    ].compactMap { $0?.standardizedFileURL }
    let url = URL(fileURLWithPath: path).standardizedFileURL
    guard roots.contains(where: { root in
      url.path == root.path || url.path.hasPrefix(root.path + "/")
    }) else { return "" }
    guard fileManager.fileExists(atPath: url.path) else { return "" }
    return (try? String(contentsOf: url, encoding: .utf8)).map { String($0.prefix(32_000)) } ?? "exists"
  }

  private func compare(actual: String, expected: String, operation: String) -> Bool {
    let actual = actual.lowercased()
    let expected = expected.lowercased()
    switch operation {
    case "not_contains": return !actual.contains(expected)
    case "exists": return !actual.isEmpty
    case "not_exists": return actual.isEmpty
    case "equals": return actual == expected
    case "matches": return (try? NSRegularExpression(pattern: expected, options: [.caseInsensitive]))
      .map { $0.firstMatch(in: actual, range: NSRange(actual.startIndex..., in: actual)) != nil } ?? false
    default: return actual.contains(expected)
    }
  }

  private func locked<T>(_ work: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return work()
  }
}
