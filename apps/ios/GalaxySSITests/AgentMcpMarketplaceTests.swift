import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
  func testAgentCapabilityCatalogIdsAreStableAndUnique() {
    let mcp = AgentDefaultCapabilityCatalog.mcpEntries
    let skills = AgentDefaultCapabilityCatalog.skillEntries

    XCTAssertGreaterThanOrEqual(mcp.count, 4)
    XCTAssertGreaterThanOrEqual(skills.count, 5)
    XCTAssertEqual(Set(mcp.map(\.id)).count, mcp.count)
    XCTAssertEqual(Set(skills.map(\.id)).count, skills.count)
    XCTAssertTrue(mcp.contains { $0.requiresPackage })
    XCTAssertTrue(skills.contains { !$0.requiredMcpCatalogIds.isEmpty })
  }

  func testAgentCapabilityCatalogMarketplaceUnifiesToolsMcpAndAutomationState() throws {
    let nativeTool = try nativeToolDescriptor(
      AgentMcpNativeTools.callTool,
      risk: .medium,
      capabilities: ["mcp.call"],
      requiredConsents: [
        AgentNativeConsentRequirement(id: "mcp.call.once", title: "MCP call")
      ]
    )
    let registry = AgentMcpRegistry(InMemoryAgentMcpStore(), nowMillis: { 1_000 })

    let initial = AgentDefaultCapabilityCatalog.marketplaceItems(
      nativeTools: [nativeTool],
      installedMcp: registry.list(),
      installedAutomations: [],
      nowMillis: 1_000
    )

    XCTAssertEqual(initial.first { $0.id == AgentMcpNativeTools.callTool }?.installState, .builtIn)
    let github = try XCTUnwrap(initial.first { $0.id == "galaxyssi.mcp.github" })
    XCTAssertEqual(github.installState, .available)
    XCTAssertTrue(github.permissionDiff.requiresApproval)
    XCTAssertTrue(github.capabilities.contains("github.repositories"))
    XCTAssertEqual(initial.first { $0.id == "galaxyssi.catalog.github-triage" }?.installState, .needsSetup)

    _ = try registry.addRemote(
      displayName: "GitHub",
      endpoint: "https://api.githubcopilot.com/mcp/",
      authProfile: try AgentMcpAuthProfile(.none),
      catalogId: "galaxyssi.mcp.github",
      id: "github"
    )
    let ready = AgentDefaultCapabilityCatalog.marketplaceItems(
      nativeTools: [nativeTool],
      installedMcp: registry.list(),
      installedAutomations: [],
      nowMillis: 1_000
    )

    XCTAssertEqual(ready.first { $0.id == "galaxyssi.mcp.github" }?.installState, .installed)
    XCTAssertTrue(ready.first { $0.id == "galaxyssi.mcp.github" }?.revocable == true)
    XCTAssertFalse(ready.first { $0.id == "galaxyssi.mcp.github" }?.permissionDiff.requiresApproval ?? true)
    XCTAssertEqual(ready.first { $0.id == "galaxyssi.catalog.github-triage" }?.installState, .available)
  }

  func testAgentCapabilityCatalogReportsAutomationRollbackAndPermissionChanges() {
    let entry = AgentDefaultCapabilityCatalog.skill("galaxyssi.catalog.device-health")!
    var previousManifest = entry.manifest
    previousManifest.version = "0.9.0"
    previousManifest.permissions = []
    previousManifest.nativeTools.remove("galaxyssi.hardware.network.status")
    let previous = AgentSkillInstallation(manifest: previousManifest, enabled: false)
    let current = AgentSkillInstallation(manifest: entry.manifest, enabled: true)

    let item = AgentDefaultCapabilityCatalog.marketplaceItems(
      nativeTools: [],
      installedMcp: [],
      installedAutomations: [previous, current],
      nowMillis: 1_000
    ).first { $0.id == entry.id }

    XCTAssertEqual(item?.installedVersion, "1.0.0")
    XCTAssertEqual(item?.rollbackVersions, ["0.9.0"])
    XCTAssertTrue(item?.revocable == true)
    XCTAssertFalse(item?.permissionDiff.requiresApproval ?? true)
  }

  func testAgentDesktopMarketplaceStoreProjectsPairedDesktopManifests() throws {
    let store = AgentDesktopMarketplaceStore()
    let longText = String(repeating: "s", count: 520)
    let longCapability = String(repeating: "c", count: 180)
    let rollbackVersions = (0..<10).map { AgentMcpJSONValue.string("0.\($0).0") }
    let updated = store.update(payload: [
      "type": .string("capability_manifest"),
      "server": .object([
        "id": .string(" desktop-1 "),
        "name": .string("Office PC")
      ]),
      "tool_marketplace": .object([
        "items": .array([
          .object([
            "id": .string(String(repeating: "m", count: 540)),
            "kind": .string(AgentCapabilityCatalogKind.mcp.rawValue),
            "name": .string("GitHub MCP"),
            "summary": .string(longText),
            "version": .string(""),
            "install_state": .string(AgentMarketplaceInstallState.installed.rawValue),
            "enabled": .bool(true),
            "capabilities": .array([
              .string(" repositories "),
              .string(""),
              .string(longCapability)
            ]),
            "permissions": .array([
              .object(["id": .string("   ")]),
              .object([
                "id": .string(" repo.read "),
                "title": .string(""),
                "description": .string(longText)
              ])
            ]),
            "permission_diff": .object([
              "added": .array([
                .object([
                  "id": .string("repo.write"),
                  "title": .string("Write repositories"),
                  "scope": .string("catalog"),
                  "risk": .string("high")
                ])
              ]),
              "removed": .array([]),
              "unchanged": .array([
                .object(["id": .string("repo.read")])
              ])
            ]),
            "installed_version": .string("0.9.0"),
            "available_version": .string(""),
            "update_available": .bool(true),
            "rollback_versions": .array(rollbackVersions),
            "revocable": .bool(true),
            "revoked": .bool(false)
          ]),
          .object([
            "id": .string("desktop-native"),
            "kind": .string(AgentCapabilityCatalogKind.nativeTool.rawValue),
            "name": .string("Desktop Terminal"),
            "summary": .string("Run workspace commands"),
            "version": .string("1.2.0"),
            "install_state": .string(AgentMarketplaceInstallState.builtIn.rawValue),
            "trusted": .bool(false)
          ]),
          .object([
            "id": .string("bad-kind"),
            "kind": .string("not-supported"),
            "install_state": .string(AgentMarketplaceInstallState.available.rawValue)
          ]),
          .object([
            "id": .string("bad-state"),
            "kind": .string(AgentCapabilityCatalogKind.automation.rawValue),
            "install_state": .string("not-supported")
          ])
        ])
      ])
    ], nowMillis: 1_800_000_000_000)

    XCTAssertTrue(updated)
    XCTAssertFalse(store.update(payload: ["type": .string("not_capability_manifest")], nowMillis: 2_000))
    XCTAssertTrue(store.list(
      pairedDesktopIds: ["desktop-1"],
      desktopSessionDesktopIds: []
    ).isEmpty)

    let all = store.list(
      pairedDesktopIds: ["desktop-1", "other-desktop"],
      desktopSessionDesktopIds: ["desktop-1"]
    )
    let mcp = try XCTUnwrap(store.list(
      selectedKind: .mcp,
      pairedDesktopIds: ["desktop-1"],
      desktopSessionDesktopIds: ["desktop-1"]
    ).first)
    let native = try XCTUnwrap(all.first { $0.id == "desktop-native" })

    XCTAssertEqual(all.count, 2)
    XCTAssertEqual(mcp.desktopId, "desktop-1")
    XCTAssertEqual(mcp.desktopName, "Office PC")
    XCTAssertEqual(mcp.id.count, 500)
    XCTAssertEqual(mcp.summary.count, 500)
    XCTAssertEqual(mcp.version, "1.0.0")
    XCTAssertEqual(mcp.installedVersion, "0.9.0")
    XCTAssertEqual(mcp.availableVersion, "1.0.0")
    XCTAssertEqual(mcp.installState, .installed)
    XCTAssertTrue(mcp.enabled)
    XCTAssertTrue(mcp.trusted)
    XCTAssertTrue(mcp.updateAvailable)
    XCTAssertEqual(mcp.capabilities.count, 2)
    XCTAssertTrue(mcp.capabilities.contains("repositories"))
    XCTAssertTrue(mcp.capabilities.contains(String(repeating: "c", count: 160)))
    XCTAssertEqual(mcp.permissions.count, 1)
    XCTAssertEqual(mcp.permissions.first?.id, "repo.read")
    XCTAssertEqual(mcp.permissions.first?.title, "repo.read")
    XCTAssertEqual(mcp.permissions.first?.description.count, 500)
    XCTAssertEqual(mcp.permissionDiff.added.first?.id, "repo.write")
    XCTAssertEqual(mcp.permissionDiff.added.first?.scope, "catalog")
    XCTAssertEqual(mcp.permissionDiff.added.first?.risk, "high")
    XCTAssertEqual(mcp.permissionDiff.unchanged.first?.title, "repo.read")
    XCTAssertEqual(mcp.rollbackVersions.count, 8)
    XCTAssertTrue(mcp.revocable)
    XCTAssertFalse(mcp.revoked)
    XCTAssertEqual(mcp.updatedAtMillis, 1_800_000_000_000)
    XCTAssertEqual(native.kind, .nativeTool)
    XCTAssertEqual(native.version, "1.2.0")
    XCTAssertFalse(native.trusted)

    store.remove(desktopId: "desktop-1")
    XCTAssertTrue(store.list(
      pairedDesktopIds: ["desktop-1"],
      desktopSessionDesktopIds: ["desktop-1"]
    ).isEmpty)
  }

  func testAgentMcpRegistryDynamicAuthenticationAdvancesStepsAndExpires() throws {
    var now: Int64 = 1_000
    let registry = AgentMcpRegistry(InMemoryAgentMcpStore(), nowMillis: { now })
    let profile = try AgentMcpAuthProfile(
      .dynamic,
      accessTokenTtlMillis: 10_000,
      refreshLeadMillis: 2_000,
      supportsRefresh: true
    )
    let connection = try registry.addRemote(
      displayName: "Relay",
      endpoint: "https://relay.example/mcp",
      authProfile: profile,
      id: "relay-1"
    )

    XCTAssertEqual(connection.authState, .notConfigured)
    XCTAssertEqual(try registry.beginAuthentication(connection.id)?.id, "credentials")
    XCTAssertThrowsError(try registry.submitAuthenticationStep(connection.id, values: ["username": "operator"]))

    let challenge = try registry.submitAuthenticationStep(
      connection.id,
      values: ["username": "operator", "password": "secret"]
    )
    XCTAssertEqual(challenge.authState, .challengeRequired)
    XCTAssertEqual(challenge.currentAuthStep?.id, "verification")

    let authenticated = try registry.submitAuthenticationStep(
      connection.id,
      values: ["otp": "123456", "access_token": "session-token"]
    )
    XCTAssertEqual(authenticated.authState, .authenticated)
    let headers = try registry.requestHeaders(connection.id)
    XCTAssertEqual(headers["Authorization"], "Bearer session-token")
    XCTAssertTrue(authenticated.isCallable(nowMillis: now))

    now = authenticated.refreshAtMillis
    XCTAssertEqual(registry.get(connection.id)?.effectiveAuthState(nowMillis: now), .refreshing)
    XCTAssertTrue(registry.get(connection.id)?.isCallable(nowMillis: now) == true)

    now = authenticated.expiresAtMillis
    XCTAssertEqual(registry.get(connection.id)?.effectiveAuthState(nowMillis: now), .reauthenticationRequired)
    XCTAssertFalse(registry.get(connection.id)?.isCallable(nowMillis: now) ?? true)
  }

  func testAgentMcpConnectionCodecPreservesDynamicExchangeWithoutSecrets() throws {
    let exchange = try AgentMcpAuthExchangeSpec(
      method: "POST",
      pathTemplate: "/api/login",
      bodyTemplate: #"{"username":{{field.username}}}"#,
      responseMappings: ["access_token": "$.token"],
      acceptedStatusCodes: [200, 201]
    )
    let step = try AgentMcpAuthStepSpec(
      id: "login",
      title: "Sign in",
      fields: [try AgentMcpAuthFieldSpec(id: "username", label: "Username", type: .text)],
      exchange: exchange
    )
    let connection = AgentMcpConnection(
      id: "codec-1",
      displayName: "Codec",
      endpoint: "https://codec.example/mcp",
      distribution: .localPackage,
      transport: .declarativeHTTP,
      authProfile: try AgentMcpAuthProfile(.dynamic, steps: [step]),
      authState: .challengeRequired,
      permissionMode: .readOnly
    )

    let encoded = AgentMcpConnectionCodec.encode([connection])
    let decoded = AgentMcpConnectionCodec.decode(encoded).first

    XCTAssertEqual(decoded?.id, connection.id)
    XCTAssertEqual(decoded?.currentAuthStep?.exchange?.pathTemplate, "/api/login")
    XCTAssertEqual(decoded?.currentAuthStep?.exchange?.responseMappings["access_token"], "$.token")
    XCTAssertEqual(decoded?.currentAuthStep?.exchange?.acceptedStatusCodes, Set([200, 201]))
    XCTAssertEqual(decoded?.permissionMode, .readOnly)
    XCTAssertFalse(encoded.contains("session-token"))
  }

  func testFileAgentMcpStorePersistsConnectionsAndSecrets() throws {
    let root = try temporaryDirectory("mcp-file-store")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileAgentMcpStore(rootURL: root)
    let connection = AgentMcpConnection(
      id: "persisted-1",
      catalogId: "galaxyssi.mcp.persisted",
      displayName: "Persisted MCP",
      endpoint: "https://persisted.example/mcp",
      distribution: .remote,
      transport: .streamableHTTP,
      authProfile: try AgentMcpAuthProfile(.none),
      authState: .notRequired,
      state: .connected,
      toolIds: ["persisted.search"]
    )

    store.upsert(connection)
    store.writeSecrets(id: connection.id, values: ["access_token": "secret-token"])
    let restored = FileAgentMcpStore(rootURL: root)

    XCTAssertEqual(restored.list().map(\.id), ["persisted-1"])
    XCTAssertEqual(restored.list().first?.toolIds, ["persisted.search"])
    XCTAssertEqual(restored.readSecrets(id: connection.id)["access_token"], "secret-token")
    XCTAssertTrue(restored.delete(id: connection.id))
    XCTAssertTrue(FileAgentMcpStore(rootURL: root).list().isEmpty)
    XCTAssertTrue(FileAgentMcpStore(rootURL: root).readSecrets(id: connection.id).isEmpty)

    try "not-json".write(
      to: FileAgentMcpStore.defaultConnectionsFileURL(rootURL: root),
      atomically: true,
      encoding: .utf8
    )
    XCTAssertTrue(FileAgentMcpStore(rootURL: root).list().isEmpty)
  }

  func testAgentMcpAuthenticationCoordinatorSubmitsExchangeAndMapsToken() async throws {
    let root = try temporaryDirectory("mcp-auth-exchange-submit")
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = AgentMcpPackageRepository(rootDirectory: root)
    let inspection = try AgentMcpPackageInstaller().inspect(storedMcpPackage(
      ("mcp.json", mcpDeclarativePackageManifest())
    ))
    try repository.save(inspection)
    let registry = AgentMcpRegistry(InMemoryAgentMcpStore(), nowMillis: { 10_000 })
    let installed = try registry.installPackage(inspection.manifest, packageSha256: inspection.packageSha256)
    _ = try registry.beginAuthentication(installed.id)
    let transport = FakeMcpDeclarativeHTTPTransport([
      AgentMcpDeclarativeHTTPResponse(statusCode: 201, body: #"{"session":{"access_token":"mapped-token"}}"#)
    ])
    let coordinator = AgentMcpAuthenticationCoordinator(
      registry: registry,
      transport: transport,
      nowMillis: { 10_000 }
    )

    let authenticated = try await coordinator.submitStep(
      connectionId: installed.id,
      values: ["username": "alice", "password": "pw"]
    )
    let request = try XCTUnwrap(transport.requests.first)
    let headers = try registry.requestHeaders(installed.id)

    XCTAssertEqual(authenticated.authState, .authenticated)
    XCTAssertEqual(request.method, "POST")
    XCTAssertEqual(request.url, "https://relay.example/api/login")
    XCTAssertEqual(request.headers["Accept"], "application/json")
    XCTAssertEqual(request.body, #"{"username":"alice","password":"pw"}"#)
    XCTAssertEqual(headers["Authorization"], "Bearer mapped-token")
    XCTAssertTrue(authenticated.expiresAtMillis > 10_000)
  }

  func testAgentMcpAuthenticationCoordinatorRejectsEscapedExchangeAndMarksReauth() async throws {
    let exchange = try AgentMcpAuthExchangeSpec(
      method: "POST",
      pathTemplate: "//evil.example/login",
      bodyTemplate: #"{"username":{{field.username}}}"#,
      responseMappings: ["access_token": "$.token"]
    )
    let step = try AgentMcpAuthStepSpec(
      id: "login",
      title: "Sign in",
      fields: [try AgentMcpAuthFieldSpec(id: "username", label: "Username", type: .text)],
      exchange: exchange
    )
    let profile = try AgentMcpAuthProfile(.dynamic, steps: [step])
    let registry = AgentMcpRegistry(InMemoryAgentMcpStore(), nowMillis: { 10_000 })
    let connection = try registry.addRemote(
      displayName: "Relay",
      endpoint: "https://relay.example/api/",
      authProfile: profile,
      id: "relay-escaped-auth"
    )
    _ = try registry.beginAuthentication(connection.id)
    let transport = FakeMcpDeclarativeHTTPTransport([])
    let coordinator = AgentMcpAuthenticationCoordinator(
      registry: registry,
      transport: transport,
      nowMillis: { 10_000 }
    )

    do {
      _ = try await coordinator.submitStep(connectionId: connection.id, values: ["username": "alice"])
      XCTFail("Expected escaped MCP authentication exchange to be rejected")
    } catch {
      let stored = try XCTUnwrap(registry.get(connection.id))
      XCTAssertEqual(transport.requests.count, 0)
      XCTAssertEqual(stored.state, .needsSetup)
      XCTAssertEqual(stored.authState, .reauthenticationRequired)
      XCTAssertTrue(stored.lastError.contains("configured server"))
    }
  }

  func testAgentMcpAuthenticationCoordinatorRefreshesWhenTokenNearExpiry() async throws {
    var now: Int64 = 10_000
    let refreshExchange = try AgentMcpAuthExchangeSpec(
      method: "POST",
      pathTemplate: "/oauth/refresh",
      headerTemplates: ["Authorization": "Bearer {{auth.access_token}}"],
      bodyTemplate: #"{"refresh":{{auth.refresh_token}}}"#,
      responseMappings: ["access_token": "$.access_token"]
    )
    let profile = try AgentMcpAuthProfile(
      .bearerToken,
      accessTokenTtlMillis: 10_000,
      refreshLeadMillis: 2_000,
      supportsRefresh: true,
      refreshExchange: refreshExchange
    )
    let registry = AgentMcpRegistry(InMemoryAgentMcpStore(), nowMillis: { now })
    let connection = try registry.addRemote(
      displayName: "Relay",
      endpoint: "https://relay.example/api/",
      authProfile: profile,
      id: "relay-refresh"
    )
    _ = try registry.beginAuthentication(connection.id)
    let authenticated = try registry.submitAuthenticationStep(
      connection.id,
      values: ["access_token": "old-token", "refresh_token": "refresh-1"]
    )
    now = authenticated.refreshAtMillis
    let transport = FakeMcpDeclarativeHTTPTransport([
      AgentMcpDeclarativeHTTPResponse(statusCode: 200, body: #"{"access_token":"fresh-token"}"#)
    ])
    let coordinator = AgentMcpAuthenticationCoordinator(
      registry: registry,
      transport: transport,
      nowMillis: { now }
    )

    let refreshed = try await coordinator.refreshIfNeeded(connectionId: connection.id)
    let request = try XCTUnwrap(transport.requests.first)
    let headers = try registry.requestHeaders(connection.id)

    XCTAssertEqual(request.url, "https://relay.example/oauth/refresh")
    XCTAssertEqual(request.headers["Authorization"], "Bearer old-token")
    XCTAssertEqual(request.body, #"{"refresh":"refresh-1"}"#)
    XCTAssertEqual(refreshed.authState, .authenticated)
    XCTAssertEqual(headers["Authorization"], "Bearer fresh-token")
    XCTAssertTrue(refreshed.expiresAtMillis > now)
  }

  func testAgentMcpStreamableHTTPTransportSendsHeadersAndReceivesJson() async throws {
    let networking = FakeMcpStreamableHTTPNetworking([
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: [
          "Mcp-Session-Id": " session-1 ",
          "Content-Type": "application/json"
        ],
        body: #"{"jsonrpc":"2.0","id":1,"result":{}}"#
      ),
      AgentMcpStreamableHTTPResponse(statusCode: 200, headers: [:], body: "")
    ])
    let transport = try AgentMcpStreamableHTTPTransport(
      endpoint: "https://mcp.example/rpc",
      requestHeaders: [
        "Authorization": "Bearer token",
        "Content-Length": "999",
        "Bad\nName": "drop",
        "X-Unsafe": "line\nbreak"
      ],
      networking: networking
    )

    try transport.open()
    transport.onProtocolVersionNegotiated("2025-06-18")
    try await transport.send(#"{"jsonrpc":"2.0","id":1,"method":"initialize"}"#)
    try await transport.send(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)

    XCTAssertEqual(networking.requests.count, 2)
    XCTAssertEqual(networking.requests[0].endpoint, "https://mcp.example/rpc")
    XCTAssertEqual(networking.requests[0].headers["Accept"], "application/json, text/event-stream")
    XCTAssertEqual(networking.requests[0].headers["Content-Type"], "application/json")
    XCTAssertEqual(networking.requests[0].headers["User-Agent"], "GalaxySSI-iOS-MCP/1")
    XCTAssertEqual(networking.requests[0].headers["Authorization"], "Bearer token")
    XCTAssertEqual(networking.requests[0].headers["MCP-Protocol-Version"], "2025-06-18")
    XCTAssertNil(networking.requests[0].headers["Content-Length"])
    XCTAssertNil(networking.requests[0].headers["Bad\nName"])
    XCTAssertNil(networking.requests[0].headers["X-Unsafe"])
    XCTAssertEqual(networking.requests[0].body, #"{"jsonrpc":"2.0","id":1,"method":"initialize"}"#)
    XCTAssertEqual(transport.receive(), #"{"jsonrpc":"2.0","id":1,"result":{}}"#)
    XCTAssertNil(transport.receive())
    XCTAssertEqual(transport.currentSessionId, "session-1")
    XCTAssertEqual(networking.requests[1].headers["Mcp-Session-Id"], "session-1")
  }

  func testAgentMcpStreamableHTTPTransportParsesSseDataEvents() async throws {
    let networking = FakeMcpStreamableHTTPNetworking([
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["content-type": "text/event-stream; charset=utf-8"],
        body: """
        : keepalive
        data: {"jsonrpc":"2.0","id":1,"result":{"ok":true}}

        data: {"jsonrpc":"2.0","method":"tools/list_changed"}

        """
      )
    ])
    let transport = try AgentMcpStreamableHTTPTransport(endpoint: "https://mcp.example/rpc", networking: networking)

    try transport.open()
    try await transport.send(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)

    XCTAssertEqual(transport.receive(), #"{"jsonrpc":"2.0","id":1,"result":{"ok":true}}"#)
    XCTAssertEqual(transport.receive(), #"{"jsonrpc":"2.0","method":"tools/list_changed"}"#)
    XCTAssertNil(transport.receive())
  }

  func testAgentMcpStreamableHTTPTransportRejectsClosedStateAndHttpFailure() async throws {
    let networking = FakeMcpStreamableHTTPNetworking([
      AgentMcpStreamableHTTPResponse(statusCode: 401, headers: [:], body: "expired")
    ])
    let transport = try AgentMcpStreamableHTTPTransport(endpoint: "https://mcp.example/rpc", networking: networking)

    do {
      try await transport.send("{}")
      XCTFail("Expected unopened MCP streamable transport to reject sends")
    } catch {
      XCTAssertEqual(error as? AgentRuntimeCapabilityError, .invalid("MCP transport is not open"))
    }

    try transport.open()
    do {
      try await transport.send("{}")
      XCTFail("Expected HTTP failure from MCP streamable transport")
    } catch {
      let http = try XCTUnwrap(error as? AgentMcpStreamableHTTPError)
      XCTAssertEqual(http.statusCode, 401)
      XCTAssertEqual(http.authenticationFailure, true)
      XCTAssertTrue(http.message.contains("expired"))
    }

    transport.close()
    XCTAssertNil(transport.receive())
  }

  func testAgentMcpRemoteSessionInitializesListsAndCallsTools() async throws {
    let networking = FakeMcpStreamableHTTPNetworking([
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: #"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","serverInfo":{"name":"relay-mcp","version":"1.0.0"},"capabilities":{"tools":{}},"instructions":"ready"}}"#
      ),
      AgentMcpStreamableHTTPResponse(statusCode: 200, headers: [:], body: ""),
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: #"{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"relay.switch","title":"Switch relay","description":"Turns relay on","inputSchema":{"type":"object"},"annotations":{"readOnlyHint":false}}],"nextCursor":"next-page"}}"#
      ),
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: #"{"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"done"}],"structuredContent":{"state":"on"},"isError":false}}"#
      )
    ])
    let transport = try AgentMcpStreamableHTTPTransport(endpoint: "https://mcp.example/rpc", networking: networking)
    let session = AgentMcpRemoteSession(transport: transport)

    let initialized = try await session.initialize(
      clientInfo: AgentMcpImplementationInfo(name: "GalaxySSI iOS", version: "1")
    )
    let tools = try await session.listTools()
    let call = try await session.callTool(name: "relay.switch", arguments: ["enabled": .bool(true)])

    XCTAssertEqual(session.state, .active)
    XCTAssertEqual(initialized.protocolVersion, "2025-06-18")
    XCTAssertEqual(initialized.serverInfo.name, "relay-mcp")
    XCTAssertTrue(initialized.capabilities.tools)
    XCTAssertEqual(tools.items.map(\.name), ["relay.switch"])
    XCTAssertEqual(tools.nextCursor, "next-page")
    XCTAssertEqual(tools.items.first?.inputSchema["type"], .string("object"))
    XCTAssertEqual(tools.items.first?.annotations?["readOnlyHint"], .bool(false))
    XCTAssertEqual(call.content.first?.text, "done")
    XCTAssertEqual(call.structuredContent?["state"], .string("on"))
    XCTAssertEqual(networking.requests.count, 4)
    XCTAssertTrue(networking.requests[0].body.contains(#""method":"initialize""#))
    XCTAssertTrue(networking.requests[1].body.contains(#""method":"notifications/initialized""#))
    XCTAssertTrue(networking.requests[2].body.contains(#""method":"tools/list""#))
    XCTAssertTrue(networking.requests[3].body.contains(#""method":"tools/call""#))
  }

  func testAgentMcpRemoteSessionReceivesNotificationsAndRespondsToPing() async throws {
    let listener = TestMcpRemoteSessionListener()
    let networking = FakeMcpStreamableHTTPNetworking([
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "text/event-stream"],
        body: """
        data: {"jsonrpc":"2.0","method":"notifications/progress","params":{"step":"connecting"}}

        data: {"jsonrpc":"2.0","id":"server-ping","method":"ping"}

        data: {"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","serverInfo":{"name":"relay-mcp","version":"1.0.0"},"capabilities":{"tools":{}}}}

        """
      ),
      AgentMcpStreamableHTTPResponse(statusCode: 200, headers: [:], body: ""),
      AgentMcpStreamableHTTPResponse(statusCode: 200, headers: [:], body: "")
    ])
    let transport = try AgentMcpStreamableHTTPTransport(endpoint: "https://mcp.example/rpc", networking: networking)
    let session = AgentMcpRemoteSession(transport: transport, listener: listener)

    let initialized = try await session.initialize(clientInfo: AgentMcpImplementationInfo(name: "GalaxySSI iOS", version: "1"))

    XCTAssertTrue(initialized.capabilities.tools)
    XCTAssertEqual(listener.notifications.map(\.method), ["notifications/progress"])
    XCTAssertEqual(listener.notifications.first?.params?["step"], .string("connecting"))
    XCTAssertTrue(listener.issues.isEmpty)
    XCTAssertEqual(networking.requests.count, 3)
    XCTAssertTrue(networking.requests[1].body.contains(#""id":"server-ping""#))
    XCTAssertTrue(networking.requests[1].body.contains(#""result":{}"#))
    XCTAssertTrue(networking.requests[2].body.contains(#""method":"notifications/initialized""#))
  }

  func testAgentMcpRemoteSessionReturnsMethodNotFoundForUnknownServerRequest() async throws {
    let networking = FakeMcpStreamableHTTPNetworking([
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: #"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","serverInfo":{"name":"relay-mcp","version":"1.0.0"},"capabilities":{"tools":{}}}}"#
      ),
      AgentMcpStreamableHTTPResponse(statusCode: 200, headers: [:], body: ""),
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "text/event-stream"],
        body: """
        data: {"jsonrpc":"2.0","id":7,"method":"sampling/createMessage"}

        data: {"jsonrpc":"2.0","id":2,"result":{"tools":[]}}

        """
      ),
      AgentMcpStreamableHTTPResponse(statusCode: 200, headers: [:], body: "")
    ])
    let transport = try AgentMcpStreamableHTTPTransport(endpoint: "https://mcp.example/rpc", networking: networking)
    let session = AgentMcpRemoteSession(transport: transport)
    _ = try await session.initialize(clientInfo: AgentMcpImplementationInfo(name: "GalaxySSI iOS", version: "1"))

    let tools = try await session.listTools()

    XCTAssertTrue(tools.items.isEmpty)
    XCTAssertEqual(networking.requests.count, 4)
    XCTAssertTrue(networking.requests[3].body.contains(#""id":7"#))
    XCTAssertTrue(networking.requests[3].body.contains(#""code":-32601"#))
    XCTAssertTrue(networking.requests[3].body.contains("Method not found: sampling/createMessage"))
  }

  func testAgentMcpRemoteSessionListsReadsResourcesAndPrompts() async throws {
    let networking = FakeMcpStreamableHTTPNetworking([
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: #"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","serverInfo":{"name":"relay-mcp","version":"1.0.0"},"capabilities":{"resources":{},"prompts":{}}}}"#
      ),
      AgentMcpStreamableHTTPResponse(statusCode: 200, headers: [:], body: ""),
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: #"{"jsonrpc":"2.0","id":2,"result":{"resources":[{"uri":"file:///README.md","name":"README.md","title":"Project readme","mimeType":"text/markdown","size":42,"annotations":{"priority":0.8}}]}}"#
      ),
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: #"{"jsonrpc":"2.0","id":3,"result":{"contents":[{"uri":"file:///README.md","mimeType":"text/markdown","text":"# GalaxySSI"}]}}"#
      ),
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: #"{"jsonrpc":"2.0","id":4,"result":{"prompts":[{"name":"review","title":"Review","arguments":[{"name":"focus","description":"Review focus","required":true}]}],"nextCursor":"prompt-page-2"}}"#
      ),
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: #"{"jsonrpc":"2.0","id":5,"result":{"description":"Focused review","messages":[{"role":"user","content":{"type":"text","text":"Review cancellation behavior"}},{"role":"assistant","content":{"type":"resource","resource":{"uri":"file:///README.md","mimeType":"text/markdown","text":"# GalaxySSI"}}}]}}"#
      )
    ])
    let transport = try AgentMcpStreamableHTTPTransport(endpoint: "https://mcp.example/rpc", networking: networking)
    let session = AgentMcpRemoteSession(transport: transport)
    _ = try await session.initialize(clientInfo: AgentMcpImplementationInfo(name: "GalaxySSI iOS", version: "1"))

    let resources = try await session.listResources()
    let resource = try await session.readResource(uri: "file:///README.md")
    let prompts = try await session.listPrompts(cursor: "prompt-page-1")
    let prompt = try await session.getPrompt(name: "review", arguments: ["focus": "cancellation"])

    XCTAssertEqual(resources.items.first?.name, "README.md")
    XCTAssertEqual(resources.items.first?.size, 42)
    XCTAssertEqual(resources.items.first?.annotations?["priority"], .double(0.8))
    XCTAssertEqual(resource.contents.first?.text, "# GalaxySSI")
    XCTAssertNil(resource.contents.first?.blob)
    XCTAssertEqual(prompts.nextCursor, "prompt-page-2")
    XCTAssertEqual(prompts.items.first?.arguments.first?.required, true)
    XCTAssertEqual(prompt.description, "Focused review")
    XCTAssertEqual(prompt.messages.first?.role, "user")
    XCTAssertEqual(prompt.messages.first?.content.text, "Review cancellation behavior")
    XCTAssertEqual(prompt.messages.last?.content.resource?.uri, "file:///README.md")
    XCTAssertEqual(prompt.messages.last?.content.resource?.text, "# GalaxySSI")
    XCTAssertEqual(networking.requests.count, 6)
    XCTAssertTrue(networking.requests[4].body.contains(#""method":"prompts/list""#))
    XCTAssertTrue(networking.requests[4].body.contains(#""cursor":"prompt-page-1""#))
    XCTAssertTrue(networking.requests[5].body.contains(#""method":"prompts/get""#))
    XCTAssertTrue(networking.requests[5].body.contains(#""focus":"cancellation""#))
  }

  func testAgentMcpRemoteSessionMapsJsonRpcError() async throws {
    let networking = FakeMcpStreamableHTTPNetworking([
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: #"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","serverInfo":{"name":"relay-mcp","version":"1.0.0"},"capabilities":{"tools":{}}}}"#
      ),
      AgentMcpStreamableHTTPResponse(statusCode: 200, headers: [:], body: ""),
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: #"{"jsonrpc":"2.0","id":2,"error":{"code":-32601,"message":"tools unavailable","data":{"reason":"disabled"}}}"#
      )
    ])
    let transport = try AgentMcpStreamableHTTPTransport(endpoint: "https://mcp.example/rpc", networking: networking)
    let session = AgentMcpRemoteSession(transport: transport)
    _ = try await session.initialize(clientInfo: AgentMcpImplementationInfo(name: "GalaxySSI iOS", version: "1"))

    do {
      _ = try await session.listTools()
      XCTFail("Expected JSON-RPC error from MCP tools/list")
    } catch {
      let sessionError = try XCTUnwrap(error as? AgentMcpRemoteSessionError)
      XCTAssertEqual(sessionError.kind, .remote)
      XCTAssertEqual(sessionError.requestId, 2)
      XCTAssertEqual(sessionError.method, "tools/list")
      XCTAssertEqual(sessionError.rpcCode, -32601)
      XCTAssertEqual(sessionError.data?.objectValue?["reason"], .string("disabled"))
      XCTAssertEqual(sessionError.message, "tools unavailable")
    }
  }

  func testAgentMcpRemoteSessionRequiresNegotiatedToolsCapability() async throws {
    let networking = FakeMcpStreamableHTTPNetworking([
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: #"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","serverInfo":{"name":"relay-mcp","version":"1.0.0"},"capabilities":{}}}"#
      ),
      AgentMcpStreamableHTTPResponse(statusCode: 200, headers: [:], body: "")
    ])
    let transport = try AgentMcpStreamableHTTPTransport(endpoint: "https://mcp.example/rpc", networking: networking)
    let session = AgentMcpRemoteSession(transport: transport)
    _ = try await session.initialize(clientInfo: AgentMcpImplementationInfo(name: "GalaxySSI iOS", version: "1"))

    do {
      _ = try await session.listTools()
      XCTFail("Expected missing tools capability to reject tools/list")
    } catch {
      let sessionError = try XCTUnwrap(error as? AgentMcpRemoteSessionError)
      XCTAssertEqual(sessionError.kind, .capabilityNotNegotiated)
      XCTAssertEqual(sessionError.method, "tools/list")
      XCTAssertEqual(networking.requests.count, 2)
    }

    do {
      _ = try await session.listResources()
      XCTFail("Expected missing resources capability to reject resources/list")
    } catch {
      let sessionError = try XCTUnwrap(error as? AgentMcpRemoteSessionError)
      XCTAssertEqual(sessionError.kind, .capabilityNotNegotiated)
      XCTAssertEqual(sessionError.method, "resources/list")
      XCTAssertEqual(networking.requests.count, 2)
    }
  }

  func testAgentMcpClientManagerListsCallsRemoteAndAudits() async throws {
    let root = try temporaryDirectory("mcp-client-manager-remote")
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = AgentMcpPackageRepository(rootDirectory: root)
    let registry = AgentMcpRegistry(InMemoryAgentMcpStore(), nowMillis: { 10_000 })
    let connection = try registry.addRemote(
      displayName: "Relay MCP",
      endpoint: "https://mcp.example/rpc",
      authProfile: try AgentMcpAuthProfile(.none),
      id: "relay-remote"
    )
    let auditStore = InMemoryAgentMcpAuditStore()
    let networking = FakeMcpStreamableHTTPNetworking([
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: #"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","serverInfo":{"name":"relay-mcp","version":"1.0.0"},"capabilities":{"tools":{}}}}"#
      ),
      AgentMcpStreamableHTTPResponse(statusCode: 200, headers: [:], body: ""),
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: #"{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"update_document","title":"Update document","inputSchema":{"type":"object"},"annotations":{"readOnlyHint":false}}]}}"#
      ),
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: #"{"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"updated"}],"structuredContent":{"ok":true}}}"#
      )
    ])
    let manager = AgentMcpClientManager(
      registry: registry,
      packageRepository: repository,
      auditStore: auditStore,
      remoteSessionFactory: { connection, headers in
        XCTAssertEqual(connection.id, "relay-remote")
        XCTAssertTrue(headers.isEmpty)
        let transport = try AgentMcpStreamableHTTPTransport(
          endpoint: connection.endpoint,
          requestHeaders: headers,
          networking: networking
        )
        return AgentMcpRemoteSession(transport: transport)
      },
      nowMillis: { 10_000 }
    )

    let tools = try await manager.listTools(connectionId: connection.id)
    let result = await manager.callTool(
      connectionId: connection.id,
      toolName: "update_document",
      arguments: ["content": .string("new")],
      context: AgentNativeToolInvocationContext(attributes: ["explicit_user_approval": "true", "task_id": "task-1"])
    )
    let audit = try XCTUnwrap(manager.audit(connectionId: connection.id, limit: 10).first)

    XCTAssertEqual(tools.map(\.name), ["update_document"])
    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(result.message, "updated")
    XCTAssertEqual(result.output["structured_content"]?.objectValue?["ok"], .bool(true))
    XCTAssertEqual(result.metadata["mcp_permission_decision"], .string("allowed_explicit_change"))
    XCTAssertNotNil(result.metadata["mcp_security"]?.objectValue)
    XCTAssertEqual(result.metadata["mcp_audit_id"], .string(audit.auditId))
    XCTAssertEqual(audit.status, "succeeded")
    XCTAssertEqual(audit.taskId, "task-1")
    XCTAssertEqual(audit.permissionDecision, "allowed_explicit_change")
    XCTAssertEqual(registry.get(connection.id)?.state, .connected)
    XCTAssertEqual(networking.requests.count, 4)
  }

  func testAgentMcpClientManagerDeniesUnapprovedMutatingCallAndAudits() async throws {
    let root = try temporaryDirectory("mcp-client-manager-denied")
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = AgentMcpPackageRepository(rootDirectory: root)
    let registry = AgentMcpRegistry(InMemoryAgentMcpStore(), nowMillis: { 10_000 })
    let connection = try registry.addRemote(
      displayName: "Relay MCP",
      endpoint: "https://mcp.example/rpc",
      authProfile: try AgentMcpAuthProfile(.none),
      id: "relay-denied"
    )
    let auditStore = InMemoryAgentMcpAuditStore()
    let networking = FakeMcpStreamableHTTPNetworking([
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: #"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","serverInfo":{"name":"relay-mcp","version":"1.0.0"},"capabilities":{"tools":{}}}}"#
      ),
      AgentMcpStreamableHTTPResponse(statusCode: 200, headers: [:], body: ""),
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: #"{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"update_document","inputSchema":{"type":"object"},"annotations":{"readOnlyHint":false}}]}}"#
      )
    ])
    let manager = AgentMcpClientManager(
      registry: registry,
      packageRepository: repository,
      auditStore: auditStore,
      remoteSessionFactory: { connection, headers in
        let transport = try AgentMcpStreamableHTTPTransport(
          endpoint: connection.endpoint,
          requestHeaders: headers,
          networking: networking
        )
        return AgentMcpRemoteSession(transport: transport)
      },
      nowMillis: { 10_000 }
    )

    let result = await manager.callTool(
      connectionId: connection.id,
      toolName: "update_document",
      arguments: ["content": .string("new")]
    )
    let audit = try XCTUnwrap(manager.audit(connectionId: connection.id, limit: 10).first)

    XCTAssertFalse(result.isSuccess)
    XCTAssertEqual(result.error?.code, "mcp_approval_required")
    XCTAssertEqual(result.error?.details["required_user_action"], .string("approve_tool_call"))
    XCTAssertEqual(result.metadata["mcp_permission_decision"], .string("mcp_approval_required"))
    XCTAssertEqual(audit.status, "denied")
    XCTAssertEqual(audit.errorCode, "mcp_approval_required")
    XCTAssertEqual(networking.requests.count, 3)
  }

  func testAgentMcpClientManagerReturnsAuthenticationFailureForDeclarativeHttp() async throws {
    let root = try temporaryDirectory("mcp-client-manager-declarative-auth")
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = AgentMcpPackageRepository(rootDirectory: root)
    let inspection = try AgentMcpPackageInstaller().inspect(storedMcpPackage(
      ("mcp.json", mcpDeclarativePackageManifest())
    ))
    try repository.save(inspection)
    let registry = AgentMcpRegistry(InMemoryAgentMcpStore(), nowMillis: { 10_000 })
    let installed = try registry.installPackage(inspection.manifest, packageSha256: inspection.packageSha256)
    _ = try registry.beginAuthentication(installed.id)
    let authenticated = try registry.submitAuthenticationStep(
      installed.id,
      values: ["username": "alice", "password": "pw", "access_token": "expired-token"]
    )
    let auditStore = InMemoryAgentMcpAuditStore()
    let transport = FakeMcpDeclarativeHTTPTransport([
      AgentMcpDeclarativeHTTPResponse(statusCode: 401, body: #"{"error":"expired"}"#)
    ])
    let declarative = AgentMcpDeclarativeHTTPClient(
      registry: registry,
      packageRepository: repository,
      transport: transport,
      nowMillis: { 10_000 }
    )
    let manager = AgentMcpClientManager(
      registry: registry,
      packageRepository: repository,
      auditStore: auditStore,
      declarativeHTTPClient: declarative,
      nowMillis: { 10_000 }
    )

    let result = await manager.callTool(
      connectionId: authenticated.id,
      toolName: "relay.switch",
      arguments: ["device_id": .string("relay-1"), "enabled": .bool(true)],
      context: AgentNativeToolInvocationContext(attributes: ["explicit_user_approval": "true"])
    )
    let audit = try XCTUnwrap(manager.audit(connectionId: authenticated.id, limit: 10).first)

    XCTAssertFalse(result.isSuccess)
    XCTAssertEqual(result.error?.code, "mcp_authentication_required")
    XCTAssertEqual(audit.status, "failed")
    XCTAssertEqual(audit.errorCode, "mcp_authentication_required")
    XCTAssertEqual(registry.get(authenticated.id)?.state, .needsSetup)
    XCTAssertEqual(registry.get(authenticated.id)?.authState, .reauthenticationRequired)
  }

  func testAgentMcpLocalRuntimeResponseCodecDecodesLastStructuredBridgeResult() throws {
    let result = try AgentMcpLocalRuntimeResponseCodec.decode(
      """
      __GALAXYSSI_MCP_RESULT__{"ok":true,"result":{"tools":[{"name":"stale.tool"}]}}
      server starting
      {"unrelated":true}
      __GALAXYSSI_MCP_RESULT__{"ok":true,"result":{"tools":[{"name":"device.read"}]}}
      """
    )
    guard case .array(let tools)? = result["tools"],
          case .object(let firstTool)? = tools.first else {
      XCTFail("Expected decoded tool list")
      return
    }

    XCTAssertEqual(firstTool["name"], .string("device.read"))
  }

  func testAgentMcpLocalRuntimeResponseCodecSurfacesBridgeFailure() {
    XCTAssertThrowsError(
      try AgentMcpLocalRuntimeResponseCodec.decode(
        #"__GALAXYSSI_MCP_RESULT__{"ok":false,"error":"server authentication failed"}"#
      )
    ) { error in
      XCTAssertEqual(error as? AgentRuntimeCapabilityError, .invalid("server authentication failed"))
    }
  }

  func testAgentMcpLocalRuntimeResponseCodecRejectsUnstructuredOutput() {
    XCTAssertThrowsError(try AgentMcpLocalRuntimeResponseCodec.decode("plain process output")) { error in
      XCTAssertEqual(error as? AgentRuntimeCapabilityError, .invalid("Local MCP bridge returned no structured result"))
    }
  }

  func testAgentMcpPackageManifestCodecDecodesDeclarativeHttpAndDynamicAuthExchange() throws {
    let manifest = try AgentMcpPackageManifestCodec.decode(mcpDeclarativePackageManifest())
    let exchange = manifest.authProfiles.first?.steps.first?.exchange
    let tool = try XCTUnwrap(manifest.tools.first)

    XCTAssertEqual(manifest.id, "example.relay")
    XCTAssertEqual(manifest.endpoint, "https://relay.example/api/")
    XCTAssertEqual(manifest.transport, .declarativeHTTP)
    XCTAssertEqual(manifest.authProfiles.first?.method, .dynamic)
    XCTAssertEqual(exchange?.pathTemplate, "/api/login")
    XCTAssertEqual(exchange?.responseMappings["access_token"], "$.session.access_token")
    XCTAssertEqual(exchange?.acceptedStatusCodes, Set([200, 201]))
    XCTAssertEqual(tool.name, "relay.switch")
    XCTAssertEqual(tool.method, "POST")
    XCTAssertEqual(tool.pathTemplate, "/api/relay/{{args.device_id}}")
    XCTAssertEqual(tool.inputSchema["type"], .string("object"))
    XCTAssertTrue(tool.mutating)
    XCTAssertTrue(try AgentMcpPackageManifestCodec.encode(manifest).contains(#""declarative_http""#))
  }

  func testAgentMcpPackageManifestCodecAcceptsSandboxedLocalStdioRuntime() throws {
    let manifest = try AgentMcpPackageManifestCodec.decode(mcpLocalStdioPackageManifest())
    let runtime = try XCTUnwrap(manifest.localRuntime)

    XCTAssertEqual(manifest.transport, .localStdio)
    XCTAssertEqual(manifest.endpoint, "local-mcp:example.local_mcp")
    XCTAssertEqual(runtime.language, .python)
    XCTAssertEqual(runtime.entrypoint, "runtime/server.py")
    XCTAssertEqual(runtime.arguments, ["--stdio"])
    XCTAssertEqual(runtime.environment["ACCESS_TOKEN"], "{{auth.access_token}}")
    XCTAssertTrue(runtime.allowedNetworkDomains.isEmpty)
    XCTAssertEqual(runtime.timeoutMillis, 45_000)
    let encoded = try AgentMcpPackageManifestCodec.encode(manifest)
    XCTAssertTrue(encoded.contains(#""local_stdio""#))
    XCTAssertTrue(encoded.contains(#""timeout_ms":45000"#))
  }

  func testAgentMcpPackageManifestCodecRejectsUnsafeLocalRuntimeAndHttpAuthExchange() {
    XCTAssertThrowsError(try AgentMcpPackageManifestCodec.decode(
      mcpLocalStdioPackageManifest(entrypoint: "../server.py")
    ))
    XCTAssertThrowsError(try AgentMcpPackageManifestCodec.decode(
      mcpLocalStdioPackageManifest(authentication: """
      [{"method":"username_password","steps":[{"id":"login","title":"Sign in","fields":[],"exchange":{"method":"POST","path":"/login"}}]}]
      """)
    ))
    XCTAssertThrowsError(try AgentMcpPackageManifestCodec.decode(
      mcpLocalStdioPackageManifest(allowedNetworkDomains: #""example.com""#)
    ))
  }

  func testAgentMcpPackageInstallerInspectsIntegrityAndRuntimeFiles() throws {
    let manifest = mcpLocalStdioPackageManifest()
    let runtime = "print('server')"
    let inspection = try AgentMcpPackageInstaller().inspect(storedMcpPackage(
      ("mcp.json", manifest),
      ("integrity.json", mcpPackageIntegrity(for: manifest)),
      ("runtime/server.py", runtime),
      ("README.md", "# Local MCP")
    ))

    XCTAssertTrue(inspection.integrityVerified)
    XCTAssertEqual(inspection.manifest.transport, .localStdio)
    XCTAssertEqual(inspection.manifest.endpoint, "local-mcp:example.local_mcp")
    XCTAssertEqual(inspection.manifestSha256, AgentMcpPackageInstaller.sha256(Data(manifest.utf8)))
    XCTAssertEqual(inspection.packageSha256.count, 64)
    XCTAssertEqual(inspection.archiveEntries, ["README.md", "integrity.json", "mcp.json", "runtime/server.py"])
    XCTAssertEqual(inspection.runtimeFiles["runtime/server.py"], Data(runtime.utf8))
  }

  func testAgentMcpPackageInstallerAcceptsDeflatedZipEntries() throws {
    let manifest = mcpLocalStdioPackageManifest()
    let runtime = "print('server')"
    let inspection = try AgentMcpPackageInstaller().inspect(deflatedZipArchive(
      ("mcp.json", manifest),
      ("integrity.json", mcpPackageIntegrity(for: manifest)),
      ("runtime/server.py", runtime)
    ))

    XCTAssertTrue(inspection.integrityVerified)
    XCTAssertEqual(inspection.archiveEntries, ["integrity.json", "mcp.json", "runtime/server.py"])
    XCTAssertEqual(inspection.runtimeFiles["runtime/server.py"], Data(runtime.utf8))
  }

  func testAgentMcpPackageInstallerAcceptsUnsignedPackageButReportsItForReview() throws {
    let inspection = try AgentMcpPackageInstaller().inspect(storedMcpPackage(
      ("mcp.json", mcpDeclarativePackageManifest())
    ))

    XCTAssertFalse(inspection.integrityVerified)
    XCTAssertEqual(inspection.manifest.transport, .declarativeHTTP)
    XCTAssertEqual(inspection.manifest.tools.first?.name, "relay.switch")
    XCTAssertTrue(inspection.runtimeFiles.isEmpty)
  }

  func testAgentMcpPackageInstallerRejectsTraversalUnsupportedAndTamperedPackages() {
    let manifest = mcpDeclarativePackageManifest()
    let installer = AgentMcpPackageInstaller()

    XCTAssertThrowsError(try installer.inspect(storedMcpPackage(("../mcp.json", manifest))))
    XCTAssertThrowsError(try installer.inspect(storedMcpPackage(
      ("mcp.json", manifest),
      ("server.js", "run()")
    )))
    XCTAssertThrowsError(try installer.inspect(storedMcpPackage(
      ("mcp.json", manifest),
      ("integrity.json", #"{"manifest_sha256":"0000000000000000000000000000000000000000000000000000000000000000"}"#)
    )))
  }

  func testAgentMcpPackageInstallerRejectsLocalStdioPackageMissingEntrypoint() {
    XCTAssertThrowsError(try AgentMcpPackageInstaller().inspect(storedMcpPackage(
      ("mcp.json", mcpLocalStdioPackageManifest())
    )))
  }

  func testAgentMcpRegistryInstallsPackageConnection() throws {
    let manifest = try AgentMcpPackageManifestCodec.decode(mcpDeclarativePackageManifest())
    let registry = AgentMcpRegistry(InMemoryAgentMcpStore(), nowMillis: { 9_000 })

    let connection = try registry.installPackage(manifest, packageSha256: String(repeating: "a", count: 64))

    XCTAssertEqual(connection.id, "example.relay")
    XCTAssertEqual(connection.catalogId, "galaxyssi.mcp.relay")
    XCTAssertEqual(connection.displayName, "Relay Controller")
    XCTAssertEqual(connection.endpoint, "https://relay.example/api/")
    XCTAssertEqual(connection.distribution, .localPackage)
    XCTAssertEqual(connection.transport, .declarativeHTTP)
    XCTAssertEqual(connection.authProfile.method, .dynamic)
    XCTAssertEqual(connection.authState, .notConfigured)
    XCTAssertEqual(connection.state, .needsSetup)
    XCTAssertEqual(connection.toolIds, ["relay.switch"])
    XCTAssertEqual(connection.packageVersion, "1.0.0")
    XCTAssertEqual(connection.packageSha256, String(repeating: "a", count: 64))
    XCTAssertEqual(connection.installedAtMillis, 9_000)
    XCTAssertEqual(registry.get("example.relay"), connection)
  }

  func testAgentMcpPackageRepositorySavesAndPreparesLocalInvocation() throws {
    let root = try temporaryDirectory("mcp-package-repository")
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = AgentMcpPackageRepository(rootDirectory: root)
    let runtime = "print('server')"
    let inspection = try AgentMcpPackageInstaller().inspect(storedMcpPackage(
      ("mcp.json", mcpLocalStdioPackageManifest()),
      ("runtime/server.py", runtime)
    ))

    try repository.save(inspection)
    let saved = try XCTUnwrap(repository.get("example.local_mcp"))
    let invocation = try repository.prepareLocalInvocation(
      id: "example.local_mcp",
      payload: #"{"operation":"list_tools"}"#
    )

    let workspace = root
      .appendingPathComponent("agent-native-workspaces", isDirectory: true)
      .appendingPathComponent(invocation.workspaceId, isDirectory: true)
    let runtimeFile = workspace.appendingPathComponent("runtime/server.py", isDirectory: false)
    let requestFile = relativeFile(invocation.requestPath, under: workspace)

    XCTAssertEqual(saved.id, "example.local_mcp")
    XCTAssertTrue(invocation.workspaceId.hasPrefix("mcp-"))
    XCTAssertTrue(invocation.requestPath.hasPrefix(".galaxyssi-mcp/request-"))
    XCTAssertEqual(try String(contentsOf: runtimeFile, encoding: .utf8), runtime)
    XCTAssertEqual(try String(contentsOf: requestFile, encoding: .utf8), #"{"operation":"list_tools"}"#)

    repository.completeLocalInvocation(invocation)
    XCTAssertFalse(FileManager.default.fileExists(atPath: requestFile.path))
    repository.delete("example.local_mcp")
    XCTAssertNil(repository.get("example.local_mcp"))
  }

  func testAgentMcpLocalRuntimeClientListsToolsAndRendersSecretEnvironment() throws {
    let root = try temporaryDirectory("mcp-local-runtime-list")
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = AgentMcpPackageRepository(rootDirectory: root)
    let inspection = try AgentMcpPackageInstaller().inspect(storedMcpPackage(
      ("mcp.json", mcpLocalStdioPackageManifest()),
      ("runtime/server.py", "print('server')")
    ))
    try repository.save(inspection)
    let registry = AgentMcpRegistry(InMemoryAgentMcpStore(), nowMillis: { 10_000 })
    let installed = try registry.installPackage(inspection.manifest, packageSha256: inspection.packageSha256)
    _ = try registry.beginAuthentication(installed.id)
    let authenticated = try registry.submitAuthenticationStep(installed.id, values: ["access_token": "secret-token"])
    let executor = FakeMcpLocalRuntimeExecutor([
      AgentMcpLocalRuntimeExecutionResponse(
        stdout: """
        bridge booted
        __GALAXYSSI_MCP_RESULT__{"ok":true,"result":{"tools":[{"name":"device.read","title":"Read device","description":"Reads state","inputSchema":{"type":"object"},"annotations":{"readOnlyHint":true}}]}}
        """,
        stderr: "",
        exitCode: 0
      )
    ])
    let client = AgentMcpLocalRuntimeClient(
      registry: registry,
      packageRepository: repository,
      executor: executor,
      nowMillis: { 10_000 }
    )

    let tools = try client.listTools(connection: authenticated)
    let request = try XCTUnwrap(executor.requests.first)
    let workspace = root
      .appendingPathComponent("agent-native-workspaces", isDirectory: true)
      .appendingPathComponent(request.workspaceId, isDirectory: true)
    let requestFile = relativeFile(try XCTUnwrap(request.arguments.first), under: workspace)

    XCTAssertEqual(tools.map(\.name), ["device.read"])
    XCTAssertEqual(tools.first?.title, "Read device")
    XCTAssertEqual(tools.first?.inputSchema["type"], .string("object"))
    XCTAssertEqual(tools.first?.annotations?["readOnlyHint"], .bool(true))
    XCTAssertEqual(request.language, .python)
    XCTAssertTrue(request.source.contains("GALAXYSSI_MCP_SANDBOX"))
    XCTAssertTrue(request.arguments.first?.hasPrefix(".galaxyssi-mcp/request-") == true)
    XCTAssertEqual(request.secretEnvironment["ACCESS_TOKEN"], "secret-token")
    XCTAssertFalse(FileManager.default.fileExists(atPath: requestFile.path))
  }

  func testAgentMcpLocalRuntimeClientCallsToolAndMapsServerErrorResult() throws {
    let root = try temporaryDirectory("mcp-local-runtime-call")
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = AgentMcpPackageRepository(rootDirectory: root)
    let inspection = try AgentMcpPackageInstaller().inspect(storedMcpPackage(
      ("mcp.json", mcpLocalStdioPackageManifest(authentication: #"[{"method":"none"}]"#)),
      ("runtime/server.py", "print('server')")
    ))
    try repository.save(inspection)
    let registry = AgentMcpRegistry(InMemoryAgentMcpStore(), nowMillis: { 10_000 })
    let connection = try registry.installPackage(inspection.manifest, packageSha256: inspection.packageSha256)
    let executor = FakeMcpLocalRuntimeExecutor([
      AgentMcpLocalRuntimeExecutionResponse(
        stdout: #"__GALAXYSSI_MCP_RESULT__{"ok":true,"result":{"content":[{"type":"text","text":"done"}],"structuredContent":{"ok":true}}}"#,
        stderr: "",
        exitCode: 0
      ),
      AgentMcpLocalRuntimeExecutionResponse(
        stdout: #"__GALAXYSSI_MCP_RESULT__{"ok":true,"result":{"isError":true,"content":[{"type":"text","text":"denied"}]}}"#,
        stderr: "",
        exitCode: 0
      )
    ])
    let client = AgentMcpLocalRuntimeClient(
      registry: registry,
      packageRepository: repository,
      executor: executor,
      nowMillis: { 10_000 }
    )

    let success = try client.callTool(connection: connection, toolName: "device.read", arguments: ["enabled": .bool(true)])
    let failure = try client.callTool(connection: connection, toolName: "device.write", arguments: [:])

    XCTAssertTrue(success.isSuccess)
    XCTAssertEqual(success.message, "done")
    XCTAssertEqual(success.output["structured_content"]?.objectValue?["ok"], .bool(true))
    XCTAssertEqual(success.metadata["transport"], .string("local_stdio"))
    XCTAssertFalse(failure.isSuccess)
    XCTAssertEqual(failure.error?.code, "mcp_tool_error")
    XCTAssertEqual(failure.message, "denied")
    XCTAssertEqual(executor.requests.map(\.requestId).count, 2)
    XCTAssertEqual(executor.requests[0].workspaceId, executor.requests[1].workspaceId)
  }

  func testAgentMcpDeclarativeHTTPClientListsAndCallsPackageTool() async throws {
    let root = try temporaryDirectory("mcp-declarative-http-call")
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = AgentMcpPackageRepository(rootDirectory: root)
    let inspection = try AgentMcpPackageInstaller().inspect(storedMcpPackage(
      ("mcp.json", mcpDeclarativePackageManifest())
    ))
    try repository.save(inspection)
    let registry = AgentMcpRegistry(InMemoryAgentMcpStore(), nowMillis: { 10_000 })
    let installed = try registry.installPackage(inspection.manifest, packageSha256: inspection.packageSha256)
    _ = try registry.beginAuthentication(installed.id)
    let authenticated = try registry.submitAuthenticationStep(
      installed.id,
      values: [
        "username": "alice",
        "password": "pw",
        "access_token": "secret-token"
      ]
    )
    let transport = FakeMcpDeclarativeHTTPTransport([
      AgentMcpDeclarativeHTTPResponse(statusCode: 200, body: #"{"relay":{"state":"on"}}"#)
    ])
    let client = AgentMcpDeclarativeHTTPClient(
      registry: registry,
      packageRepository: repository,
      transport: transport,
      nowMillis: { 10_000 }
    )

    let tools = try client.listTools(connection: authenticated)
    let result = try await client.callTool(
      connection: authenticated,
      toolName: "relay.switch",
      arguments: [
        "device_id": .string("relay 1"),
        "enabled": .bool(true)
      ]
    )
    let request = try XCTUnwrap(transport.requests.first)
    let stored = try XCTUnwrap(registry.get(installed.id))

    XCTAssertEqual(tools.map(\.name), ["relay.switch"])
    XCTAssertEqual(tools.first?.annotations?["readOnlyHint"], .bool(false))
    XCTAssertEqual(request.method, "POST")
    XCTAssertEqual(request.url, "https://relay.example/api/relay/relay%201")
    XCTAssertEqual(request.headers["Accept"], "application/json, text/plain")
    XCTAssertEqual(request.headers["Authorization"], "Bearer secret-token")
    XCTAssertEqual(request.body, #"{"enabled":true}"#)
    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(result.output["result"]?.objectValue?["state"], .string("on"))
    XCTAssertEqual(result.output["http_status"], .int(200))
    XCTAssertEqual(result.metadata["transport"], .string("declarative_http"))
    XCTAssertEqual(stored.state, .connected)
    XCTAssertEqual(stored.toolIds, ["relay.switch"])
  }

  func testAgentMcpDeclarativeHTTPClientRejectsEscapedTargetAndMarksFailure() async throws {
    let root = try temporaryDirectory("mcp-declarative-http-escaped")
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = AgentMcpPackageRepository(rootDirectory: root)
    let manifest = mcpDeclarativePackageManifest().replacingOccurrences(
      of: #""path": "/api/relay/{{args.device_id}}""#,
      with: #""path": "//evil.example/{{args.device_id}}""#
    )
    let inspection = try AgentMcpPackageInstaller().inspect(storedMcpPackage(
      ("mcp.json", manifest)
    ))
    try repository.save(inspection)
    let registry = AgentMcpRegistry(InMemoryAgentMcpStore(), nowMillis: { 10_000 })
    let installed = try registry.installPackage(inspection.manifest, packageSha256: inspection.packageSha256)
    _ = try registry.beginAuthentication(installed.id)
    let authenticated = try registry.submitAuthenticationStep(
      installed.id,
      values: [
        "username": "alice",
        "password": "pw",
        "access_token": "secret-token"
      ]
    )
    let transport = FakeMcpDeclarativeHTTPTransport([])
    let client = AgentMcpDeclarativeHTTPClient(
      registry: registry,
      packageRepository: repository,
      transport: transport,
      nowMillis: { 10_000 }
    )

    do {
      _ = try await client.callTool(
        connection: authenticated,
        toolName: "relay.switch",
        arguments: ["device_id": .string("relay-1")]
      )
      XCTFail("Expected escaped declarative MCP target to be rejected")
    } catch {
      let stored = try XCTUnwrap(registry.get(installed.id))
      XCTAssertEqual(transport.requests.count, 0)
      XCTAssertEqual(stored.state, .error)
      XCTAssertTrue(stored.lastError.contains("configured server"))
    }
  }

  func testAgentMcpDeclarativeHTTPClientMarksAuthenticationFailureOnHttp401() async throws {
    let root = try temporaryDirectory("mcp-declarative-http-401")
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = AgentMcpPackageRepository(rootDirectory: root)
    let inspection = try AgentMcpPackageInstaller().inspect(storedMcpPackage(
      ("mcp.json", mcpDeclarativePackageManifest())
    ))
    try repository.save(inspection)
    let registry = AgentMcpRegistry(InMemoryAgentMcpStore(), nowMillis: { 10_000 })
    let installed = try registry.installPackage(inspection.manifest, packageSha256: inspection.packageSha256)
    _ = try registry.beginAuthentication(installed.id)
    let authenticated = try registry.submitAuthenticationStep(
      installed.id,
      values: [
        "username": "alice",
        "password": "pw",
        "access_token": "secret-token"
      ]
    )
    let transport = FakeMcpDeclarativeHTTPTransport([
      AgentMcpDeclarativeHTTPResponse(statusCode: 401, body: #"{"error":"expired"}"#)
    ])
    let client = AgentMcpDeclarativeHTTPClient(
      registry: registry,
      packageRepository: repository,
      transport: transport,
      nowMillis: { 10_000 }
    )

    do {
      _ = try await client.callTool(
        connection: authenticated,
        toolName: "relay.switch",
        arguments: [
          "device_id": .string("relay-1"),
          "enabled": .bool(true)
        ]
      )
      XCTFail("Expected HTTP 401 to require MCP reauthentication")
    } catch {
      let stored = try XCTUnwrap(registry.get(installed.id))
      XCTAssertEqual(transport.requests.count, 1)
      XCTAssertEqual(stored.state, .needsSetup)
      XCTAssertEqual(stored.authState, .reauthenticationRequired)
      XCTAssertEqual(stored.lastError, "MCP authentication expired")
    }
  }

  func testAgentCapabilityDependencyResolverAndEndpointPolicyMatchAndroid() throws {
    let skill = AgentDefaultCapabilityCatalog.skill("galaxyssi.catalog.github-triage")!
    let registry = AgentMcpRegistry(InMemoryAgentMcpStore(), nowMillis: { 1_000 })
    let missing = AgentCapabilityDependencyResolver.resolve(
      skill,
      installedMcp: registry.list(),
      nativeToolIds: [AgentMcpNativeTools.callTool],
      nowMillis: 1_000
    )
    XCTAssertFalse(missing.available)
    XCTAssertEqual(missing.missingMcpCatalogIds, ["galaxyssi.mcp.github"])

    _ = try registry.addRemote(
      displayName: "GitHub",
      endpoint: "https://api.githubcopilot.com/mcp/",
      authProfile: try AgentMcpAuthProfile(.none),
      catalogId: "galaxyssi.mcp.github",
      id: "github"
    )
    let ready = AgentCapabilityDependencyResolver.resolve(
      skill,
      installedMcp: registry.list(),
      nativeToolIds: [AgentMcpNativeTools.callTool],
      nowMillis: 1_000
    )
    XCTAssertTrue(ready.available)

    XCTAssertEqual(try AgentMcpEndpointPolicy.normalize(" https://example.com/mcp "), "https://example.com/mcp")
    XCTAssertThrowsError(try AgentMcpEndpointPolicy.normalize("https://user:password@example.com/mcp"))
    XCTAssertThrowsError(try AgentMcpEndpointPolicy.normalize("file:///tmp/server"))
  }

}
