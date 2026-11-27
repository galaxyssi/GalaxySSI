import XCTest
@testable import GalaxySSI

final class AgentTeamWriterFormatSessionTests: XCTestCase {
  private let endpoint = "http://127.0.0.1:8080/v1/chat/completions"
  private func format(_ session: AgentTeamWriterFormatSession, stage: String = "synthesis") -> AgentMcpJSONObject? {
    session.format(system: AgentTeamPredictionContrast.writer, endpoint: endpoint, stage: stage)
  }
  private func schema(_ session: AgentTeamWriterFormatSession, stage: String) throws -> [String: Any] {
    let value = try XCTUnwrap(format(session, stage: stage))
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    return try XCTUnwrap((object["json_schema"] as? [String: Any])?["schema"] as? [String: Any])
  }
  func testCapabilityRequiresExplicitProductAndIsRunLocal() {
    let session = AgentTeamWriterFormatSession()
    XCTAssertNil(format(session))
    for product in ["llama.cpp", "LLAMA.CPP", " llama.cpp/b1234 ", "llama.cpp/1.2.3-dev"] {
      session.observe(endpoint: endpoint, responseURL: endpoint, server: product)
      XCTAssertNotNil(format(session))
      XCTAssertNil(format(AgentTeamWriterFormatSession()))
    }
    for product in [nil, "", "nginx", "not-llama.cpp", "llama.cpp-proxy", "llama.cpp/", "llama.cpp/1.2 proxy", "nginx, llama.cpp", String(repeating: "x", count: 129)] as [String?] {
      session.observe(endpoint: endpoint, responseURL: endpoint, server: "llama.cpp")
      session.observe(endpoint: endpoint, responseURL: endpoint, server: product)
      XCTAssertNil(format(session))
    }
  }
  func testCanonicalOriginAndExactEndpointMustMatch() {
    let session = AgentTeamWriterFormatSession()
    for other in ["http://localhost:8080/v1/chat/completions", "https://example.invalid/v1/chat/completions",
      "http://127.0.0.1:8081/v1/chat/completions", "https://127.0.0.1:8080/v1/chat/completions",
      endpoint + "?x=1", endpoint + "#x", endpoint + "/", "http://user@127.0.0.1:8080/v1/chat/completions",
      "http://127.0.0.1:0/v1/chat/completions", "http://127.0.0.1:/v1/chat/completions"] {
      session.observe(endpoint: endpoint, responseURL: other, server: "llama.cpp")
      XCTAssertNil(format(session), other)
      session.observe(endpoint: other, responseURL: endpoint, server: "llama.cpp")
      XCTAssertNil(format(session), other)
    }
    let ipv6 = "https://[::1]:8080/v1/chat/completions"
    session.observe(endpoint: ipv6, responseURL: ipv6, server: "llama.cpp")
    XCTAssertNotNil(session.format(system: AgentTeamPredictionContrast.writer, endpoint: ipv6, stage: "rewrite"))
    let implicit = "http://127.0.0.1/v1/chat/completions"
    session.observe(endpoint: implicit, responseURL: "http://127.0.0.1:80/v1/chat/completions", server: "llama.cpp")
    XCTAssertNil(session.format(system: AgentTeamPredictionContrast.writer, endpoint: implicit, stage: "rewrite"))
  }
  func testOnlyExactWriterAndTwoStagesCanUseCapability() {
    let session = AgentTeamWriterFormatSession()
    session.observe(endpoint: endpoint, responseURL: endpoint, server: "llama.cpp")
    for stage in ["plan", "role", "audit", "recheck", "Synthesis", "rewrite "] { XCTAssertNil(format(session, stage: stage)) }
    for system in [AgentTeamPredictionContrast.auditor, AgentTeamPredictionContrast.writer + " ", "ordinary writer"] {
      XCTAssertNil(session.format(system: system, endpoint: endpoint, stage: "synthesis"))
    }
    XCTAssertNotNil(format(session, stage: "rewrite"))
  }
  func testSchemaConstrainsDirectionsNotScientificContent() throws {
    let session = AgentTeamWriterFormatSession()
    session.observe(endpoint: endpoint, responseURL: endpoint, server: "llama.cpp")
    let rewrite = try schema(session, stage: "rewrite")
    XCTAssertNil(rewrite["anyOf"])
    let fields = ["purpose", "input", "input_direction", "readout", "expected_direction", "alternative", "gap"]
    let properties = try XCTUnwrap(rewrite["properties"] as? [String: [String: Any]])
    XCTAssertEqual(Set(properties.keys), Set(fields))
    XCTAssertEqual(Set(try XCTUnwrap(rewrite["required"] as? [String])), Set(fields))
    XCTAssertEqual(rewrite["additionalProperties"] as? Bool, false)
    for key in fields {
      XCTAssertEqual(properties[key]?["type"] as? String, "string")
      if key.hasSuffix("_direction") { XCTAssertEqual(properties[key]?["enum"] as? [String], ["higher", "lower"]) }
      else { XCTAssertEqual(properties[key]?.count, 1) }
    }
    let choices = try XCTUnwrap(try schema(session, stage: "synthesis")["anyOf"] as? [[String: Any]])
    XCTAssertEqual(choices.count, 2)
    XCTAssertTrue(NSDictionary(dictionary: choices[0]).isEqual(to: rewrite))
    XCTAssertEqual(Set(try XCTUnwrap(choices[1]["properties"] as? [String: Any]).keys), ["answer"])
  }
  func testRequestPreservesRouteHeadersAndPayloadOutsideFormat() throws {
    let session = AgentTeamWriterFormatSession()
    let request = ModelStreamRequest(requestId: "synthetic-writer", provider: .openAICompatible, endpoint: endpoint,
      headers: ["X-Fixture": "synthetic"], bodyJson: #"{"model":"fixture","messages":[],"stream":true,"store":false}"#)
    XCTAssertEqual(try session.apply(to: request, system: AgentTeamPredictionContrast.writer, stage: "rewrite"), request)
    session.observe(endpoint: endpoint, responseURL: endpoint, server: "llama.cpp")
    var result = try session.apply(to: request, system: AgentTeamPredictionContrast.writer, stage: "rewrite")
    var body = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(result.bodyJson.utf8)) as? [String: Any])
    XCTAssertNotNil(body.removeValue(forKey: "response_format"))
    XCTAssertTrue(NSDictionary(dictionary: body).isEqual(to: try XCTUnwrap(JSONSerialization.jsonObject(with: Data(request.bodyJson.utf8)) as? [String: Any])))
    result.bodyJson = request.bodyJson
    XCTAssertEqual(result, request)
    var foreign = request; foreign.provider = .anthropic
    XCTAssertEqual(try session.apply(to: foreign, system: AgentTeamPredictionContrast.writer, stage: "rewrite"), foreign)
    XCTAssertEqual(try session.apply(to: request, system: AgentTeamPredictionContrast.writer, stage: "audit"), request)
    var malformed = request; malformed.bodyJson = "[]"
    XCTAssertThrowsError(try session.apply(to: malformed, system: AgentTeamPredictionContrast.writer, stage: "rewrite"))
  }
  func testOnlySuccessfulNonRedirectedResponseAdvertises() throws {
    let observer = CloudTextServerObservation()
    let url = try XCTUnwrap(URL(string: endpoint))
    for status in [200, 204, 299] {
      let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Server": "llama.cpp"]))
      XCTAssertEqual(observer.advertisement(response: response), .init(responseURL: endpoint, server: "llama.cpp"))
    }
    for status in [301, 400, 500] {
      XCTAssertNil(observer.advertisement(response: try XCTUnwrap(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))))
    }
    let session = URLSession(configuration: .ephemeral)
    defer { session.invalidateAndCancel() }
    let request = URLRequest(url: url), task = session.dataTask(with: url)
    let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Server": "llama.cpp"]))
    observer.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: request) {
      XCTAssertEqual($0, request)
    }
    XCTAssertNil(observer.advertisement(response: response))
  }
}
