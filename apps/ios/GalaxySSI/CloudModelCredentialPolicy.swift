import Foundation

enum CloudModelCredentialPolicy {
  private static let placeholderCredentials: Set<String> = [
    "key",
    "api-key",
    "your-api-key",
    "your_api_key",
    "replace-me",
    "replace_me"
  ]

  private static let debugCredentials: Set<String> = [
    "smoke-key",
    "backup-smoke-key",
    "sk-galaxyssi-smoke-key"
  ]

  static func isStoredCredential(_ value: String?) -> Bool {
    let credential = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if credential.isEmpty || credential.contains("*") {
      return false
    }
    return !placeholderCredentials.contains(credential.lowercased())
  }

  static func isDebugFixtureCredential(_ value: String?) -> Bool {
    let credential = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    return debugCredentials.contains(credential) ||
      credential.contains("galaxyssi-smoke") ||
      credential.hasPrefix("backup-smoke-")
  }

  static func isAutoRoutableCredential(_ value: String?) -> Bool {
    isStoredCredential(value) && !isDebugFixtureCredential(value)
  }

  static func isAutoRoutable(
    model: CloudModelConfig,
    apiKey: String?,
    provider: String,
    setupStatus: String = "ready"
  ) -> Bool {
    let endpoint = model.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    let modelId = model.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
    let status = setupStatus.trimmingCharacters(in: .whitespacesAndNewlines)
    return (status.isEmpty || status.localizedCaseInsensitiveCompare("ready") == .orderedSame) &&
      !provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !modelId.isEmpty &&
      modelId.localizedCaseInsensitiveCompare("model-id") != .orderedSame &&
      endpoint.lowercased().hasPrefix("https://") &&
      !endpoint.localizedCaseInsensitiveContains("example.com") &&
      isAutoRoutableCredential(apiKey)
  }
}
