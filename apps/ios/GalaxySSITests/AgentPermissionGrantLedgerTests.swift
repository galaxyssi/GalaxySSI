import XCTest
@testable import GalaxySSI

final class AgentPermissionGrantLedgerTests: XCTestCase {
  func testAgentPermissionGrantLedgerConsumesSingleUseGrantExactlyOnce() throws {
    var now: Int64 = 1_000
    let store = InMemoryAgentPermissionGrantStore(nowMillis: { now })
    _ = try store.grant(permissionGrant(lifetime: .singleUse))

    XCTAssertTrue(try store.authorize(permissionRequest(), consume: true).granted)
    XCTAssertFalse(try store.authorize(permissionRequest(), consume: true).granted)
    XCTAssertEqual(store.list().first?.status, .consumed)
    XCTAssertEqual(store.list(includeInactive: false).count, 0)
    now = 1_100
    XCTAssertFalse(try store.authorize(permissionRequest(), consume: false).granted)
  }

  func testAgentPermissionGrantLedgerExpiresTemporaryGrantAtBoundary() throws {
    var now: Int64 = 1_000
    let store = InMemoryAgentPermissionGrantStore(nowMillis: { now })
    _ = try store.grant(permissionGrant(
      lifetime: .temporary,
      expiresAtMillis: 2_000,
      maxUses: 0
    ))

    XCTAssertTrue(try store.authorize(permissionRequest()).granted)
    now = 2_000
    XCTAssertFalse(try store.authorize(permissionRequest()).granted)
    XCTAssertEqual(store.list().first?.status, .expired)
  }

  func testAgentPermissionGrantLedgerEnforcesResourceAndTargetConstraints() throws {
    let store = InMemoryAgentPermissionGrantStore(nowMillis: { 1_000 })
    _ = try store.grant(permissionGrant(
      lifetime: .permanent,
      resource: "content://documents/report.pdf",
      target: "local-runtime",
      maxUses: 0
    ))

    XCTAssertTrue(try store.authorize(permissionRequest(
      resource: "content://documents/report.pdf",
      target: "local-runtime"
    )).granted)
    XCTAssertFalse(try store.authorize(permissionRequest(
      resource: "content://documents/private.pdf",
      target: "local-runtime"
    )).granted)
    XCTAssertFalse(try store.authorize(permissionRequest(
      resource: "content://documents/report.pdf",
      target: "cloud-runtime"
    )).granted)
  }

  func testAgentPermissionGrantLedgerRevocationAndSerializationSurviveRecreation() throws {
    let first = InMemoryAgentPermissionGrantStore(nowMillis: { 1_000 })
    let issued = try first.grant(permissionGrant(lifetime: .permanent, maxUses: 0))
    let recreated = InMemoryAgentPermissionGrantStore(
      serialized: first.serializedSnapshot(),
      nowMillis: { 1_500 }
    )
    let duplicate = try recreated.grant(permissionGrant(lifetime: .permanent, maxUses: 0))

    XCTAssertEqual(duplicate.grantId, issued.grantId)
    XCTAssertTrue(try recreated.authorize(permissionRequest()).granted)
    let revocation = recreated.revokeGrant(grantId: issued.grantId, reason: " user_revoked ")
    let afterRestart = InMemoryAgentPermissionGrantStore(
      serialized: recreated.serializedSnapshot(),
      nowMillis: { 2_000 }
    )

    XCTAssertEqual(revocation.revokedGrantIds, Set([issued.grantId]))
    XCTAssertEqual(revocation.scopes, Set(["location.foreground"]))
    XCTAssertEqual(revocation.reason, "user_revoked")
    XCTAssertFalse(try afterRestart.authorize(permissionRequest()).granted)
    XCTAssertEqual(afterRestart.list().first?.revocationReason, "user_revoked")
  }

  func testAgentPermissionGrantLedgerRejectsMalformedOrContradictoryGrants() throws {
    let store = InMemoryAgentPermissionGrantStore(nowMillis: { 1_000 })

    XCTAssertThrowsError(try store.grant(permissionGrant(
      lifetime: .temporary,
      expiresAtMillis: 999,
      maxUses: 0
    ))) { error in
      XCTAssertTrue(error is AgentPermissionGrantLedgerError)
    }
    XCTAssertThrowsError(try store.grant(permissionGrant(
      lifetime: .permanent,
      constraintsJson: "[]",
      maxUses: 0
    ))) { error in
      XCTAssertTrue(error is AgentPermissionGrantLedgerError)
    }
  }

  func testAgentPermissionGrantLedgerUsesMostSpecificActiveGrant() throws {
    let store = InMemoryAgentPermissionGrantStore(nowMillis: { 1_000 })
    _ = try store.grant(permissionGrant(
      grantId: "wildcard",
      lifetime: .permanent,
      subjectId: "*",
      scope: "*",
      action: "",
      maxUses: 0,
      createdAtMillis: 900
    ))
    _ = try store.grant(permissionGrant(
      grantId: "specific",
      lifetime: .permanent,
      resource: "content://documents/report.pdf",
      target: "local-runtime",
      maxUses: 0,
      createdAtMillis: 1_000
    ))

    let decision = try store.authorize(permissionRequest(
      resource: "content://documents/report.pdf",
      target: "local-runtime"
    ))

    XCTAssertTrue(decision.granted)
    XCTAssertEqual(decision.grant?.grantId, "specific")
    XCTAssertEqual(decision.reason, "host_grant_active")
  }

  func testAgentPermissionGrantLedgerModelsUseAndroidWireNames() throws {
    let decoded = try JSONDecoder.galaxySSI.decode(
      AgentPermissionGrant.self,
      from: Data(
        #"""
        {
          "grant_id": "grant-1",
          "subject_type": "TOOL",
          "subject_id": "android.location",
          "scope": "location.foreground",
          "action": "read",
          "resource": "content://documents/report.pdf",
          "target": "local-runtime",
          "constraints_json": "{\"allow\":\"once\"}",
          "issuer": "USER",
          "evidence": "approval-dialog:turn-1",
          "lifetime": "SINGLE_USE",
          "status": "ACTIVE",
          "max_uses": 1,
          "uses": 0,
          "created_at_millis": 1000,
          "expires_at_millis": 0,
          "consumed_at_millis": 0,
          "revoked_at_millis": 0,
          "revocation_reason": ""
        }
        """#.utf8
      )
    )
    let encoded = try JSONEncoder.galaxySSI.encode(decoded)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let serialized = AgentPermissionGrantJsonCodec.encode([decoded])
    let roundTripped = AgentPermissionGrantJsonCodec.decode(serialized)
    let fallbackSubject = try JSONDecoder.galaxySSI.decode(
      AgentPermissionSubjectType.self,
      from: Data(#""future""#.utf8)
    )

    XCTAssertEqual(decoded.grantId, "grant-1")
    XCTAssertEqual(decoded.subjectType, .tool)
    XCTAssertEqual(decoded.lifetime, .singleUse)
    XCTAssertEqual(object["grant_id"] as? String, "grant-1")
    XCTAssertEqual(object["subject_type"] as? String, "TOOL")
    XCTAssertEqual(object["constraints_json"] as? String, #"{"allow":"once"}"#)
    XCTAssertEqual(roundTripped.first?.grantId, "grant-1")
    XCTAssertEqual(fallbackSubject, .tool)
  }

  private func permissionGrant(
    grantId: String = "grant-location",
    lifetime: AgentPermissionGrantLifetime,
    subjectId: String = "android.location",
    scope: String = "location.foreground",
    action: String = "read",
    resource: String = "",
    target: String = "",
    constraintsJson: String = "{}",
    expiresAtMillis: Int64 = 0,
    maxUses: Int? = nil,
    createdAtMillis: Int64 = 1_000
  ) -> AgentPermissionGrant {
    AgentPermissionGrant(
      grantId: grantId,
      subjectType: .tool,
      subjectId: subjectId,
      scope: scope,
      action: action,
      resource: resource,
      target: target,
      constraintsJson: constraintsJson,
      issuer: .user,
      evidence: "approval-dialog:turn-1",
      lifetime: lifetime,
      maxUses: maxUses,
      createdAtMillis: createdAtMillis,
      expiresAtMillis: expiresAtMillis
    )
  }

  private func permissionRequest(
    subjectId: String = "android.location",
    scope: String = "location.foreground",
    action: String = "read",
    resource: String = "",
    target: String = ""
  ) -> AgentPermissionRequest {
    AgentPermissionRequest(
      subjectType: .tool,
      subjectId: subjectId,
      scope: scope,
      action: action,
      resource: resource,
      target: target
    )
  }
}
