import Foundation

extension CloudModelClient {
  func withContextOverflowRetry<T>(
    model: CloudModelConfig,
    apiKey: String,
    operation: (Int, Int) async throws -> T
  ) async throws -> T {
    let configuredWindow = CloudModelConversationContext.contextWindowTokens(model: model, apiKey: apiKey)
    let windows = CloudContextOverflowPolicy.retryWindows(configuredWindowTokens: configuredWindow)
    var lastOverflow: CloudHTTPFailure?
    for (attempt, contextWindow) in windows.enumerated() {
      do {
        return try await operation(contextWindow, attempt)
      } catch let failure as CloudHTTPFailure {
        guard CloudContextOverflowPolicy.isContextOverflow(failure), attempt < windows.count - 1 else {
          throw Self.cloudHTTPError(failure)
        }
        lastOverflow = failure
      }
    }
    throw lastOverflow.map(Self.cloudHTTPError) ??
      GalaxySSIError.invalidPayload("Cloud context retry ended without a result.")
  }

  static func cloudHTTPError(_ failure: CloudHTTPFailure) -> GalaxySSIError {
    if CloudContextOverflowPolicy.isContextOverflow(failure) {
      return .invalidPayload(
        "Cloud request exceeded the model context window. Try a shorter chat history or smaller attachment."
      )
    }
    return .invalidPayload(
      "Cloud request failed with \(failure.statusCode): \(failure.responseBody.prefix(240))"
    )
  }
}
