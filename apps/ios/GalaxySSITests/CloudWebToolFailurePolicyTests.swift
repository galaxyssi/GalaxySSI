import Foundation
import XCTest
@testable import GalaxySSI

final class CloudWebToolFailurePolicyTests: XCTestCase {
  func testStructuredTimeoutCodesAndStatusSupplyNonRetryableGuidance() {
    for code in ["timeout", "web_media_timeout", "web_source_timeout"] {
      let payload: AgentMcpJSONObject = ["error": .object(["code": .string(code), "retryable": .bool(true)]),
        "output": .object(["source_receipts": .array([.object(["status": .string("failed")])])])]
      let result = CloudWebToolFailurePolicy.applying(to: payload, status: .failed, code: code)
      XCTAssertEqual(result["error_code"], .string("web_source_timeout"))
      XCTAssertEqual(result["retryable"], .bool(false))
      XCTAssertEqual(result["error"], payload["error"])
      XCTAssertEqual(result["output"], payload["output"])
      XCTAssertTrue(result["next_action"]?.stringValue?.contains("same URL") == true)
    }
    XCTAssertEqual(CloudWebToolFailurePolicy.applying(to: [:], status: .timedOut, code: nil)["error_code"], .string("web_source_timeout"))
  }

  func testStoppedRendererAndEngineFailuresHaveDistinctActions() {
    for code in ["cancelled", "web_media_cancelled", "web_execution_stopped", "web_budget_exceeded"] {
      XCTAssertEqual(CloudWebToolFailurePolicy.applying(to: [:], status: .failed, code: code)["error_code"], .string("web_execution_stopped"))
    }
    let renderer = CloudWebToolFailurePolicy.applying(to: [:], status: .failed, code: "renderer_unavailable")
    XCTAssertEqual(renderer["retryable"], .bool(false))
    XCTAssertTrue(renderer["next_action"]?.stringValue?.contains("instead of claiming the page was read") == true)
    for code in ["unsupported_search_engine", "unsupported_image_engine", "invalid_engine"] {
      let engine = CloudWebToolFailurePolicy.applying(to: [:], status: .failed, code: code)
      XCTAssertEqual(engine["error_code"], .string("invalid_engine"))
      XCTAssertTrue(engine["next_action"]?.stringValue?.contains("only if the user did not require a specific source") == true)
    }
  }

  func testSuccessfulStaticEvidenceAndUnrelatedFailuresRemainUnchanged() {
    let payload: AgentMcpJSONObject = ["status": .string("completed"), "metadata": .object(["dynamic_fallback_error": .string("renderer_unavailable")])]
    XCTAssertEqual(CloudWebToolFailurePolicy.applying(to: payload, status: .succeeded, code: "renderer_unavailable"), payload)
    for code in ["transport_failed", "invalid_engine_response", "permission_denied", "source_verification_required"] {
      XCTAssertEqual(CloudWebToolFailurePolicy.applying(to: payload, status: .failed, code: code), payload)
    }
    let untrustedMessage: AgentMcpJSONObject = ["error": .string("timeout renderer_unavailable invalid_engine")]
    XCTAssertEqual(CloudWebToolFailurePolicy.applying(to: untrustedMessage, status: .failed, code: nil), untrustedMessage)
  }

  func testTypedThrownFailuresAreClassifiedWithoutMessageGuessingAndStayBounded() {
    let result = CloudWebToolFailurePolicy.failure(tool: String(repeating: "t", count: 100), error: AgentNativeToolInvocationError.timedOut)
    XCTAssertEqual(result["tool"]?.stringValue?.count, 80)
    XCTAssertEqual(result["native_status"], .string("timed_out"))
    XCTAssertEqual(result["error_code"], .string("web_source_timeout"))
    XCTAssertEqual(CloudWebToolFailurePolicy.failure(tool: "web_fetch", error: AgentNativeToolInvocationError.cancelled)["error_code"], .string("web_execution_stopped"))
    XCTAssertEqual(CloudWebToolFailurePolicy.failure(tool: "web_fetch", error: AgentIOSDynamicWebRenderError.unavailable)["error_code"], .string("renderer_unavailable"))
    let generic = CloudWebToolFailurePolicy.failure(tool: "web_fetch", error: NSError(domain: "timeout", code: 1,
      userInfo: [NSLocalizedDescriptionKey: String(repeating: "x", count: 1_000)]))
    XCTAssertNil(generic["error_code"])
    XCTAssertEqual(generic["error"]?.stringValue?.count, 300)
  }

  func testActualNativeTimeoutGetsRootClassificationAndCrossReadReuse() throws {
    let transport = FailedWebTransport()
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("web-timeout-hint-\(UUID()).json")
    defer { removeWebCacheFixture(file) }
    let provider = AgentIOSURLSessionWebIntelligenceProvider(webMediaProvider: AgentIOSURLSessionWebMediaToolProvider(
      transport: transport, sourceHealthStore: nil), cacheStore: AgentIOSWebIntelligenceCacheStore(fileURL: file, secrets: InMemorySecretStore()))
    let url = "https://source.test/timeout"
    let output = CloudWebGrounding.executeTool(provider: provider, name: "web_fetch", arguments: ["url": .string(url)],
      context: .init(grantedPermissions: [AgentIOSWebIntelligenceNativeToolCatalog.networkPermission],
        grantedConsents: [AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent]))
    let decoded = try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(output.utf8))
    XCTAssertEqual(decoded["error_code"], .string("web_source_timeout"))
    XCTAssertEqual(decoded["error"]?.objectValue?["code"], .string("web_media_timeout"))
    XCTAssertEqual(decoded["retryable"], .bool(false))
    XCTAssertEqual(transport.requests.count, 1)
    let progress = CloudWebToolLoopProgress()
    XCTAssertTrue(progress.record(toolName: "web_fetch", arguments: ["url": .string(url)], output: output))
    for tool in ["web_extract", "web_diff"] {
      XCTAssertEqual(progress.cached(toolName: tool, arguments: ["url": .string(url), "force": .bool(true)]), output)
    }
    XCTAssertNil(progress.cached(toolName: "web_extract", arguments: ["url": .string("https://source.test/other")]))
    XCTAssertEqual(transport.requests.count, 1)
  }

  func testActualURLSessionTimeoutIsNotFlattenedIntoGenericTransportFailure() throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [WebFailureURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let transport = AgentIOSDefaultURLSessionWebTransport(session: session)
    XCTAssertThrowsError(try transport.execute(.init(method: .get, url: XCTUnwrap(URL(string: "https://source.test/page")),
      timeoutMillis: 5_000, maxBodyBytes: 1_024, headers: [:]))) { error in
      guard let web = error as? AgentIOSURLSessionWebError else { return XCTFail("Expected a typed WebMedia error") }
      guard case .timeout = web else {
        return XCTFail("Expected the typed timeout, not a generic transport error: \(error)")
      }
    }
  }

  func testRegistryInvalidEngineDoesNotSilentlySearchAlternativeSources() throws {
    let transport = FailedWebTransport()
    let provider = AgentIOSURLSessionWebIntelligenceProvider(webMediaProvider: AgentIOSURLSessionWebMediaToolProvider(transport: transport, sourceHealthStore: nil))
    let encoded = CloudWebGrounding.executeTool(provider: provider, name: "web_search",
      arguments: ["query": .string("exact subject"), "engines": .array([.string("invented-engine")])],
      context: .init(grantedPermissions: [AgentIOSWebIntelligenceNativeToolCatalog.networkPermission],
        grantedConsents: [AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent]))
    let result = try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(encoded.utf8))
    XCTAssertEqual(result["error_code"], .string("invalid_engine"))
    XCTAssertEqual(result["retryable"], .bool(false))
    XCTAssertTrue(transport.requests.isEmpty)
  }
}

private final class FailedWebTransport: AgentIOSURLSessionWebTransporting {
  private(set) var requests: [AgentIOSURLSessionWebRequest] = []
  func execute(_ request: AgentIOSURLSessionWebRequest) throws -> AgentIOSURLSessionWebResponse {
    requests.append(request)
    throw AgentIOSURLSessionWebError.timeout
  }
}

private final class WebFailureURLProtocol: URLProtocol {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.timedOut)) }
  override func stopLoading() {}
}
