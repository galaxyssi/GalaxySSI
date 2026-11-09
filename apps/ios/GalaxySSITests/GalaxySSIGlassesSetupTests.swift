import Foundation
import XCTest
@testable import GalaxySSI

final class GalaxySSIGlassesSetupTests: XCTestCase {
  typealias Wire = GalaxySSIGlassesSetupProtocol

  func testPairingVectorAndTransferRequireBothConfirmations() throws {
    let nonce = Data(repeating: 1, count: 32), peer = Data(repeating: 2, count: 32)
    let credential = "synthetic-fixture-key"
    let profile = try Wire.Profile(agentName: "Fixture", model: model(), key: credential)
    var client = try Wire.Handshake(nonce: nonce)
    XCTAssertThrowsError(try client.transfer(profile))
    XCTAssertEqual(try client.hello()["commitment"], .string(Wire.Handshake.digest(nonce)))
    let challenge: AgentMcpJSONObject = ["type": .string("challenge"), "version": .int(1),
      "commitment": .string(Wire.Handshake.digest(peer))]
    XCTAssertFalse(AgentMcpJSONCodec.stringify(try client.reveal(after: challenge)).contains(credential))
    XCTAssertThrowsError(try client.compare(reveal: ["type": .string("reveal"),
      "nonce": .string(String(repeating: "03", count: 32))], certificate: Data("test cert".utf8)))
    XCTAssertEqual(try client.compare(reveal: ["type": .string("reveal"),
      "nonce": .string(String(repeating: "02", count: 32))], certificate: Data("test cert".utf8)), "189296")
    XCTAssertThrowsError(try client.acceptReady(["type": .string("ready")]))
    XCTAssertThrowsError(try client.transfer(profile))
    XCTAssertEqual(try client.confirm(), ["type": .string("confirm"), "accept": .bool(true)])
    XCTAssertThrowsError(try client.transfer(profile))
    try client.acceptReady(["type": .string("ready")])
    let payload = try client.transfer(profile)
    XCTAssertEqual(payload["kind"], .string("cloud"))
    XCTAssertEqual(payload["profile"]?.objectValue?["api_key"], .string(credential))
    XCTAssertEqual(payload["agent_name"], .string("Fixture"))
    XCTAssertThrowsError(try client.transfer(profile))
  }

  @MainActor func testRejectsOutOfBoundsFramesUnsafeAddressesAndProviderURLs() throws {
    let frame = try Wire.frame(["type": .string("ready")])
    XCTAssertEqual(try Wire.frameLength(Data(frame.prefix(4))), frame.count - 4)
    XCTAssertThrowsError(try Wire.frameLength(Data([0, 0, 0, 1])))
    XCTAssertThrowsError(try Wire.frameLength(Data([0, 0, 128, 1])))
    XCTAssertThrowsError(try Wire.frameLength(Data([0, 0, 1])))
    XCTAssertNotNil(GalaxySSIGlassesSetupConnection.manualEndpoint(host: "192.168.1.4", port: "8080"))
    for host in ["127.0.0.1", "8.8.8.8", "10.0.0.256", "example.test", "::1"] {
      XCTAssertNil(GalaxySSIGlassesSetupConnection.manualEndpoint(host: host, port: "8080"))
    }
    XCTAssertNil(GalaxySSIGlassesSetupConnection.manualEndpoint(host: "192.168.1.4", port: "0"))
    for endpoint in ["http://example.test/v1/chat/completions", "https://example.test/v1/messages",
                     "https://example.test/v1/chat/completions?key=secret", "https://name@example.test/v1/chat/completions"] {
      XCTAssertThrowsError(try Wire.Profile(agentName: "Fixture", model: model(endpoint), key: "fixture"))
    }
  }

  private func model(_ endpoint: String = "https://example.test/v1/chat/completions") -> CloudModelConfig {
    .init(id: "fixture", displayName: "Fixture", provider: "Custom", modelId: "fixture-model",
      endpoint: endpoint, apiStyle: .openAICompatible, keychainAccount: "", updatedAt: Date(timeIntervalSince1970: 1))
  }
}
