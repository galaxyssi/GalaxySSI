import Foundation
import ImageIO
import PDFKit
import UIKit

enum AgentIOSWeChatArticlePDF {
  enum ExportError: Error { case articleUnavailable, pageLimit }
  static func articleURL(_ value: String) -> URL? {
    let input = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard input.utf8.count <= 4_096, !input.contains(where: \.isWhitespace),
      let parts = URLComponents(string: input), parts.scheme?.lowercased() == "https",
      parts.host?.lowercased() == "mp.weixin.qq.com", parts.user == nil, parts.password == nil,
      parts.port == nil, parts.path == "/s" || (parts.path.hasPrefix("/s/") && parts.path.count > 3) else { return nil }
    return parts.url
  }
  static func invocation(clock: AgentIOSWeChatExportClock, duration: Int64) throws -> AgentNativeToolInvocation {
    guard let definition = AgentIOSWebIntelligenceNativeToolCatalog.definitions()
      .first(where: { $0.descriptor.id == AgentIOSWebIntelligenceNativeToolCatalog.fetch }) else { throw AgentIOSWeChatArticleFailure.loadFailed }
    let id = UUID().uuidString.lowercased(), start = clock.now(), deadline = min(start + duration, clock.origin + 300_000)
    return AgentNativeToolInvocation(descriptor: definition.descriptor, input: [:],
      context: AgentNativeToolInvocationContext(sessionId: id, turnId: id, callerId: "galaxyssi.wechat_pdf",
        requestedAtEpochMillis: start, deadlineEpochMillis: deadline,
        grantedPermissions: [AgentIOSWebIntelligenceNativeToolCatalog.networkPermission],
        grantedConsents: [AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent]),
      startedAtEpochMillis: start, deadlineEpochMillis: deadline, nowMillis: clock.now,
      cancellationRequested: { Task.isCancelled }, progressReporter: { _, _ in })
  }
  static func save(url: URL, messages: AgentIOSWeChatArticleMessages) async throws -> AgentIOSWeChatArticlePDFResult {
    guard articleURL(url.absoluteString) != nil else { throw AgentIOSWeChatArticleFailure.bodyUnavailable }
    let lease = try AgentIOSWeChatExportGate.shared.acquire(), clock = AgentIOSWeChatExportClock()
    defer { withExtendedLifetime(lease) {} }
    let fetch = Task.detached(priority: .userInitiated) {
      let provider = AgentIOSURLSessionWebMediaToolProvider(nowMillis: clock.now)
      return try provider.weChatPDFSource(url: url, invocation: invocation(clock: clock, duration: 45_000))
    }
    let source: AgentIOSWeChatArticleSource
    do {
      source = try await withTaskCancellationHandler(operation: { try await fetch.value }, onCancel: { fetch.cancel() })
      try Task.checkCancellation()
    } catch {
      if Task.isCancelled { throw CancellationError() }
      if case AgentIOSURLSessionWebError.responseTooLarge = error { throw AgentIOSWeChatArticleFailure.tooLarge }
      throw (error as? AgentIOSWeChatArticleFailure) ?? .loadFailed
    }
    let document: AgentIOSWeChatArticleDocument
    do { document = try await AgentIOSWeChatArticleDOM.parse(html: source.html, url: source.url) }
    catch {
      if Task.isCancelled { throw CancellationError() }
      throw (error as? AgentIOSWeChatArticleFailure) ?? .bodyUnavailable
    }
    guard !source.httpError else { throw AgentIOSWeChatArticleFailure.loadFailed }
    return try await exportLoaded(document: document, url: source.url, messages: messages, lease: lease, clock: clock)
  }
  static func exportLoaded(document: AgentIOSWeChatArticleDocument, url: URL, messages: AgentIOSWeChatArticleMessages,
                           lease: AgentIOSWeChatExportGate.Lease, clock: AgentIOSWeChatExportClock) async throws -> AgentIOSWeChatArticlePDFResult {
    guard articleURL(url.absoluteString) != nil else { throw AgentIOSWeChatArticleFailure.bodyUnavailable }
    try document.validate()
    let worker = Task.detached(priority: .userInitiated) {
      defer { withExtendedLifetime(lease) {} }
      return try AgentIOSWeChatArticleRenderer.render(document: document, url: url, messages: messages, clock: clock)
    }
    let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    do { try Task.checkCancellation() }
    catch { try? FileManager.default.removeItem(at: result.url); throw error }
    return result
  }
}
