import Foundation
import XCTest
@testable import GalaxySSI

final class GalaxySSIGlassesCloudConfigurationTests: XCTestCase {
  typealias Cloud = GalaxySSIGlassesCloudConfiguration

  func testCandidatePinsExactEndpointModelStyleAndCredential() throws {
    var draft = Cloud.Draft(agentName: "Fixture", endpoint: "https://example.test/v1/chat/completions",
      modelID: "fixture-model", key: "fixture-credential")
    let initial = try XCTUnwrap(draft.candidate)
    XCTAssertEqual(initial.fingerprint, draft.candidate?.fingerprint)
    draft.key = "second-fixture-credential"
    XCTAssertNotEqual(initial.fingerprint, draft.candidate?.fingerprint)
    draft.modelID = "new-model"
    XCTAssertNotEqual(initial.fingerprint, draft.candidate?.fingerprint)
    draft.style = .gemini
    draft.endpoint = "https://example.test/v1/models/other-model:generateContent"
    XCTAssertNil(draft.candidate)
    draft.endpoint = "https://example.test/v1/models/new-model:generateContent"
    XCTAssertNotNil(draft.candidate)
    draft.endpoint += "?secret=invalid"
    XCTAssertNil(draft.candidate)
  }

  func testProbeUsesOnlySyntheticPromptAndTheProviderSpecificResponse() async throws {
    let fixtures: [(GalaxySSICloudAPIStyle, String, String, String, String)] = [
      (.openAICompatible, "https://example.test/v1/chat/completions", "Authorization", "Bearer fixture-credential",
        #"{"choices":[{"message":{"content":"OK"}}]}"#),
      (.anthropic, "https://example.test/v1/messages", "x-api-key", "fixture-credential",
        #"{"content":[{"type":"text","text":"OK"}]}"#),
      (.gemini, "https://example.test/v1/models/fixture-model:generateContent", "x-goog-api-key", "fixture-credential",
        #"{"candidates":[{"content":{"parts":[{"text":"OK"}]}}]}"#)
    ]
    for (style, endpoint, header, expectedHeader, reply) in fixtures {
      let candidate = try XCTUnwrap(Cloud.Draft(agentName: "Private fixture", endpoint: endpoint,
        modelID: "fixture-model", key: "fixture-credential", style: style).candidate)
      try await Cloud.probe(candidate, send: { request in
        XCTAssertEqual(request.url?.absoluteString, endpoint)
        XCTAssertEqual(request.value(forHTTPHeaderField: header), expectedHeader)
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("Reply OK."))
        XCTAssertFalse(body.contains("fixture-credential"))
        XCTAssertFalse(body.contains("Private fixture"))
        return Data(reply.utf8)
      })
      for invalid in [Data(#"{"error":{"message":"Synthetic error"}}"#.utf8), Data(repeating: 32, count: 32_769)] {
        do {
          try await Cloud.probe(candidate, send: { _ in invalid })
          XCTFail("Invalid provider result must not pass the connection test.")
        } catch {}
      }
    }
  }
}
