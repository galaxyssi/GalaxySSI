import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
  func testTransportBackedAgentAdapterNegotiatesStartsAndReplaysIdempotentRuns() async throws {
    let registration = controlPlaneRegistration()
    let transport = FakeAgentAdapterTransport(registration: registration)
    let receipts = InMemoryAgentRunStartReceiptStore(clock: { 1_000 })
    let adapter = TransportBackedAgentAdapter(
      initialRegistration: registration,
      transport: transport,
      runStartReceipts: receipts
    )
    let request = controlPlaneRunRequest()

    let first = try await adapter.startRun(request)
    let replay = try await adapter.startRun(request)
    let status = try await adapter.status()
    let recovered = try await adapter.recoverRuns()

    XCTAssertEqual(first, replay)
    XCTAssertEqual(first.agentId, "codex")
    XCTAssertEqual(transport.openCount, 1)
    XCTAssertEqual(transport.startedRequests.count, 1)
    XCTAssertEqual(status.agentId, "codex")
    XCTAssertTrue(recovered.isEmpty)
    XCTAssertEqual(receipts.list().first?.status, .accepted)
  }

  func testTransportBackedAgentAdapterBlocksIncompatibleObserveAndIgnoreBypass() async throws {
    let incompatibleTransport = FakeAgentAdapterTransport(
      registration: controlPlaneRegistration(),
      remoteProtocol: AgentProtocolRange(preferred: "2.0", minimum: "2.0", maximum: "2.1")
    )
    let incompatible = TransportBackedAgentAdapter(
      initialRegistration: controlPlaneRegistration(),
      transport: incompatibleTransport
    )

    do {
      _ = try await incompatible.startRun(controlPlaneRunRequest(runId: "bad", idempotencyKey: "bad"))
      XCTFail("Expected incompatible protocol to fail")
    } catch {
      XCTAssertTrue(String(describing: error).contains("compatible"))
    }

    XCTAssertEqual(incompatibleTransport.openCount, 1)
    XCTAssertEqual(incompatibleTransport.closeCount, 1)
    XCTAssertTrue(incompatibleTransport.startedRequests.isEmpty)

    let ignoreTransport = FakeAgentAdapterTransport(registration: controlPlaneRegistration())
    let ignore = TransportBackedAgentAdapter(
      initialRegistration: controlPlaneRegistration(),
      transport: ignoreTransport
    )
    let ignored = try await ignore.startRun(
      controlPlaneRunRequest(runId: "ignored", deliveryMode: .ignore, idempotencyKey: "ignored")
    )

    XCTAssertEqual(ignored.remoteRunId, "")
    XCTAssertEqual(ignoreTransport.openCount, 0)
    XCTAssertTrue(ignoreTransport.startedRequests.isEmpty)

    try await ignore.sendMessage(
      runId: "ignored",
      message: AgentControlMessage(messageId: "m", role: "assistant", text: "skip", deliveryMode: .ignore)
    )
    XCTAssertEqual(ignoreTransport.openCount, 1)
    XCTAssertTrue(ignoreTransport.sentMessages.isEmpty)

    let noObserve = FakeAgentAdapterTransport(
      registration: controlPlaneRegistration(features: ["run.cancel", "run.recover"])
    )
    let observer = TransportBackedAgentAdapter(
      initialRegistration: controlPlaneRegistration(features: ["run.cancel", "run.recover"]),
      transport: noObserve
    )
    do {
      _ = try await observer.startRun(
        controlPlaneRunRequest(runId: "observe", deliveryMode: .observe, idempotencyKey: "observe")
      )
      XCTFail("Expected missing message.observe feature to fail")
    } catch {
      XCTAssertTrue(String(describing: error).contains("message.observe"))
    }
    XCTAssertTrue(noObserve.startedRequests.isEmpty)
  }

  func testTransportBackedAgentProviderFiltersRegistrationsAndBuildsAdapters() async throws {
    let hermes = controlPlaneRegistration(
      agentId: "hermes",
      providerId: "remote-provider",
      displayName: "Hermes",
      capabilities: [.chat, .research, .liveData]
    )
    let other = controlPlaneRegistration(
      agentId: "other",
      providerId: "other-provider",
      displayName: "Other"
    )
    let hermesTransport = FakeAgentAdapterTransport(registration: hermes)
    let providerTransport = FakeAgentProviderTransport(
      remoteProtocol: hermes.`protocol`,
      registrations: [hermes, other],
      adapters: ["hermes": hermesTransport]
    )
    let provider = TransportBackedAgentProvider(
      providerId: "remote-provider",
      transport: providerTransport,
      localProtocol: hermes.`protocol`
    )

    let registrations = try await provider.registrations()
    let adapter = try await provider.adapter(agentId: "hermes")
    let handle = try await adapter?.startRun(controlPlaneRunRequest(runId: "remote", idempotencyKey: "remote"))

    XCTAssertEqual(registrations.map(\.agentId), ["hermes"])
    XCTAssertEqual(providerTransport.openCount, 1)
    XCTAssertEqual(handle?.agentId, "hermes")
    XCTAssertEqual(hermesTransport.startedRequests.count, 1)
  }

  func testAgentAdapterDirectoryResolvesSearchesAndCachesProviderAdapters() async throws {
    let codex = controlPlaneRegistration()
    let hermes = controlPlaneRegistration(
      agentId: "hermes",
      providerId: "remote-provider",
      displayName: "Hermes",
      capabilities: [.chat, .research, .liveData]
    )
    let directory = AgentAdapterDirectory()
    let codexTransport = FakeAgentAdapterTransport(registration: codex)
    let hermesTransport = FakeAgentAdapterTransport(registration: hermes)
    let provider = TransportBackedAgentProvider(
      providerId: "remote-provider",
      transport: FakeAgentProviderTransport(
        remoteProtocol: hermes.`protocol`,
        registrations: [hermes],
        adapters: ["hermes": hermesTransport]
      ),
      localProtocol: hermes.`protocol`
    )

    try directory.register(TransportBackedAgentAdapter(initialRegistration: codex, transport: codexTransport))
    try directory.register(provider)

    let resolved = try await directory.resolveAdapter("hermes")
    let cached = directory.adapter("hermes")
    let registrations = try await directory.registrations()
    let search = try await directory.searchAgents(AgentNetworkSearchQuery(text: "Hermes", routableOnly: false))

    XCTAssertNotNil(resolved)
    XCTAssertTrue(cached === resolved)
    XCTAssertEqual(registrations.map(\.agentId), ["codex", "hermes"])
    XCTAssertEqual(search.hits.map { $0.registration.agentId }, ["hermes"])
  }

  func testAgentTeamCoordinatorStartsRespondingAndObservingMembers() async throws {
    let codex = controlPlaneRegistration(capabilities: [.chat, .code, .taskExecution])
    let tester = controlPlaneRegistration(
      agentId: "tester",
      installationId: "tester-install",
      providerId: "tester-provider",
      displayName: "Tester",
      capabilities: [.chat, .research]
    )
    let codexTransport = FakeAgentAdapterTransport(registration: codex)
    let testerTransport = FakeAgentAdapterTransport(registration: tester)
    let directory = AgentAdapterDirectory()
    try directory.register(TransportBackedAgentAdapter(initialRegistration: codex, transport: codexTransport))
    try directory.register(TransportBackedAgentAdapter(initialRegistration: tester, transport: testerTransport))

    let run = try await AgentTeamCoordinator(directory: directory).start(
      definition: AgentTeamDefinition(
        teamId: "team",
        primaryAgentId: "codex",
        members: [
          AgentTeamMember(
            agentId: "codex",
            deliveryMode: .respond,
            requiredCapabilities: [.code],
            role: "lead",
            objective: "Implement",
            dependsOnAgentIds: [],
            context: [:]
          ),
          AgentTeamMember(
            agentId: "tester",
            deliveryMode: .observe,
            requiredCapabilities: [.research],
            role: "verifier",
            objective: "Review",
            dependsOnAgentIds: ["codex"],
            context: [:]
          ),
          AgentTeamMember(
            agentId: "ignored",
            deliveryMode: .ignore,
            requiredCapabilities: [],
            role: "silent",
            objective: "",
            dependsOnAgentIds: [],
            context: [:]
          )
        ],
        visibilityMode: .visible,
        collectiveCapabilities: []
      ),
      request: controlPlaneRunRequest(requiredCapabilities: [.chat])
    )

    XCTAssertEqual(Set(run.memberRuns.keys), Set(["codex", "tester"]))
    XCTAssertEqual(run.primaryRun.agentId, "codex")
    XCTAssertEqual(run.visibilityMode, .visible)
    XCTAssertTrue(run.unavailableMembers.isEmpty)
    XCTAssertEqual(codexTransport.startedRequests.count, 1)
    XCTAssertEqual(testerTransport.startedRequests.count, 1)
    XCTAssertEqual(testerTransport.startedRequests.first?.deliveryMode, .observe)
    XCTAssertEqual(testerTransport.startedRequests.first?.parentRunId, run.primaryRun.runId)
    XCTAssertEqual(testerTransport.startedRequests.first?.idempotencyKey, "key:tester")
  }

  func controlPlaneRegistration(
    agentId: String = "codex",
    installationId: String = "installation",
    providerId: String = "desktop-provider",
    displayName: String = "Codex",
    capabilities: Set<AgentCapability> = [.chat, .code],
    features: Set<String> = ["run.cancel", "run.recover", "message.observe"]
  ) -> AgentRegistration {
    AgentRegistration(
      agentId: agentId,
      installationId: installationId,
      deviceId: installationId,
      providerId: providerId,
      displayName: displayName,
      kind: .agent,
      location: .trustedDesktop,
      status: .online,
      capabilities: capabilities,
      protocol: AgentProtocolRange(preferred: "1.1", minimum: "1.0", maximum: "1.1", features: features),
      connectionKind: .galaxyssiLink,
      trust: .verifiedPaired
    )
  }

  func controlPlaneRunRequest(
    runId: String = "run",
    deliveryMode: AgentDeliveryMode = .respond,
    requiredCapabilities: Set<AgentCapability> = [.chat],
    idempotencyKey: String = "key"
  ) -> AgentRunRequest {
    AgentRunRequest(
      conversationId: "conversation",
      messageId: "message",
      taskId: "task",
      runId: runId,
      parentRunId: "",
      goal: "Implement and review",
      deliveryMode: deliveryMode,
      requiredCapabilities: requiredCapabilities,
      context: [:],
      idempotencyKey: idempotencyKey,
      createdAtMillis: 1_000
    )
  }
}

private final class FakeAgentAdapterTransport: AgentAdapterTransport {
  private let registrationValue: AgentRegistration
  private let remoteProtocol: AgentProtocolRange
  private let recoveredRuns: [AgentRecoverableRun]
  var openCount = 0
  var closeCount = 0
  var startedRequests: [AgentRunRequest] = []
  var sentMessages: [AgentControlMessage] = []
  var cancelledRunIds: [String] = []

  init(
    registration: AgentRegistration,
    remoteProtocol: AgentProtocolRange? = nil,
    recoveredRuns: [AgentRecoverableRun] = []
  ) {
    self.registrationValue = registration
    self.remoteProtocol = remoteProtocol ?? registration.`protocol`
    self.recoveredRuns = recoveredRuns
  }

  func open() async throws -> AgentProtocolRange {
    openCount += 1
    return remoteProtocol
  }

  func close() async {
    closeCount += 1
  }

  func status() async throws -> AgentRegistration {
    registrationValue
  }

  func startRun(_ request: AgentRunRequest) async throws -> AgentRunHandle {
    startedRequests.append(request)
    return AgentRunHandle(
      runId: request.runId,
      taskId: request.taskId,
      agentId: registrationValue.agentId,
      remoteRunId: request.runId,
      acceptedAtMillis: 2_000
    )
  }

  func sendMessage(runId: String, message: AgentControlMessage) async throws {
    sentMessages.append(message)
  }

  func cancelRun(runId: String) async throws {
    cancelledRunIds.append(runId)
  }

  func observeEvents(runId: String) -> AsyncStream<AgentRunControlEvent> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }

  func recoverRuns() async throws -> [AgentRecoverableRun] {
    recoveredRuns
  }
}

private final class FakeAgentProviderTransport: AgentProviderTransport {
  private let remoteProtocol: AgentProtocolRange
  private let registrationValues: [AgentRegistration]
  private let adapters: [String: FakeAgentAdapterTransport]
  var openCount = 0

  init(
    remoteProtocol: AgentProtocolRange,
    registrations: [AgentRegistration],
    adapters: [String: FakeAgentAdapterTransport]
  ) {
    self.remoteProtocol = remoteProtocol
    self.registrationValues = registrations
    self.adapters = adapters
  }

  func open() async throws -> AgentProtocolRange {
    openCount += 1
    return remoteProtocol
  }

  func close() async {}

  func registrations() async throws -> [AgentRegistration] {
    registrationValues
  }

  func adapterTransport(agentId: String) async throws -> (AgentRegistration, AgentAdapterTransport)? {
    guard let transport = adapters[agentId],
      let registration = registrationValues.first(where: { $0.agentId == agentId }) else {
      return nil
    }
    return (registration, transport)
  }

  func recoverRuns() async throws -> [AgentRecoverableRun] {
    []
  }
}
