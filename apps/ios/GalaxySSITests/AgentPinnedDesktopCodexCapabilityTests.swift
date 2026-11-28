import XCTest
@testable import GalaxySSI

@MainActor
final class AgentPinnedDesktopCodexCapabilityTests: XCTestCase {
  private let marker = AgentPinnedDesktopCodexCapability.id

  func testOnlyAnExactTopLevelArrayAdvertisesTheCapability() {
    XCTAssertTrue(AgentPinnedDesktopCodexCapability.advertised(["capabilities": [marker]]))
    let payloads: [[String: Any]] = [
      ["capabilities": marker], ["capabilities": [" " + marker]],
      ["adapter": ["capabilities": [marker]]], [marker: true], ["capabilities": [true, 1]]
    ]
    for payload in payloads { XCTAssertFalse(AgentPinnedDesktopCodexCapability.advertised(payload)) }
  }

  func testCompactMarkerIsNotAnAuthoritativeEmptyInventory() {
    XCTAssertTrue(AgentPinnedDesktopCodexCapability.compact(["capabilities": [marker]]))
    XCTAssertNil(AgentPinnedDesktopCodexCapability.inventory(["capabilities": [marker]]))
    XCTAssertTrue(AgentPinnedDesktopCodexCapability.compact(["capabilities": [marker], "adapter": NSNull()]))
    XCTAssertEqual(AgentPinnedDesktopCodexCapability.inventory(["capabilities": [String]()])?.capabilities, [])
    let detailed: [String: Any] = ["capabilities": [marker], "adapter": [String: Any]()]
    XCTAssertFalse(AgentPinnedDesktopCodexCapability.compact(detailed))
    XCTAssertEqual(AgentPinnedDesktopCodexCapability.inventory(detailed)?.capabilities, [])
  }

  func testMarkerIsRemovedFromRoutingRatherThanBecomingAnAgentAbility() throws {
    let inventory = try XCTUnwrap(AgentPinnedDesktopCodexCapability.inventory(["capabilities": [marker, "reasoning", "code_generation"]]))
    XCTAssertEqual(inventory.capabilities, ["reasoning", "code_generation"])
    XCTAssertTrue(inventory.markerRemoved)
    let adapter: [String: Any] = ["adapter": ["capabilities": [marker, "reasoning"]]]
    XCTAssertFalse(AgentPinnedDesktopCodexCapability.advertised(adapter))
    XCTAssertEqual(AgentPinnedDesktopCodexCapability.inventory(adapter)?.capabilities, ["reasoning"])
  }

  func testParentMetadataCannotPromoteTheMarker() {
    XCTAssertNil(AgentPinnedDesktopCodexCapability.inheritedCapabilities([marker]))
    XCTAssertEqual(AgentPinnedDesktopCodexCapability.inheritedCapabilities([marker, "reasoning"]) as? [String], ["reasoning"])
    XCTAssertEqual(AgentPinnedDesktopCodexCapability.inheritedCapabilities(["reasoning"]) as? [String], ["reasoning"])
  }

  func testActualStoreKeepsSameDesktopRoutingAndModelMetadataOnCompactStatus() throws {
    try withStore { store, link in
      self.update(store, link: link, capabilities: ["reasoning", "code_generation"], extra: self.fullMetadata())
      let before = try XCTUnwrap(store.contact(id: link.desktopId + ":codex"))
      self.update(store, link: link, capabilities: [self.marker])
      let after = try XCTUnwrap(store.contact(id: before.id))
      XCTAssertEqual(after.pinned_team_codex_v1, true)
      XCTAssertEqual(after.connectorCapabilities, before.connectorCapabilities)
      XCTAssertEqual(after.connectorCapabilitiesHash, before.connectorCapabilitiesHash)
      XCTAssertEqual(after.connectorProtocols, before.connectorProtocols)
      XCTAssertEqual(after.connectorProtocolFeatures, before.connectorProtocolFeatures)
      XCTAssertEqual(after.connectorAdapterType, before.connectorAdapterType)
      XCTAssertEqual(after.connectorProviderProfileJSON, before.connectorProviderProfileJSON)
      XCTAssertEqual(after.connectorInvocationProfileJSON, before.connectorInvocationProfileJSON)
    }
  }

  func testFullAdvertisementUpdatesTheCleanRoutingInventoryAndHash() throws {
    try withStore { store, link in
      self.update(store, link: link, capabilities: ["reasoning"], extra: ["capabilities_hash": "old-hash"])
      self.update(store, link: link, capabilities: [self.marker, "reasoning", "code_generation"],
        extra: ["capabilities_hash": "hash-containing-the-marker"])
      let contact = try XCTUnwrap(store.contact(id: link.desktopId + ":codex"))
      XCTAssertEqual(contact.pinned_team_codex_v1, true)
      XCTAssertEqual(contact.connectorCapabilities, ["reasoning", "code_generation"])
      XCTAssertNotEqual(contact.connectorCapabilitiesHash, "old-hash")
      XCTAssertNotEqual(contact.connectorCapabilitiesHash, "hash-containing-the-marker")
    }
  }

  func testAFullSnapshotWithoutTheMarkerRevokesStoredSupport() throws {
    try withStore { store, link in
      self.update(store, link: link, capabilities: [self.marker])
      XCTAssertEqual(store.contact(id: link.desktopId + ":codex")?.pinned_team_codex_v1, true)
      self.update(store, link: link, capabilities: ["reasoning"])
      XCTAssertNil(store.contact(id: link.desktopId + ":codex")?.pinned_team_codex_v1)
    }
  }

  func testOtherAgentsCannotBorrowTheCodexMarker() throws {
    try withStore { store, link in
      self.update(store, link: link, capabilities: [self.marker], agentID: "claude")
      XCTAssertNil(store.contact(id: link.desktopId + ":claude")?.pinned_team_codex_v1)
    }
  }

  func testUnpairedAdvertisementsCannotSetStoredSupport() throws {
    try withStore(paired: false) { store, link in
      self.update(store, link: link, capabilities: [self.marker])
      XCTAssertNil(store.contact(id: link.desktopId + ":codex")?.pinned_team_codex_v1)
    }
  }

  func testChangedFingerprintCannotRetainAnOldModelInventory() throws {
    try withStore { store, link in
      self.update(store, link: link, capabilities: ["reasoning"], extra: self.fullMetadata())
      self.update(store, link: link, capabilities: [self.marker], parent: ["desktop_fingerprint": String(repeating: "b", count: 64)])
      let contact = try XCTUnwrap(store.contact(id: link.desktopId + ":codex"))
      XCTAssertNil(contact.pinned_team_codex_v1)
      XCTAssertNil(contact.connectorCapabilities)
      XCTAssertNil(contact.connectorAdapterType)
      XCTAssertNil(contact.connectorInvocationProfileJSON)
    }
  }

  func testCompactAgentCannotBorrowTheParentModelOrAdapter() throws {
    try withStore { store, link in
      self.update(store, link: link, capabilities: ["reasoning"], extra: self.fullMetadata())
      let before = try XCTUnwrap(store.contact(id: link.desktopId + ":codex"))
      self.update(store, link: link, capabilities: [self.marker], parent: [
        "adapter": ["type": "unrelated-adapter"],
        "provider_profile": ["provider": "unrelated"],
        "invocation_profile": ["models": ["unrelated-model"]]
      ])
      let after = try XCTUnwrap(store.contact(id: before.id))
      XCTAssertEqual(after.connectorAdapterType, before.connectorAdapterType)
      XCTAssertEqual(after.connectorProviderProfileJSON, before.connectorProviderProfileJSON)
      XCTAssertEqual(after.connectorInvocationProfileJSON, before.connectorInvocationProfileJSON)
      self.update(store, link: link, capabilities: nil, parent: ["capabilities": [self.marker]])
      XCTAssertNil(store.contact(id: before.id)?.pinned_team_codex_v1)
    }
  }

  func testStoredCapabilityUsesTheWireKeyAndRemainsOptionalForOldContacts() throws {
    var contact = GalaxySSIContact.system()
    let legacy = try JSONDecoder().decode(GalaxySSIContact.self, from: JSONEncoder().encode(contact))
    XCTAssertNil(legacy.pinned_team_codex_v1)
    contact.pinned_team_codex_v1 = true
    let data = try JSONEncoder().encode(contact)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(object[marker] as? Bool, true)
    XCTAssertEqual(try JSONDecoder().decode(GalaxySSIContact.self, from: data).pinned_team_codex_v1, true)
  }

  private func fullMetadata() -> [String: Any] {
    ["adapter": ["type": "codex-app-server-or-cli"], "protocols": ["agent_conversation"],
      "protocol_features": ["streaming"], "provider_profile": ["provider": "codex"],
      "invocation_profile": ["models": ["synthetic-model"], "default_model": "synthetic-model", "reasoning_efforts": ["high"]]]
  }

  private func update(_ store: GalaxySSIStore, link: ServerLink, capabilities: [String]?,
                      extra: [String: Any] = [:], parent: [String: Any] = [:], agentID: String = "codex") {
    var agent: [String: Any] = ["id": agentID, "agent_id": agentID, "kind": "local-cli", "status": "ready"]
    if let capabilities { agent["capabilities"] = capabilities }
    extra.forEach { agent[$0.key] = $0.value }
    var payload: [String: Any] = ["type": "capability_manifest", "desktop_id": link.desktopId,
      "desktop_fingerprint": link.desktopFingerprint, "agents": [agent]]
    parent.forEach { payload[$0.key] = $0.value }
    XCTAssertEqual(store.updateDesktopAgentContacts(from: payload, link: link), 1)
  }

  private func withStore(paired: Bool = true, _ work: (GalaxySSIStore, ServerLink) throws -> Void) throws {
    let domain = "PinnedDesktopCapability-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let store = GalaxySSIStore(defaults: defaults, secrets: InMemorySecretStore())
    let payload: [String: Any] = ["t": "o2", "n": "Synthetic Desktop", "h": String(repeating: "a", count: 64),
      "k": Data(repeating: 1, count: 32).base64URLEncodedString(), "x": String(repeating: "t", count: 43),
      "e": Data(repeating: 7, count: 32).base64URLEncodedString(), "a": 0, "c": Int64(Date().timeIntervalSince1970)]
    let text = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
    let pairing = try GalaxySSILinkProtocol.decodePairingQRCode(from: text)
    let initial = try store.addServerLink(from: pairing, rotateClientRoute: false)
    if paired { store.markServerPaired(desktopId: initial.desktopId, access: pairing.access) }
    let link = try XCTUnwrap(store.serverLinks.first { $0.desktopId == initial.desktopId })
    try work(store, link)
  }
}
