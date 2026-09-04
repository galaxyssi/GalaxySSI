import CryptoKit
import Foundation

struct AgentFailureMemory: Codable, Equatable, Identifiable {
  var id: String
  var taskFamily: String
  var resourceId: String
  var failureReasons: [String]
  var inapplicableConditions: Set<String>
  var evidenceRunIds: [String]
  var evidenceCount: Int
  var firstObservedAtMillis: Int64
  var lastObservedAtMillis: Int64
  var revalidateAfterMillis: Int64
  var resolvedAtMillis: Int64

  var active: Bool { resolvedAtMillis <= 0 }

  init(
    id: String = UUID().uuidString,
    taskFamily: String,
    resourceId: String,
    failureReasons: [String],
    inapplicableConditions: Set<String>,
    evidenceRunIds: [String],
    evidenceCount: Int,
    firstObservedAtMillis: Int64,
    lastObservedAtMillis: Int64,
    revalidateAfterMillis: Int64,
    resolvedAtMillis: Int64 = 0
  ) {
    self.id = id
    self.taskFamily = taskFamily
    self.resourceId = resourceId
    self.failureReasons = Array(failureReasons.suffix(24))
    self.inapplicableConditions = Set(inapplicableConditions.prefix(16))
    self.evidenceRunIds = Array(evidenceRunIds.suffix(40))
    self.evidenceCount = max(1, evidenceCount)
    self.firstObservedAtMillis = max(0, firstObservedAtMillis)
    self.lastObservedAtMillis = max(0, lastObservedAtMillis)
    self.revalidateAfterMillis = max(0, revalidateAfterMillis)
    self.resolvedAtMillis = max(0, resolvedAtMillis)
  }
}

final class AgentFailureMemoryStore {
  private struct State: Codable { var memories: [String: AgentFailureMemory] = [:] }

  static let defaultKey = "galaxyssi-ios-agent-failure-memory-v1"
  private let defaults: UserDefaults
  private let secrets: GalaxySSISecretStore
  private let key: String
  private let nowMillis: () -> Int64
  private let lock = NSRecursiveLock()

  init(
    defaults: UserDefaults = .standard,
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared,
    key: String = AgentFailureMemoryStore.defaultKey,
    nowMillis: @escaping () -> Int64 = AgentEvalClock.nowMillis
  ) {
    self.defaults = defaults
    self.secrets = secrets
    self.key = key
    self.nowMillis = nowMillis
  }

  @discardableResult
  func observe(run: AgentRecordedRun, sample: AgentEvalSample) -> AgentFailureMemory? {
    guard !sample.passed, !sample.failureReasons.isEmpty else { return nil }
    let family = AgentLearningAnalyzer.taskFamily(run.originalRequest)
    guard !family.isBlank, !AgentLearningAnalyzer.containsSensitiveData(run.originalRequest) else { return nil }
    return locked {
      var state = load()
      let stable = AgentLearningAnalyzer.stableKey("\(family)|\(sample.resourceId)")
      let current = state.memories[stable]
      let observedAt = sample.completedAtMillis > 0 ? sample.completedAtMillis : nowMillis()
      let reasons = unique((current?.failureReasons ?? []) + sample.failureReasons)
      let conditions = Set(unique(
        Array(current?.inapplicableConditions ?? []) +
          sample.failureReasons.map { $0.components(separatedBy: ":").first ?? $0 } +
          [sample.condition.rawValue]
      ))
      let updated = AgentFailureMemory(
        id: current?.id ?? UUID().uuidString,
        taskFamily: family,
        resourceId: sample.resourceId,
        failureReasons: reasons,
        inapplicableConditions: conditions,
        evidenceRunIds: unique((current?.evidenceRunIds ?? []) + [run.runId]),
        evidenceCount: (current?.evidenceCount ?? 0) + 1,
        firstObservedAtMillis: current?.firstObservedAtMillis ?? observedAt,
        lastObservedAtMillis: observedAt,
        revalidateAfterMillis: observedAt + revalidationDelay(sample.condition)
      )
      state.memories[stable] = updated
      state.memories = Dictionary(uniqueKeysWithValues: state.memories
        .sorted { $0.value.lastObservedAtMillis > $1.value.lastObservedAtMillis }
        .prefix(Self.maximumItems))
      save(state)
      return updated
    }
  }

  @discardableResult
  func resolve(taskFamily: String, resourceId: String, atMillis: Int64? = nil) -> Bool {
    locked {
      var state = load()
      let stable = AgentLearningAnalyzer.stableKey("\(taskFamily)|\(resourceId)")
      guard var current = state.memories[stable] else { return false }
      current.resolvedAtMillis = max(0, atMillis ?? nowMillis())
      state.memories[stable] = current
      save(state)
      return true
    }
  }

  func list(activeOnly: Bool = false, limit: Int = AgentFailureMemoryStore.maximumItems) -> [AgentFailureMemory] {
    locked {
      Array(load().memories.values)
        .filter { !activeOnly || $0.active }
        .sorted { $0.lastObservedAtMillis > $1.lastObservedAtMillis }
        .prefixArray(min(max(limit, 1), Self.maximumItems))
    }
  }

  func dueForRevalidation(nowMillis: Int64? = nil) -> [AgentFailureMemory] {
    let now = nowMillis ?? self.nowMillis()
    return list(activeOnly: true).filter { $0.revalidateAfterMillis <= now }
  }

  private func revalidationDelay(_ condition: AgentEvalCondition) -> Int64 {
    switch condition {
    case .networkLoss, .processDeath: return 24 * 60 * 60_000
    case .doze, .reboot: return 3 * 24 * 60 * 60_000
    case .normal: return 7 * 24 * 60 * 60_000
    }
  }

  private func unique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.compactMap { value in
      let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return clean.isEmpty || !seen.insert(clean).inserted ? nil : clean
    }
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

  static let maximumItems = 1_000
}

struct AgentSkillMarkdownInspection: Equatable {
  var manifest: AgentSkillManifest
  var signed: Bool
  var signatureValid: Bool
  var signerFingerprint: String = ""
  var warnings: [String] = []
}

enum AgentSkillMarkdownCodec {
  static func encode(_ manifest: AgentSkillManifest) -> String {
    let markdown = """
    ---
    name: \(yamlScalar(manifest.id))
    description: \(yamlScalar(manifest.description.ifBlank(manifest.name)))
    version: \(yamlScalar(manifest.version))
    author: \(yamlScalar(manifest.author))
    ---

    # \(manifest.name)

    \(manifest.instructions.trimmingCharacters(in: .whitespacesAndNewlines))

    ## GalaxySSI Workflow

    \(jsonBlockStart)
    \(AgentSkillManifestCodec.encode(manifest))
    ```
    """
    return String(markdown.prefix(maximumMarkdownCharacters))
  }

  static func decode(_ markdown: String) -> AgentSkillManifest? {
    let clean = String(markdown.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumMarkdownCharacters))
    guard !clean.isEmpty else { return nil }
    if let embedded = embeddedManifest(clean) {
      var manifest = embedded
      manifest.source = "repository"
      manifest.autoInvoke = false
      return manifest
    }
    let metadata = frontmatter(clean)
    let id = normalizeSkillId(metadata["name"] ?? "")
    let description = String((metadata["description"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(1_000))
    guard !id.isEmpty, !description.isEmpty else { return nil }
    let versionValue = metadata["version"] ?? ""
    let version = versionValue.range(of: versionPattern, options: .regularExpression) != nil ? versionValue : "1.0.0"
    let sections = clean.components(separatedBy: "---")
    let bodySource = sections.count >= 3 ? sections.dropFirst(2).joined(separator: "---") : clean
    let body = bodySource
      .split(separator: "\n", omittingEmptySubsequences: false)
      .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("# ") }
      .joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !body.isEmpty else { return nil }
    let toolId = AgentConversationSkillCompiler.agentOrchestrationToolId
    return AgentSkillManifest(
      id: id,
      name: id.replacingOccurrences(of: "-", with: " ").capitalized,
      version: version,
      summary: description,
      instructions: String(body.prefix(32_000)),
      nativeTools: [toolId],
      parameters: AgentSkillParameterSchema.objectSchema(
        properties: ["request": .string(minLength: 1, maxLength: 8_000)],
        required: ["request"]
      ),
      steps: [AgentSkillStep(id: "step_1", toolId: toolId, input: ["request": .string("{{parameters.request}}")])],
      description: description,
      author: String((metadata["author"] ?? "External Skill").prefix(200)),
      source: "repository",
      autoInvoke: false,
      triggerExamples: [description]
    )
  }

  private static func embeddedManifest(_ markdown: String) -> AgentSkillManifest? {
    guard let start = markdown.range(of: jsonBlockStart) else { return nil }
    let tail = markdown[start.upperBound...]
    guard let end = tail.range(of: "```") else { return nil }
    return AgentSkillManifestCodec.decode(String(tail[..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines))
  }

  private static func frontmatter(_ markdown: String) -> [String: String] {
    guard markdown.hasPrefix("---") else { return [:] }
    let remainder = markdown.dropFirst(3)
    guard let end = remainder.range(of: "---") else { return [:] }
    return remainder[..<end.lowerBound].split(separator: "\n").reduce(into: [:]) { values, line in
      let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
      guard parts.count == 2 else { return }
      let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
      if !key.isEmpty, !value.isEmpty { values[key] = value }
    }
  }

  private static func normalizeSkillId(_ value: String) -> String {
    let normalized = value.lowercased().replacingOccurrences(
      of: #"[^a-z0-9._-]+"#,
      with: "-",
      options: .regularExpression
    )
    return String(normalized.trimmingCharacters(in: CharacterSet(charactersIn: "-._")).prefix(96))
  }

  private static func yamlScalar(_ value: String) -> String {
    let escaped = value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\r", with: " ")
      .replacingOccurrences(of: "\n", with: " ")
    return "\"\(String(escaped.prefix(1_000)))\""
  }

  private static let jsonBlockStart = "```galaxyssi-skill-json"
  private static let versionPattern = #"^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9._-]+)?$"#
  private static let maximumMarkdownCharacters = 128_000
}

enum AgentSkillMarkdownSigner {
  private struct Envelope: Codable {
    var format: String
    var skillMd: String
    var signerFingerprint: String
    var signerPublicKey: String
    var signature: String

    enum CodingKeys: String, CodingKey {
      case format
      case skillMd = "skill_md"
      case signerFingerprint = "signer_fingerprint"
      case signerPublicKey = "signer_public_key"
      case signature
    }
  }

  static func sign(
    _ markdown: String,
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared
  ) throws -> String {
    let clean = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { throw AgentSkillMarkdownError("SKILL.md content is empty") }
    let key = try signingKey(secrets: secrets)
    let payload = Data(clean.utf8)
    let signature = try key.signature(for: payload).derRepresentation.base64EncodedString()
    let publicKey = key.publicKey.x963Representation
    let fingerprint = SHA256.hash(data: publicKey).map { String(format: "%02x", $0) }.joined()
    let envelope = Envelope(
      format: envelopeFormat,
      skillMd: clean,
      signerFingerprint: fingerprint,
      signerPublicKey: publicKey.base64EncodedString(),
      signature: signature
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return String(decoding: try encoder.encode(envelope), as: UTF8.self)
  }

  static func inspect(_ raw: String) -> AgentSkillMarkdownInspection? {
    let envelope = raw.data(using: .utf8).flatMap { try? JSONDecoder().decode(Envelope.self, from: $0) }
    let signed = envelope?.format == envelopeFormat
    let markdown = signed ? envelope?.skillMd ?? "" : raw
    guard let manifest = AgentSkillMarkdownCodec.decode(markdown) else { return nil }
    guard signed, let envelope else {
      return AgentSkillMarkdownInspection(
        manifest: manifest,
        signed: false,
        signatureValid: false,
        warnings: ["Unsigned SKILL.md requires review and installs disabled"]
      )
    }
    let valid = verify(envelope: envelope)
    return AgentSkillMarkdownInspection(
      manifest: manifest,
      signed: true,
      signatureValid: valid,
      signerFingerprint: envelope.signerFingerprint,
      warnings: valid ? [] : ["SKILL.md signature verification failed"]
    )
  }

  private static func verify(envelope: Envelope) -> Bool {
    guard let publicData = Data(base64Encoded: envelope.signerPublicKey),
          let publicKey = try? P256.Signing.PublicKey(x963Representation: publicData),
          let signatureData = Data(base64Encoded: envelope.signature),
          let signature = try? P256.Signing.ECDSASignature(derRepresentation: signatureData) else { return false }
    let fingerprint = SHA256.hash(data: publicData).map { String(format: "%02x", $0) }.joined()
    return fingerprint == envelope.signerFingerprint &&
      publicKey.isValidSignature(signature, for: Data(envelope.skillMd.utf8))
  }

  private static func signingKey(secrets: GalaxySSISecretStore) throws -> P256.Signing.PrivateKey {
    if let encoded = secrets.string(account: signingKeyAccount),
       let data = Data(base64Encoded: encoded),
       let key = try? P256.Signing.PrivateKey(rawRepresentation: data) {
      return key
    }
    let key = P256.Signing.PrivateKey()
    try secrets.setString(key.rawRepresentation.base64EncodedString(), account: signingKeyAccount)
    return key
  }

  private static let envelopeFormat = "galaxyssi-signed-skill-md-v1"
  private static let signingKeyAccount = "galaxyssi-ios-skill-markdown-signing-v1"
}

final class AgentSkillMarkdownInstaller {
  private let runtime: AgentSkillRuntime

  init(runtime: AgentSkillRuntime) {
    self.runtime = runtime
  }

  func inspect(_ raw: String) throws -> AgentSkillMarkdownInspection {
    guard let inspected = AgentSkillMarkdownSigner.inspect(raw) else {
      throw AgentSkillMarkdownError("SKILL.md is malformed")
    }
    try runtime.validate(inspected.manifest).requireValid()
    return inspected
  }

  func installForReview(_ raw: String) throws -> AgentSkillInstallation {
    let inspected = try inspect(raw)
    guard !inspected.signed || inspected.signatureValid else {
      throw AgentSkillMarkdownError("SKILL.md signature is invalid")
    }
    var manifest = inspected.manifest
    manifest.autoInvoke = false
    return try runtime.install(manifest, enabled: false)
  }

  func approveSignAndInstall(_ markdown: String) throws -> AgentSkillInstallation {
    let inspected = try inspect(AgentSkillMarkdownSigner.sign(markdown))
    guard inspected.signed, inspected.signatureValid else {
      throw AgentSkillMarkdownError("Local SKILL.md signing failed")
    }
    var manifest = inspected.manifest
    manifest.autoInvoke = false
    return try runtime.install(manifest, enabled: true)
  }
}

struct AgentSkillMarkdownError: LocalizedError, Equatable {
  var message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { message }
}

enum AgentTrajectoryLearningService {
  static func observe(
    run: AgentRecordedRun,
    sample: AgentEvalSample,
    failureStore: AgentFailureMemoryStore = AgentFailureMemoryStore(),
    governanceStore: AgentCognitiveGovernanceStore = AgentCognitiveGovernanceStore()
  ) {
    if sample.passed {
      _ = failureStore.resolve(
        taskFamily: AgentLearningAnalyzer.taskFamily(run.originalRequest),
        resourceId: sample.resourceId
      )
    } else {
      failureStore.observe(run: run, sample: sample)
    }
    AgentKnowledgeGapDetector.observe(store: governanceStore, run: run, sample: sample)
  }
}

private extension Array {
  func prefixArray(_ count: Int) -> [Element] { Array(prefix(count)) }
}
