import Foundation
import XCTest
@testable import GalaxySSI

final class AgentIOSEncodedWebRequestTests: XCTestCase {
  func testPinnedAndroidEncodedPathAndSignedRedirectReachTransportUnchanged() throws {
    let original = "https://public.example.test/a%2Fb/%E4%B8%AD?q=%E5%B0%8F+fish&x=%25%26%3D%2B#fragment"
    let redirected = "https://public.example.test/image?name=%E4%B8%AD&sig=a%2Fb%3D%3D"
    let transport = EncodedWebTransport(locations: [redirected])
    let result = try call(original, transport: transport)
    XCTAssertTrue(result.isSuccess, result.error?.message ?? "")
    let expected = String(original.prefix { $0 != "#" })
    XCTAssertEqual(transport.requests.map(\.url.absoluteString), [expected, redirected])
    XCTAssertEqual(result.output["source"]?.objectValue?["requested_url"], .string(expected))
    XCTAssertEqual(result.output["source"]?.objectValue?["final_url"], .string(redirected))
    XCTAssertEqual(result.output["source"]?.objectValue?["redirect_chain"]?.arrayValue?.first?.objectValue?["to_url"], .string(redirected))
  }

  func testRelativeRedirectPreservesEncodedSeparatorsAndQueryOrder() throws {
    let original = "https://public.example.test/base/a%2fb?old=%252F"
    let transport = EncodedWebTransport(locations: ["../next%2fpart?a=%26&a=%3D&sig=AbC%2f%2B+%2525#ignored"])
    let result = try call(original, transport: transport)
    XCTAssertTrue(result.isSuccess, result.error?.message ?? "")
    XCTAssertEqual(transport.requests.map(\.url.absoluteString), [original,
      "https://public.example.test/next%2fpart?a=%26&a=%3D&sig=AbC%2f%2B+%2525"])
  }

  func testCaseSensitivePathAndQueryRedirectsAreNotFalseLoops() throws {
    let urls = ["https://public.example.test/Article?sig=AbC", "https://public.example.test/article?sig=AbC",
      "https://public.example.test/article?sig=abc"]
    let transport = EncodedWebTransport(locations: Array(urls.dropFirst()))
    let result = try call(urls[0], transport: transport)
    XCTAssertTrue(result.isSuccess, result.error?.message ?? "")
    XCTAssertEqual(transport.requests.map(\.url.absoluteString), urls)
  }

  func testFragmentOnlyRedirectStillStopsAsLoopWithoutRedispatch() throws {
    let transport = EncodedWebTransport(locations: ["#second-fragment"])
    let result = try call("https://public.example.test/same?q=%252f#first", transport: transport)
    XCTAssertFalse(result.isSuccess)
    XCTAssertEqual(result.error?.code, "redirect_loop")
    XCTAssertEqual(transport.requests.map(\.url.absoluteString), ["https://public.example.test/same?q=%252f"])
  }

  func testEmptyPathAndAuthorityNormalizeWithoutTouchingEncodedQuery() throws {
    let transport = EncodedWebTransport()
    let result = try call("HTTPS://PUBLIC.EXAMPLE.TEST?x=%2526&x=%26&plus=+&empty=#local", transport: transport)
    XCTAssertTrue(result.isSuccess, result.error?.message ?? "")
    XCTAssertEqual(transport.requests.first?.url.absoluteString, "https://public.example.test/?x=%2526&x=%26&plus=+&empty=")
  }

  func testCommonStatelessOperationsUseTheSamePreservedRequestAddress() throws {
    let expected = "https://public.example.test/a%2Fb?q=a%2Bb+c&sig=AbC%3D"
    for operation in [AgentIOSWebMediaOperation.webFetch, .webHead, .httpRequest, .webOpen] {
      let transport = EncodedWebTransport()
      let result = try call(expected + "#fragment", transport: transport, operation: operation)
      XCTAssertTrue(result.isSuccess, "\(operation.rawValue): \(result.error?.message ?? "")")
      XCTAssertEqual(transport.requests.map(\.url.absoluteString), [expected])
      XCTAssertEqual(transport.requests.first?.method, operation == .webHead ? .head : .get)
    }
  }

  func testPrivateCredentialedAndInsecureRedirectsStillStopBeforeNextDispatch() throws {
    for target in ["https://127.0.0.1/a%2Fb?sig=AbC", "https://user:secret@public.example.test/a%2Fb", "http://public.example.test/a%2Fb"] {
      let transport = EncodedWebTransport(locations: [target])
      let result = try call("https://public.example.test/start", transport: transport)
      XCTAssertFalse(result.isSuccess)
      XCTAssertEqual(transport.requests.count, 1)
    }
  }

  private func call(_ address: String, transport: EncodedWebTransport,
    operation: AgentIOSWebMediaOperation = .webFetch) throws -> AgentNativeToolResult {
    let provider = AgentIOSURLSessionWebMediaToolProvider(transport: transport, sourceHealthStore: nil, nowMillis: { 1_000 })
    let registry = try AgentNativeToolRegistry().registerExecutables(AgentPhoneNativeToolCatalog.webMediaExecutableDefinitions(provider: provider))
    var input: AgentMcpJSONObject = ["url": .string(address)]
    if operation == .httpRequest { input["method"] = .string("GET") }
    return registry.invoke(operation.rawValue, input: input, context: .init(
      grantedPermissions: [AgentIOSWebMediaNativeToolCatalog.publicHttpsNetworkPermission],
      grantedConsents: [AgentIOSWebMediaNativeToolCatalog.publicWebConsent]), hooks: .init(nowMillis: { 1_000 }))
  }
}

private final class EncodedWebTransport: AgentIOSURLSessionWebTransporting {
  private(set) var requests: [AgentIOSURLSessionWebRequest] = []
  let locations: [String]
  init(locations: [String] = []) { self.locations = locations }
  func execute(_ request: AgentIOSURLSessionWebRequest) throws -> AgentIOSURLSessionWebResponse {
    let position = requests.count
    requests.append(request)
    if position < locations.count {
      return .init(statusCode: 302, finalURL: request.url, headers: ["location": locations[position]], body: Data(), retrievedAtEpochMillis: 1_000)
    }
    let html = "<html><title>Encoded page</title><main><p>Readable public content for a bounded stateless request.</p></main></html>"
    return .init(statusCode: 200, finalURL: request.url, headers: ["content-type": "text/html; charset=utf-8"],
      body: request.method == .head ? Data() : Data(html.utf8), retrievedAtEpochMillis: 1_000)
  }
}
