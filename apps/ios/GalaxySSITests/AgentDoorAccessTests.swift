import Foundation
import XCTest
@testable import GalaxySSI

final class AgentDoorAccessTests: XCTestCase {
  func testOnlyEnabledVerifiedPackageProvidesExactLocalAliases() throws {
    let store = InMemoryAgentSkillStore()
    let runtime = AgentSkillRuntime(store: store, availableNativeToolIds: [])
    let installer = AgentSkillPackageInstaller(runtime)
    let manifest = fixture()
    XCTAssertThrowsError(try runtime.install(manifest))
    XCTAssertTrue(runtime.installAvailable([manifest]).isEmpty)
    let package = AgentSkillPackageExporter.export(manifest)
    XCTAssertFalse(try installer.install(package).enabled)
    XCTAssertNil(AgentDoorAccessConfiguration.enabled(in: store, automatic: true))
    _ = try runtime.enable(id: manifest.id, version: manifest.version)
    let config = try XCTUnwrap(AgentDoorAccessConfiguration.enabled(in: store, automatic: true))
    XCTAssertEqual(config.command(" List doors. "), .list)
    XCTAssertEqual(config.command("OPEN the door!"), .open("fixture"))
    XCTAssertNil(config.command("Explain how to open the door"))
    XCTAssertNil(config.command("Open the door tomorrow"))
    XCTAssertThrowsError(try runtime.expand(id: manifest.id, version: manifest.version))
    _ = try runtime.disable(id: manifest.id, version: manifest.version)
    XCTAssertNil(AgentDoorAccessConfiguration.enabled(in: store))
    XCTAssertNil(AgentDoorAccessConfiguration(fixture(listAlias: "Open the door.")))
  }

  func testListDoesNotPublishAndUncertainUnlockIsNeverRetried() async throws {
    var calls: [URLRequest] = []
    let client = AgentDoorAccessClient(send: { request in
      calls.append(request)
      switch request.url?.path {
      case "/MobileApi/House/Login":
        return Data(#"{"State":true,"Data":{"Token":"test+token","House":{"ID":"user"}}}"#.utf8)
      case "/GuestApi/PrivateCloud/GetSubSystems":
        return Data(#"{"State":true,"Data":[{"SubSystem":1,"SubSystemHost":"http://fixture.taichuan.net:80/"}]}"#.utf8)
      case "/Api/MobileApi/Index/SearchEquipment":
        return Data(#"{"State":true,"Data":[{"EQ_Name":"Fixture Door","EQ_Num":"channel"}]}"#.utf8)
      case "/MobileApi/Publisher/Publish":
        throw AgentDoorAccessClient.Failure.unavailable
      default:
        XCTFail("Unexpected endpoint")
        throw AgentDoorAccessClient.Failure.invalid
      }
    })
    let session = try await client.login(.init(account: "fixture account", password: "fixture&password"))
    let doors = try await client.list(session)
    XCTAssertEqual(calls.count, 3)
    XCTAssertEqual(calls.last?.url?.scheme, "https")
    XCTAssertEqual(calls.last?.url?.host, "fixture.taichuan.net")
    XCTAssertTrue(calls.last?.url?.absoluteString.contains("test%2Btoken") == true)
    let target = try XCTUnwrap(AgentDoorAccessConfiguration(fixture())?.targets.first)
    let door = try XCTUnwrap(AgentDoorAccessClient.uniqueDoor(target, in: doors))
    XCTAssertNil(AgentDoorAccessClient.uniqueDoor(target, in: doors + doors))
    switch await client.open(session, door: door, millis: 1_000) {
    case .unconfirmed: break
    default: XCTFail("A lost response is not a rejection or acceptance.")
    }
    XCTAssertEqual(calls.count, 4)
    XCTAssertEqual(calls.last?.httpMethod, "POST")
    XCTAssertTrue(calls.last?.httpBody.flatMap { String(data: $0, encoding: .utf8) }?.contains("channel=channel") == true)
    for unsafe in ["https://taichuan.net.evil.test", "https://user@fixture.taichuan.net", "https://fixture.taichuan.net:8080",
                   "https://fixture.taichuan.net/redirect", "https://fixture.taichuan.net/?query=1"] {
      XCTAssertNil(AgentDoorAccessClient.secureServiceURL(unsafe))
    }
  }

  private func fixture(listAlias: String = "List doors") -> AgentSkillManifest {
    let configuration: AgentMcpJSONObject = ["version": .int(1), "default_door": .string("fixture"),
      "default_open_commands": .array([.string("Open the door")]), "list_commands": .array([.string(listAlias)]),
      "doors": .array([.object(["id": .string("fixture"), "service_name": .string("Fixture Door"),
        "display_name": .string("Fixture"), "commands": .array([.string("Open fixture")])])]]
    return .init(id: AgentDoorAccessConfiguration.skillID, name: "Synthetic Door", version: "1.3.0",
      summary: "Fixture only", nativeTools: [AgentDoorAccessConfiguration.toolID],
      steps: [.init(id: "open_panel", toolId: AgentDoorAccessConfiguration.toolID,
        input: ["door_config": .object(configuration)])], source: "third_party", autoInvoke: true)
  }
}
