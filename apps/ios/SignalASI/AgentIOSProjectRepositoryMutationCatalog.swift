import Foundation

enum AgentIOSProjectRepositoryMutationOperation: String, CaseIterable, Identifiable {
  case clone
  case fetch
  case checkout
  case commit
  case pull

  var id: String { rawValue }
}

enum AgentIOSProjectRepositoryMutationToolCatalog {
  static let clone = "signalasi.project.repository.clone"
  static let fetch = "signalasi.project.repository.fetch"
  static let checkout = "signalasi.project.repository.branch.checkout"
  static let commit = "signalasi.project.repository.commit"
  static let pull = "signalasi.project.repository.pull"

  static let executorId = "signalasi.ios_project_repository_mutation"
  static let writeConsent = "signalasi.consent.project_write"
  static let toolIds: Set<String> = [clone, fetch, checkout, commit, pull]

  static func definitions(
    runtimeProvider: AgentIOSOnDeviceRuntimeToolProviding
  ) -> [AgentPhoneNativeToolDefinition] {
    AgentIOSProjectRepositoryMutationOperation.allCases.map {
      definition($0, runtimeProvider: runtimeProvider)
    }
  }

  static func operation(for toolId: String) -> AgentIOSProjectRepositoryMutationOperation? {
    switch toolId {
    case clone: return .clone
    case fetch: return .fetch
    case checkout: return .checkout
    case commit: return .commit
    case pull: return .pull
    default: return nil
    }
  }

  private static func definition(
    _ operation: AgentIOSProjectRepositoryMutationOperation,
    runtimeProvider: AgentIOSOnDeviceRuntimeToolProviding
  ) -> AgentPhoneNativeToolDefinition {
    let descriptor = try! AgentNativeToolDescriptor(
      id: toolId(operation),
      version: AgentPhoneNativeToolCatalog.version,
      title: title(operation),
      description: description(operation),
      location: .application,
      inputSchema: inputSchema(operation),
      outputSchema: outputSchema(operation),
      risk: .medium,
      capabilities: ["project.repository.write", "runtime.linux", "git.write"],
      requiredPermissions: [
        AgentNativePermissionRequirement(
          id: AgentIOSOnDeviceRuntimeNativeToolCatalog.runtimePermission,
          title: "iOS on-device runtime",
          description: "Runs bounded Git commands inside the embedded Debian 1.3.9 runtime."
        ),
        AgentNativePermissionRequirement(
          id: AgentIOSOnDeviceRuntimeNativeToolCatalog.workspacePermission,
          title: "Runtime project workspace",
          description: "Restricts Git mutations to the current conversation project."
        )
      ],
      requiredConsents: [
        AgentNativeConsentRequirement(
          id: writeConsent,
          title: "Modify phone project repository",
          description: "Allows repository preparation and branch or remote-ref updates in the current project."
        )
      ],
      timeoutMillis: operation == .clone || operation == .fetch || operation == .pull
        ? 30 * 60_000
        : 5 * 60_000,
      idempotency: operation == .commit ? .idempotencyKeyRequired : .idempotent,
      availability: runtimeProvider.availability(operation: .execute)
    )
    return AgentPhoneNativeToolDefinition(
      descriptor: descriptor,
      executorId: executorId,
      provenanceMetadata: [
        "platform": "ios",
        "compatibility_source": "AgentMobileProjectNativeTools",
        "runtime": runtimeProvider.implementationId,
        "scope": "conversation_project",
        "credential_transport": "signed_guest_secret_environment"
      ]
    )
  }

  private static func toolId(_ operation: AgentIOSProjectRepositoryMutationOperation) -> String {
    switch operation {
    case .clone: return clone
    case .fetch: return fetch
    case .checkout: return checkout
    case .commit: return commit
    case .pull: return pull
    }
  }

  private static func title(_ operation: AgentIOSProjectRepositoryMutationOperation) -> String {
    switch operation {
    case .clone: return "Prepare a repository in the phone project"
    case .fetch: return "Fetch phone project remote refs"
    case .checkout: return "Switch the phone project branch"
    case .commit: return "Commit verified phone project changes"
    case .pull: return "Update the phone project from its remote"
    }
  }

  private static func description(_ operation: AgentIOSProjectRepositoryMutationOperation) -> String {
    switch operation {
    case .clone:
      return "Installs Git when needed, clones or updates a trusted GitHub repository, optionally prepares a feature branch, and returns verified repository metadata from one iOS Debian execution."
    case .fetch:
      return "Fetches validated remote Git refs without merging them. A configured GitHub token is injected only into the built-in guest process."
    case .checkout:
      return "Creates or checks out a validated Git branch after confirming the working tree is clean."
    case .commit:
      return "Stages current project changes and creates a local Git commit after the model has inspected and verified the result."
    case .pull:
      return "Fetches a validated remote branch and fast-forwards the clean current branch inside the iOS Debian guest."
    }
  }

  private static func inputSchema(_ operation: AgentIOSProjectRepositoryMutationOperation) -> AgentMcpJSONObject {
    var properties: [String: AgentMcpJSONValue] = [
      "workspace_id": .object(stringSchema(maxLength: 128))
    ]
    var required = ["workspace_id"]
    switch operation {
    case .clone:
      properties["repository_url"] = .object(stringSchema(maxLength: 2_048))
      properties["branch"] = .object(stringSchema(maxLength: 128))
      properties["feature_branch"] = .object(stringSchema(maxLength: 128))
      properties["depth"] = .object(integerSchema(minimum: 1, maximum: 100))
      properties["replace_existing"] = .object(["type": .string("boolean")])
      required.append("repository_url")
    case .fetch:
      properties["remote"] = .object(stringSchema(maxLength: 64))
      properties["ref"] = .object(stringSchema(maxLength: 128))
    case .checkout:
      properties["branch"] = .object(stringSchema(maxLength: 128))
      properties["base_ref"] = .object(stringSchema(maxLength: 128))
      properties["create"] = .object(["type": .string("boolean")])
      required.append("branch")
    case .commit:
      properties["message"] = .object(stringSchema(maxLength: 4_000))
      properties["author_name"] = .object(stringSchema(maxLength: 120))
      properties["author_email"] = .object(stringSchema(maxLength: 254))
      required.append("message")
    case .pull:
      properties["remote"] = .object(stringSchema(maxLength: 64))
      properties["branch"] = .object(stringSchema(maxLength: 128))
    }
    return objectSchema(properties: properties, required: required)
  }

  private static func outputSchema(_ operation: AgentIOSProjectRepositoryMutationOperation) -> AgentMcpJSONObject {
    var properties: [String: AgentMcpJSONValue] = [
      "workspace_id": .object(stringSchema(maxLength: 128)),
      "state": .object(stringSchema(maxLength: 32)),
      "repository_url": .object(stringSchema(maxLength: 2_048)),
      "branch": .object(stringSchema(maxLength: 128)),
      "head_commit": .object(stringSchema(maxLength: 128)),
      "clean": .object(["type": .string("boolean")])
    ]
    if operation == .fetch {
      properties["remote_refs"] = .object([
        "type": .string("array"),
        "items": .object(stringSchema(maxLength: 256)),
        "maxItems": .int(256)
      ])
    }
    if operation == .commit {
      properties["commit"] = .object(stringSchema(maxLength: 128))
      properties["changed_files"] = .object([
        "type": .string("array"),
        "items": .object(stringSchema(maxLength: 4_096)),
        "maxItems": .int(10_000)
      ])
    }
    return objectSchema(properties: properties, additionalProperties: true)
  }

  private static func objectSchema(
    properties: [String: AgentMcpJSONValue],
    required: [String] = [],
    additionalProperties: Bool = false
  ) -> AgentMcpJSONObject {
    [
      "type": .string("object"),
      "properties": .object(properties),
      "required": .array(required.map(AgentMcpJSONValue.string)),
      "additionalProperties": .bool(additionalProperties)
    ]
  }

  private static func stringSchema(maxLength: Int64) -> AgentMcpJSONObject {
    ["type": .string("string"), "maxLength": .int(maxLength)]
  }

  private static func integerSchema(minimum: Int64, maximum: Int64) -> AgentMcpJSONObject {
    [
      "type": .string("integer"),
      "minimum": .int(minimum),
      "maximum": .int(maximum)
    ]
  }
}
