import XCTest
@testable import GalaxySSI

final class TestAgentActionExecutor: AgentActionExecutor {
  var callCount = 0
  private let handler: (AgentAction, AgentScreenContext) -> AgentActionResult

  init(_ handler: @escaping (AgentAction, AgentScreenContext) -> AgentActionResult) {
    self.handler = handler
  }

  func execute(action: AgentAction, screen: AgentScreenContext) -> AgentActionResult {
    callCount += 1
    return handler(action, screen)
  }
}

final class FakeMcpLocalRuntimeExecutor: AgentMcpLocalRuntimeExecuting {
  var requests: [AgentMcpLocalRuntimeExecutionRequest] = []
  private var responses: [AgentMcpLocalRuntimeExecutionResponse]

  init(_ responses: [AgentMcpLocalRuntimeExecutionResponse]) {
    self.responses = responses
  }

  func execute(_ request: AgentMcpLocalRuntimeExecutionRequest) throws -> AgentMcpLocalRuntimeExecutionResponse {
    requests.append(request)
    guard !responses.isEmpty else {
      throw AgentRuntimeCapabilityError.invalid("No fake MCP runtime response is queued")
    }
    return responses.removeFirst()
  }
}

final class FakeMcpDeclarativeHTTPTransport: AgentMcpDeclarativeHTTPTransport {
  var requests: [AgentMcpDeclarativeHTTPRequest] = []
  private var responses: [AgentMcpDeclarativeHTTPResponse]

  init(_ responses: [AgentMcpDeclarativeHTTPResponse]) {
    self.responses = responses
  }

  func execute(_ request: AgentMcpDeclarativeHTTPRequest) async throws -> AgentMcpDeclarativeHTTPResponse {
    requests.append(request)
    guard !responses.isEmpty else {
      throw AgentRuntimeCapabilityError.invalid("No fake MCP HTTP response is queued")
    }
    return responses.removeFirst()
  }
}

final class FakeMcpStreamableHTTPNetworking: AgentMcpStreamableHTTPNetworking {
  var requests: [AgentMcpStreamableHTTPRequest] = []
  private var responses: [AgentMcpStreamableHTTPResponse]

  init(_ responses: [AgentMcpStreamableHTTPResponse]) {
    self.responses = responses
  }

  func post(_ request: AgentMcpStreamableHTTPRequest) async throws -> AgentMcpStreamableHTTPResponse {
    requests.append(request)
    guard !responses.isEmpty else {
      throw AgentRuntimeCapabilityError.invalid("No fake MCP streamable HTTP response is queued")
    }
    return responses.removeFirst()
  }
}

final class TestMcpRemoteSessionListener: AgentMcpRemoteSessionListener {
  var notifications: [AgentMcpNotification] = []
  var issues: [AgentMcpRemoteSessionError] = []

  func onNotification(_ notification: AgentMcpNotification) {
    notifications.append(notification)
  }

  func onProtocolIssue(_ error: AgentMcpRemoteSessionError) {
    issues.append(error)
  }
}

extension AgentRuntimePackCatalogEntry {
  func with(
    version: String? = nil,
    downloadUrl: String? = nil,
    minimumHostVersionCode: Int64? = nil,
    guestApiVersion: Int? = nil
  ) -> AgentRuntimePackCatalogEntry {
    var copy = self
    if let version {
      copy.version = version
    }
    if let downloadUrl {
      copy.downloadUrl = downloadUrl
    }
    if let minimumHostVersionCode {
      copy.minimumHostVersionCode = minimumHostVersionCode
    }
    if let guestApiVersion {
      copy.guestApiVersion = guestApiVersion
    }
    return copy
  }
}

@MainActor
final class GalaxySSIStoreTests: XCTestCase {
  func testSystemNotificationViewportStartsAtTopAndDoesNotFollowUpdates() {
    XCTAssertEqual(
      GalaxySSIChatMessageViewportPolicy.initialPosition(systemNotifications: true),
      .first
    )
    XCTAssertFalse(
      GalaxySSIChatMessageViewportPolicy.followsLatest(systemNotifications: true)
    )
    XCTAssertEqual(
      GalaxySSIChatMessageViewportPolicy.initialPosition(systemNotifications: false),
      .last
    )
    XCTAssertTrue(
      GalaxySSIChatMessageViewportPolicy.followsLatest(systemNotifications: false)
    )
  }

  func testConversationHubBackReturnsNestedListsBeforeDismissing() {
    XCTAssertEqual(
      GalaxySSIConversationHubBackPolicy.action(
        searchExpanded: true,
        tab: .contacts,
        archived: true
      ),
      .closeSearch
    )
    XCTAssertEqual(
      GalaxySSIConversationHubBackPolicy.action(
        searchExpanded: false,
        tab: .contacts,
        archived: false
      ),
      .showConversations
    )
    XCTAssertEqual(
      GalaxySSIConversationHubBackPolicy.action(
        searchExpanded: false,
        tab: .conversations,
        archived: false
      ),
      .dismiss
    )
  }

  func testConversationHubScrollPolicyChoosesNearestVisibleStableRow() {
    XCTAssertEqual(
      "conversation:agent:1",
      GalaxySSIConversationHubScrollPolicy.anchorId(positions: [
        "conversation:agent:1": -18,
        "conversation:agent:2": 6,
        "conversation:agent:3": 72
      ])
    )
    XCTAssertEqual(
      "conversation:agent:1",
      GalaxySSIConversationHubScrollPolicy.anchorId(positions: [
        "conversation:agent:1": -4,
        "conversation:agent:0": -48
      ])
    )
  }

  func testConversationHubScrollPolicyRestoresAgentIdentityAndPixelOffset() {
    XCTAssertEqual(
      GalaxySSIConversationHubScrollPolicy.agentConversationId(
        from: "conversation:agent:conversation-500"
      ),
      "conversation-500"
    )
    XCTAssertNil(
      GalaxySSIConversationHubScrollPolicy.agentConversationId(
        from: "conversation:contact:contact-500"
      )
    )
    XCTAssertEqual(
      GalaxySSIConversationHubScrollPolicy.restoredContentOffsetY(
        alignedContentOffsetY: 4_000,
        savedRowOffset: -164,
        minimumContentOffsetY: 0,
        maximumContentOffsetY: 8_000
      ),
      4_164
    )
    XCTAssertEqual(
      GalaxySSIConversationHubScrollPolicy.restoredContentOffsetY(
        alignedContentOffsetY: 20,
        savedRowOffset: 37,
        minimumContentOffsetY: 0,
        maximumContentOffsetY: 8_000
      ),
      0
    )
  }

  func testVisibleConversationTrackerSuppressesOnlyActiveMatchingConversation() {
    let tracker = GalaxySSIVisibleConversationTracker()
    let firstToken = UUID()
    let secondToken = UUID()
    tracker.markVisible(contactId: "contact-a", token: firstToken)
    tracker.markVisible(contactId: "contact-b", token: secondToken)

    XCTAssertFalse(tracker.shouldNotify(contactId: "contact-a", applicationIsActive: true))
    XCTAssertFalse(tracker.shouldNotify(contactId: "contact-b", applicationIsActive: true))
    XCTAssertTrue(tracker.shouldNotify(contactId: "contact-c", applicationIsActive: true))
    XCTAssertTrue(tracker.shouldNotify(contactId: "contact-a", applicationIsActive: false))

    tracker.markHidden(token: firstToken)
    XCTAssertTrue(tracker.shouldNotify(contactId: "contact-a", applicationIsActive: true))
    XCTAssertFalse(tracker.shouldNotify(contactId: "contact-b", applicationIsActive: true))
  }

  func testForegroundNotificationPresentationRestoresVisibleConversationSuppression() {
    let tracker = GalaxySSIVisibleConversationTracker()
    let token = UUID()
    let userInfo: [AnyHashable: Any] = [
      GalaxySSIContactNotificationPresentationPolicy.contactIdKey: "contact-a"
    ]
    tracker.markVisible(contactId: "contact-a", token: token)

    XCTAssertTrue(GalaxySSIContactNotificationPresentationPolicy.shouldPresent(
      userInfo: userInfo,
      applicationIsActive: false,
      tracker: tracker
    ))
    XCTAssertFalse(GalaxySSIContactNotificationPresentationPolicy.shouldPresent(
      userInfo: userInfo,
      applicationIsActive: true,
      tracker: tracker
    ))
    XCTAssertTrue(GalaxySSIContactNotificationPresentationPolicy.shouldPresent(
      userInfo: [:],
      applicationIsActive: true,
      tracker: tracker
    ))
  }

  func testIncomingMessageNotificationIdentifierIsStablePerContact() {
    XCTAssertEqual(
      NotificationService.incomingMessageIdentifier(contactId: " phone "),
      NotificationService.incomingMessageIdentifier(contactId: "phone")
    )
    XCTAssertNotEqual(
      NotificationService.incomingMessageIdentifier(contactId: "phone"),
      NotificationService.incomingMessageIdentifier(contactId: "desktop")
    )
  }

  func testAgentRuntimeNotificationPolicySuppressesAuthenticatedForegroundFinals() {
    let final: [String: Any] = [
      "type": "text",
      "source_message_id": 42,
      "conversation_id": "conversation",
      "turn_id": "turn",
      "task_id": "task"
    ]

    XCTAssertFalse(AgentRuntimeNotificationPolicy.shouldNotify(
      payload: final,
      applicationIsActive: true
    ))
    XCTAssertTrue(AgentRuntimeNotificationPolicy.shouldNotify(
      payload: final,
      applicationIsActive: false
    ))
    XCTAssertFalse(AgentRuntimeNotificationPolicy.shouldNotify(
      payload: ["type": "agent_task_event"],
      applicationIsActive: true
    ))
    XCTAssertTrue(AgentRuntimeNotificationPolicy.shouldNotify(
      payload: ["type": "text", "source_message_id": 42, "contact_id": "peer"],
      applicationIsActive: true
    ))
  }

  func testInitialStoreContainsAndroidParityContacts() {
    let store = makeStore()

    XCTAssertNotNil(store.contact(id: "hermes"))
    XCTAssertEqual(store.contact(id: "system")?.trustState, .verified)
    XCTAssertTrue(store.profile.identityFingerprint.count == 64)
  }

  func testAddServerLinkCreatesAndroidParityDesktopAgents() throws {
    let store = makeStore()

    let link = try store.addServerLink(from: makePairingQRCode())

    XCTAssertNotNil(store.contact(id: "\(link.desktopId):codex"))
    XCTAssertNotNil(store.contact(id: "\(link.desktopId):claude"))
    XCTAssertEqual(store.contact(id: "\(link.desktopId):local-llm")?.agentKind, "local-model")
    XCTAssertEqual(store.contact(id: "\(link.desktopId):codex")?.trustState, .unverified)

    store.markServerPaired(desktopId: link.desktopId)

    XCTAssertEqual(store.contact(id: "\(link.desktopId):codex")?.trustState, .verified)
    XCTAssertEqual(store.contact(id: "\(link.desktopId):codex")?.setupStatus, "ready")
  }

  func testServerLinkTracksAndroidCapabilityManifestVersion() throws {
    let store = makeStore()

    let link = try store.addServerLink(from: makePairingQRCode())

    XCTAssertEqual(GalaxySSILinkProtocol.capabilityManifestVersion, 2)
    XCTAssertEqual(link.capabilityManifestVersion, 0)
    XCTAssertTrue(GalaxySSILinkProtocol.needsCapabilityManifest(link))

    let updated = try XCTUnwrap(store.markCapabilityManifestReceived(
      desktopId: link.desktopId,
      version: GalaxySSILinkProtocol.capabilityManifestVersion
    ))
    XCTAssertEqual(updated.capabilityManifestVersion, 2)
    XCTAssertFalse(GalaxySSILinkProtocol.needsCapabilityManifest(updated))

    let retained = try XCTUnwrap(store.markCapabilityManifestReceived(desktopId: link.desktopId, version: 1))
    XCTAssertEqual(retained.capabilityManifestVersion, 2)

    let rescanned = try store.addServerLink(from: makePairingQRCode(), rotateClientRoute: false)
    XCTAssertEqual(rescanned.capabilityManifestVersion, 2)
  }

  func testServerLinkDecodesLegacyPayloadWithoutCapabilityManifestVersion() throws {
    let link = ServerLink(
      desktopId: "desktop-legacy",
      desktopName: "Desktop",
      desktopFingerprint: String(repeating: "c", count: 64),
      signalName: "desktop-legacy",
      routes: GalaxySSILinkRoutes(
        clientRouteId: "zyxwvutsrqponmlkjihgfe",
        linkSecret: Data(repeating: 7, count: 32).base64URLEncodedString(),
        localFingerprint: String(repeating: "a", count: 64),
        remoteFingerprint: String(repeating: "c", count: 64)
      ),
      paired: true,
      accessProfile: GalaxySSILinkProtocol.accessRestricted,
      accessScopes: [GalaxySSILinkProtocol.scopeAgentChat],
      capabilityManifestVersion: 2,
      updatedAt: Date(timeIntervalSince1970: 1)
    )
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder.galaxySSI.encode(link)) as? [String: Any])
    object.removeValue(forKey: "capability_manifest_version")
    let legacyData = try JSONSerialization.data(withJSONObject: object)

    let decoded = try JSONDecoder.galaxySSI.decode(ServerLink.self, from: legacyData)

    XCTAssertEqual(decoded.desktopId, "desktop-legacy")
    XCTAssertEqual(decoded.capabilityManifestVersion, 0)
    XCTAssertTrue(GalaxySSILinkProtocol.needsCapabilityManifest(decoded))
  }

  func testConnectorStatusRequestPayloadMatchesAndroidCapabilityManifestWireKeys() throws {
    let store = makeStore()
    let link = try store.addServerLink(from: makePairingQRCode())
    let stalePayload = GalaxySSILinkProtocol.connectorStatusRequestPayload(
      link: link,
      now: Date(timeIntervalSince1970: 10)
    )
    let current = try XCTUnwrap(store.markCapabilityManifestReceived(
      desktopId: link.desktopId,
      version: GalaxySSILinkProtocol.capabilityManifestVersion
    ))
    let currentPayload = GalaxySSILinkProtocol.connectorStatusRequestPayload(
      link: current,
      now: Date(timeIntervalSince1970: 11)
    )
    let forcedPayload = GalaxySSILinkProtocol.connectorStatusRequestPayload(
      link: current,
      forceCapabilityManifest: true,
      now: Date(timeIntervalSince1970: 12)
    )

    XCTAssertEqual(stalePayload["type"] as? String, "connector_status_request")
    XCTAssertEqual(stalePayload["contact_id"] as? String, "system")
    XCTAssertEqual(stalePayload["desktop_id"] as? String, link.desktopId)
    XCTAssertEqual(stalePayload["capability_manifest_version"] as? Int, 0)
    XCTAssertEqual(stalePayload["request_capability_manifest"] as? Bool, true)
    XCTAssertEqual(stalePayload["time"] as? Int64, 10_000)
    XCTAssertEqual(currentPayload["capability_manifest_version"] as? Int, 2)
    XCTAssertEqual(currentPayload["request_capability_manifest"] as? Bool, false)
    XCTAssertEqual(forcedPayload["request_capability_manifest"] as? Bool, true)
  }

  func testContactSearchMatchesAndroidNameAndIdFiltering() throws {
    let store = makeStore()
    let request = store.addFriendRequest(makeFriendRequest(galaxySSIId: "friend-alice", name: "Alice"))
    XCTAssertTrue(store.approveFriendRequest(id: request.id))
    _ = try store.addCloudModelContact(
      displayName: "Model A",
      provider: "OpenAI",
      modelId: "gpt-5",
      endpoint: "https://api.example.com/v1/chat/completions",
      apiKey: "key-a",
      apiStyle: .openAICompatible
    )

    XCTAssertEqual(store.visibleContacts(matching: "alice").map(\.id), ["friend-alice"])
    XCTAssertEqual(store.visibleContacts(matching: "cloud:openai").map(\.id), ["cloud:openai"])
    XCTAssertEqual(store.contactList(matching: "gpt-5").map(\.id), ["cloud:openai"])
    XCTAssertTrue(store.visibleContacts(matching: "missing-contact").isEmpty)
  }

  func testOutgoingPendingFriendRequestRemainsVisibleWhileWaiting() {
    var request = makeFriendRequest(galaxySSIId: "friend-waiting", name: "Waiting")
    request.direction = .outgoing
    request.status = .pending

    XCTAssertTrue(GalaxySSIFriendRequestPresentationPolicy.isVisible(request, contactIsVerified: false))
    XCTAssertFalse(GalaxySSIFriendRequestPresentationPolicy.isAdded(request, contactIsVerified: false))
  }

  func testOutgoingApprovedFriendRequestRemainsVisibleAsAdded() {
    var request = makeFriendRequest(galaxySSIId: "friend-added", name: "Added")
    request.direction = .outgoing
    request.status = .approved

    XCTAssertTrue(GalaxySSIFriendRequestPresentationPolicy.isVisible(request, contactIsVerified: true))
    XCTAssertTrue(GalaxySSIFriendRequestPresentationPolicy.isAdded(request, contactIsVerified: true))
  }

  func testVerifiedContactRepairsStaleOutgoingPendingPresentation() {
    var request = makeFriendRequest(galaxySSIId: "friend-stale", name: "Stale")
    request.direction = .outgoing
    request.status = .pending

    XCTAssertTrue(GalaxySSIFriendRequestPresentationPolicy.isAdded(request, contactIsVerified: true))
  }

  func testCompletedIncomingFriendRequestLivesOnlyInContacts() {
    var request = makeFriendRequest(galaxySSIId: "friend-incoming", name: "Incoming")
    request.direction = .incoming
    request.status = .approved

    XCTAssertFalse(GalaxySSIFriendRequestPresentationPolicy.isVisible(request, contactIsVerified: true))
  }

  func testOnlyUnreadIncomingPendingFriendRequestsAreCounted() {
    var incomingUnread = makeFriendRequest(galaxySSIId: "incoming-unread", name: "Unread")
    incomingUnread.direction = .incoming
    incomingUnread.isRead = false
    var incomingRead = makeFriendRequest(galaxySSIId: "incoming-read", name: "Read")
    incomingRead.direction = .incoming
    incomingRead.isRead = true
    var outgoing = makeFriendRequest(galaxySSIId: "outgoing", name: "Outgoing")
    outgoing.direction = .outgoing
    outgoing.isRead = false
    var approved = makeFriendRequest(galaxySSIId: "approved", name: "Approved")
    approved.direction = .incoming
    approved.status = .approved

    XCTAssertEqual(
      GalaxySSIFriendRequestUnreadPolicy.unreadCount([
        incomingUnread,
        incomingRead,
        outgoing,
        approved
      ]),
      1
    )
  }

  func testOpeningNewFriendsMarksOnlyIncomingPendingRequestsRead() {
    let store = makeStore()
    var first = makeFriendRequest(galaxySSIId: "incoming-first", name: "First")
    first.direction = .incoming
    var second = makeFriendRequest(galaxySSIId: "incoming-second", name: "Second")
    second.direction = .incoming
    var outgoing = makeFriendRequest(galaxySSIId: "outgoing", name: "Outgoing")
    outgoing.direction = .outgoing
    let firstStored = store.addFriendRequest(first)
    let secondStored = store.addFriendRequest(second)
    let outgoingStored = store.addFriendRequest(outgoing)

    XCTAssertEqual(store.unreadFriendRequestCount, 2)
    XCTAssertEqual(store.markIncomingFriendRequestsRead(), 2)
    XCTAssertEqual(store.unreadFriendRequestCount, 0)
    XCTAssertEqual(store.friendRequest(id: firstStored.id)?.isRead, true)
    XCTAssertEqual(store.friendRequest(id: secondStored.id)?.isRead, true)
    XCTAssertEqual(store.friendRequest(id: outgoingStored.id)?.isRead, true)
  }

  func testDuplicatePendingFriendRequestKeepsReadStateAndNewIncomingStartsUnread() {
    var viewed = makeFriendRequest(galaxySSIId: "existing", name: "Existing")
    viewed.direction = .incoming
    viewed.status = .pending
    viewed.isRead = true

    XCTAssertTrue(
      GalaxySSIFriendRequestUnreadPolicy.isReadForPendingRequest(
        previous: viewed,
        direction: .incoming
      )
    )
    XCTAssertFalse(
      GalaxySSIFriendRequestUnreadPolicy.isReadForPendingRequest(
        previous: nil,
        direction: .incoming
      )
    )
    XCTAssertTrue(
      GalaxySSIFriendRequestUnreadPolicy.isReadForPendingRequest(
        previous: nil,
        direction: .outgoing
      )
    )
  }

  func testCloudModelContactsAreGroupedByProvider() throws {
    let store = makeStore()

    _ = try store.addCloudModelContact(
      displayName: "Model A",
      provider: "OpenAI",
      modelId: "model-a",
      endpoint: "https://api.example.com/v1/chat/completions",
      apiKey: "key-a",
      apiStyle: .openAICompatible
    )
    let contact = try store.addCloudModelContact(
      displayName: "Model B",
      provider: "OpenAI",
      modelId: "model-b",
      endpoint: "https://api.example.com/v1/chat/completions",
      apiKey: "key-b",
      apiStyle: .openAICompatible
    )

    XCTAssertEqual(contact.id, "cloud:openai")
    XCTAssertEqual(contact.cloudModels.count, 2)
    XCTAssertEqual(store.contacts.filter { $0.id == "cloud:openai" }.count, 1)
    XCTAssertEqual(store.apiKey(for: contact.cloudModels[1]), "key-b")
  }

  func testRenamesContactLocally() {
    let store = makeStore()
    let request = store.addFriendRequest(makeFriendRequest(galaxySSIId: "friend-alice", name: "Alice"))
    XCTAssertTrue(store.approveFriendRequest(id: request.id))

    XCTAssertTrue(store.renameContact(id: "friend-alice", displayName: "  Alice Remark  "))

    let contact = store.contact(id: "friend-alice")
    XCTAssertEqual(contact?.name, "Alice Remark")
    XCTAssertEqual(contact?.displayName, "Alice Remark")
  }

  func testDeleteContactSoftDeletesAndOptionallyRemovesMessages() {
    let store = makeStore()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let request = store.addFriendRequest(makeFriendRequest(galaxySSIId: "friend-bob", name: "Bob"))
    XCTAssertTrue(store.approveFriendRequest(id: request.id))
    store.appendOutgoing("hello", to: "friend-bob")

    XCTAssertTrue(store.deleteContact(id: "friend-bob", deleteMessages: true, now: now))

    let contact = store.contact(id: "friend-bob")
    XCTAssertEqual(contact?.deleted, true)
    XCTAssertEqual(contact?.trustState, .deleted)
    XCTAssertEqual(contact?.deletedAt, now)
    XCTAssertTrue(store.messages(for: "friend-bob").isEmpty)
    XCTAssertEqual(store.friendRequest(id: request.id)?.status, .deleted)
    XCTAssertEqual(store.friendRequest(id: request.id)?.readdRequired, true)
  }

  func testDeleteContactKeepsMessagesByDefault() {
    let store = makeStore()
    let request = store.addFriendRequest(makeFriendRequest(galaxySSIId: "friend-carol", name: "Carol"))
    XCTAssertTrue(store.approveFriendRequest(id: request.id))
    store.appendOutgoing("keep this history", to: "friend-carol")

    XCTAssertTrue(store.deleteContact(id: "friend-carol"))

    XCTAssertEqual(store.contact(id: "friend-carol")?.trustState, .deleted)
    XCTAssertEqual(store.messages(for: "friend-carol").map(\.content), ["keep this history"])
  }

  func testDeleteMessageRemovesOnlyTargetMessage() {
    let store = makeStore()
    let first = store.appendOutgoing("first", to: "hermes")
    let second = store.appendOutgoing("second", to: "hermes")

    XCTAssertTrue(store.deleteMessage(first.id, contactId: "hermes"))

    XCTAssertEqual(store.messages(for: "hermes").map(\.content), [
      "Pair GalaxySSI Desktop to start a trusted Link conversation.",
      "second"
    ])
    XCTAssertFalse(store.deleteMessage(first.id, contactId: "hermes"))
    XCTAssertEqual(store.messages(for: "hermes").last?.id, second.id)
  }

  func testDeleteChatHistoryKeepsContact() {
    let store = makeStore()
    store.appendOutgoing("hello", to: "hermes")
    XCTAssertTrue(store.setContactPinned("hermes", pinned: true))

    store.deleteMessages(for: "hermes")

    XCTAssertTrue(store.messages(for: "hermes").isEmpty)
    XCTAssertNotNil(store.contact(id: "hermes"))
    XCTAssertEqual(store.contact(id: "hermes")?.deleted, false)
    XCTAssertFalse(store.isContactPinned("hermes"))
  }

  func testPinnedContactConversationMovesOutOfRecent() {
    let updatedAt = Date(timeIntervalSince1970: 30)
    let sections = GalaxySSIConversationHubModels.unifiedConversations(
      agents: [],
      contacts: [
        GalaxySSIConversationHubContactSummary(
          contactId: "desktop-route",
          title: "T14 Desktop",
          preview: "Connected",
          updatedAt: updatedAt,
          pinned: true
        )
      ],
      query: "",
      archived: false
    )

    XCTAssertEqual(sections.pinned.map(\.title), ["T14 Desktop"])
    XCTAssertTrue(sections.recent.isEmpty)
  }

  func testContactConversationUnreadCountFlowsIntoHubItem() {
    let sections = GalaxySSIConversationHubModels.unifiedConversations(
      agents: [],
      contacts: [
        GalaxySSIConversationHubContactSummary(
          contactId: "desktop-route",
          title: "T14 Desktop",
          preview: "photo.jpg",
          updatedAt: Date(timeIntervalSince1970: 30),
          unreadCount: 3
        )
      ],
      query: "",
      archived: false
    )

    XCTAssertEqual(sections.recent.first?.unreadCount, 3)
  }

  func testSystemNoticeUsesSameConversationSummaryRuleAsRefreshedHub() throws {
    let store = makeStore()
    store.appendSystem("Background task completed", to: "system")
    let system = try XCTUnwrap(store.chatContacts.first { $0.id == "system" })

    let initial = GalaxySSIConversationHubModels.contactSummaries(
      contacts: store.chatContacts,
      summary: store.conversationSummary(for:),
      isPinned: store.isContactPinned
    )
    let refreshed = GalaxySSIConversationHubModels.contactSummaries(
      contacts: [system],
      summary: store.conversationSummary(for:),
      isPinned: store.isContactPinned
    )

    XCTAssertEqual(initial.first { $0.contactId == "system" }, refreshed.first)
    XCTAssertEqual(refreshed.first?.preview, "Background task completed")
  }

  func testConversationSummaryTracksUnreadMessagesAndReadState() {
    let store = makeStore()

    XCTAssertEqual(store.conversationSummary(for: "hermes").unreadCount, 0)

    store.appendIncoming("desktop reply", from: "hermes")
    store.appendSystem("local notice", to: "hermes")
    store.appendOutgoing("ack", to: "hermes")

    let summary = store.conversationSummary(for: "hermes")
    XCTAssertEqual(summary.lastMessage?.content, "ack")
    XCTAssertEqual(summary.unreadCount, 1)
    XCTAssertTrue(summary.hasUnreadMessages)

    XCTAssertEqual(store.markContactRead("hermes"), 1)
    XCTAssertEqual(store.conversationSummary(for: "hermes").unreadCount, 0)
    XCTAssertEqual(store.markContactRead("hermes"), 0)
  }

  func testRuntimePlaintextBoundaryRestoresEncryptedMessagesAndMergesBackgroundArrival() {
    let store = makeStore()
    _ = store.appendIncoming(
      "before background",
      from: "hermes",
      remoteMessageId: "remote-before"
    )

    store.clearRuntimePlaintextForBackground()

    XCTAssertTrue(store.messagesByContact.isEmpty)
    XCTAssertTrue(store.messages(for: "hermes").isEmpty)
    XCTAssertTrue(store.hasIncomingDuplicate(
      "before background",
      from: "hermes",
      remoteMessageId: "remote-before"
    ))
    _ = store.appendIncoming(
      "arrived in background",
      from: "hermes",
      remoteMessageId: "remote-background"
    )
    XCTAssertTrue(store.messagesByContact.isEmpty)

    XCTAssertTrue(store.restoreRuntimePlaintextAfterForeground())
    XCTAssertEqual(
      store.messages(for: "hermes").filter { !$0.isSystem }.map(\.content),
      ["before background", "arrived in background"]
    )
    XCTAssertFalse(store.restoreRuntimePlaintextAfterForeground())
  }

  func testLanguagePolicyNormalizesAndUpdatesVoiceLocale() {
    let store = makeStore()

    store.updateLanguagePolicy {
      $0.interfaceLanguage = "zh-CN"
      $0.responseLanguage = "en-US"
      $0.asrLanguage = "zh-HK"
      $0.ttsLanguage = "not-supported"
    }

    XCTAssertEqual(store.languagePolicy.interfaceLanguage, "zh-CN")
    XCTAssertEqual(store.languagePolicy.responseLanguage, "en-US")
    XCTAssertEqual(store.languagePolicy.asrLanguage, "zh-HK")
    XCTAssertEqual(store.languagePolicy.ttsLanguage, "auto")
    XCTAssertEqual(store.voiceSettings.preferredLocaleIdentifier, "zh_HK")
  }

  func testCloudSystemPromptUsesConfiguredResponseLanguage() {
    let prompt = CloudModelClient.systemPrompt(languagePolicy: LanguagePolicySettings(responseLanguage: "zh-CN"))

    XCTAssertTrue(prompt.contains("Reply in Simplified Chinese"))
  }

  func testCloudContextOverflowPolicyMatchesAndroidContextErrorDetection() {
    XCTAssertTrue(
      CloudContextOverflowPolicy.isContextOverflow(
        CloudHTTPFailure(statusCode: 400, responseBody: #"{"code":"context_length_exceeded"}"#)
      )
    )
    XCTAssertTrue(
      CloudContextOverflowPolicy.isContextOverflow(
        CloudHTTPFailure(statusCode: 413, responseBody: "Request too large")
      )
    )
    XCTAssertFalse(
      CloudContextOverflowPolicy.isContextOverflow(
        CloudHTTPFailure(statusCode: 401, responseBody: "Too many tokens in the supplied credential")
      )
    )
    XCTAssertFalse(
      CloudContextOverflowPolicy.isContextOverflow(
        CloudHTTPFailure(statusCode: 400, responseBody: "Unknown model")
      )
    )
  }

  func testCloudContextOverflowPolicyRetryWindowsShrinkByTokenCapacity() {
    XCTAssertEqual(
      CloudContextOverflowPolicy.retryWindows(configuredWindowTokens: 64_000),
      [64_000, 32_000, 16_000, 8_000]
    )
    XCTAssertEqual(
      CloudContextOverflowPolicy.retryWindows(configuredWindowTokens: 8_192),
      [8_192, 4_096]
    )
  }

  func testWakeWordPolicyMatchesAndroidStandaloneHelloOnly() {
    XCTAssertEqual(WakeWordPolicy.wakeWord, "hello")
    XCTAssertEqual(WakeWordPolicy.configuredWords, ["hello"])
    XCTAssertEqual(VoiceSettings.defaultWakeWords, WakeWordPolicy.configuredWords)

    ["hello", "Hello!", "please, hello now", "hello world"].forEach { transcript in
      XCTAssertTrue(WakeWordPolicy.matches(transcript), transcript)
    }

    [
      "GalaxySSI",
      "galaxy ssi",
      "hi",
      "wake up",
      "assistant",
      "\u{4f60}\u{597d}",
      "\u{5c0f}\u{4fe1}",
      "\u{9192}\u{9192}",
      "shelloworld"
    ].forEach { transcript in
      XCTAssertFalse(WakeWordPolicy.matches(transcript), transcript)
    }
  }

  func testVoiceSettingsNormalizeAdvancedAndroidParityFields() {
    let store = makeStore()

    store.updateVoiceSettings {
      $0.wakeWords = VoiceSettings.wakeWords(from: " GalaxySSI, , hello, custom wake ")
      $0.wakeProvider = .androidASR
      $0.wakeModel = "missing.onnx"
      $0.wakeThreshold = 2
      $0.welcomeText = "  "
      $0.asrProvider = .localWhisperCpp
      $0.asrModelId = "does-not-exist"
      $0.asrRuntimeMode = .privacy
      $0.ttsProvider = .microsoftEdge
      $0.microsoftVoice = "  "
      $0.targetContactId = ""
      $0.speakReplies = false
      $0.routingMode = .contact
    }

    XCTAssertEqual(store.voiceSettings.wakeWords, ["GalaxySSI", "hello", "custom wake"])
    XCTAssertEqual(store.voiceSettings.wakeProvider, .androidASR)
    XCTAssertEqual(store.voiceSettings.wakeModel, VoiceSettings.defaultWakeModel)
    XCTAssertEqual(store.voiceSettings.wakeThreshold, 0.99)
    XCTAssertEqual(store.voiceSettings.welcomeText, VoiceSettings.defaultWelcomeText)
    XCTAssertEqual(store.voiceSettings.asrProvider, .localWhisperCpp)
    XCTAssertEqual(store.voiceSettings.asrModelId, "tiny")
    XCTAssertEqual(store.voiceSettings.asrRuntimeMode, .privacy)
    XCTAssertEqual(store.voiceSettings.ttsProvider, .microsoftEdge)
    XCTAssertEqual(store.voiceSettings.microsoftVoice, VoiceSettings.defaultMicrosoftVoice)
    XCTAssertEqual(store.voiceSettings.targetContactId, "hermes")
    XCTAssertFalse(store.voiceSettings.speakReplies)
    XCTAssertEqual(store.voiceSettings.routingMode, .contact)
  }

  func testVoiceSettingsDecodeAndroidProviderWireValues() throws {
    let settings = try JSONDecoder.galaxySSI.decode(
      VoiceSettings.self,
      from: Data(#"{"wake_provider":"android_asr","wake_model":"hello_world.onnx","asr_provider":"local_whisper_cpp","asr_runtime_mode":"ACCURATE","tts_provider":"microsoft_edge","microsoft_voice":" zh-CN-Xiaoxiao:DragonHDFlashLatestNeural ","asr_model":"base"}"#.utf8)
    )
    let fallback = try JSONDecoder.galaxySSI.decode(
      VoiceSettings.self,
      from: Data(#"{"wake_provider":"bad","wake_model":"bad.onnx","asr_provider":"bad","tts_provider":"bad","microsoft_voice":" "}"#.utf8)
    )
    let automatic = try JSONDecoder.galaxySSI.decode(
      VoiceSettings.self,
      from: Data(#"{"asr_provider":"auto"}"#.utf8)
    )
    let encoded = try JSONEncoder.galaxySSI.encode(settings)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

    XCTAssertEqual(settings.wakeProvider, .androidASR)
    XCTAssertEqual(settings.wakeModel, VoiceSettings.defaultWakeModel)
    XCTAssertEqual(settings.asrProvider, .localWhisperCpp)
    XCTAssertEqual(settings.asrRuntimeMode, .accurate)
    XCTAssertEqual(settings.ttsProvider, .microsoftEdge)
    XCTAssertEqual(settings.microsoftVoice, MicrosoftTTSVoiceCatalog.xiaoxiaoDragonHDFlash)
    XCTAssertEqual(settings.asrModelId, "base")
    XCTAssertEqual(fallback.wakeProvider, .androidASR)
    XCTAssertEqual(fallback.wakeModel, VoiceSettings.defaultWakeModel)
    XCTAssertEqual(fallback.asrProvider, .automatic)
    XCTAssertEqual(fallback.ttsProvider, .system)
    XCTAssertEqual(fallback.microsoftVoice, VoiceSettings.defaultMicrosoftVoice)
    XCTAssertEqual(automatic.asrProvider, .automatic)
    XCTAssertEqual(object["wake_provider"] as? String, "android_asr")
    XCTAssertEqual(object["asr_provider"] as? String, "local_whisper_cpp")
    XCTAssertEqual(object["asr_runtime_mode"] as? String, "ACCURATE")
    XCTAssertEqual(object["tts_provider"] as? String, "microsoft_edge")
    XCTAssertEqual(object["microsoft_voice"] as? String, MicrosoftTTSVoiceCatalog.xiaoxiaoDragonHDFlash)
  }

  func testDisplaySettingsNormalizeAndroidTextScaleWireValues() throws {
    let extraLarge = try JSONDecoder.galaxySSI.decode(
      AppDisplaySettings.self,
      from: Data(#"{"text_scale":"EXTRA_LARGE"}"#.utf8)
    )
    let fallback = try JSONDecoder.galaxySSI.decode(
      AppDisplaySettings.self,
      from: Data(#"{"text_scale":"not-supported"}"#.utf8)
    )
    let store = makeStore()

    XCTAssertEqual(extraLarge.textScale, .extraLarge)
    XCTAssertEqual(fallback.textScale, .comfortable)
    XCTAssertEqual(store.displaySettings.textScale, .comfortable)
    XCTAssertEqual(
      AppTextScaleMode.comfortable.detail,
      "Use the app's default comfortable text size."
    )

    store.updateDisplaySettings {
      $0.textScale = .large
    }

    XCTAssertEqual(store.displaySettings.textScale, .large)
  }

  func testAgentSafetySettingsDecodeAndroidPolicyAndEncodeStoredNames() throws {
    let settings = try JSONDecoder.galaxySSI.decode(
      AgentSafetySettings.self,
      from: Data(#"{"task_execution_mode":"plan_only","permission_mode":"AUTO_LOW_RISK","high_risk_guard":false,"memory_capture":false,"screen_observation_allowed":false,"local_actions_allowed":false,"connector_calls_allowed":false,"device_control_allowed":false,"execution_paused":true}"#.utf8)
    )
    let fallback = try JSONDecoder.galaxySSI.decode(
      AgentSafetySettings.self,
      from: Data(#"{"task_execution_mode":"unknown","permission_mode":"unknown"}"#.utf8)
    )
    let encoded = try JSONEncoder.galaxySSI.encode(settings)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

    XCTAssertEqual(settings.taskExecutionMode, .planOnly)
    XCTAssertEqual(settings.permissionMode, .autoLowRisk)
    XCTAssertFalse(settings.highRiskGuard)
    XCTAssertFalse(settings.memoryCapture)
    XCTAssertFalse(settings.screenObservationAllowed)
    XCTAssertFalse(settings.localActionsAllowed)
    XCTAssertFalse(settings.connectorCallsAllowed)
    XCTAssertFalse(settings.deviceControlAllowed)
    XCTAssertTrue(settings.executionPaused)
    XCTAssertEqual(fallback.taskExecutionMode, .autoComplete)
    XCTAssertEqual(fallback.permissionMode, .askBeforeAction)
    XCTAssertEqual(object["task_execution_mode"] as? String, "PLAN_ONLY")
    XCTAssertEqual(object["permission_mode"] as? String, "AUTO_LOW_RISK")

    let store = makeStore()
    store.updateAgentSafetySettings {
      $0.taskExecutionMode = .planOnly
      $0.permissionMode = .observeOnly
      $0.executionPaused = true
    }

    XCTAssertEqual(store.agentSafetySettings.taskExecutionMode, .planOnly)
    XCTAssertEqual(store.agentSafetySettings.permissionMode, .observeOnly)
    XCTAssertTrue(store.agentSafetySettings.executionPaused)
  }

  func testAgentTaskExecutionModePolicyMatchesAndroidExplicitSignals() {
    let planOnly = AgentTaskExecutionModePolicy.resolve(
      request: "\u{5148}\u{7ed9}\u{65b9}\u{6848}\u{ff0c}\u{4e0d}\u{8981}\u{6267}\u{884c}\u{4efb}\u{4f55}\u{64cd}\u{4f5c}",
      configuredMode: .autoComplete
    )
    let autoComplete = AgentTaskExecutionModePolicy.resolve(
      request: "\u{6309}\u{8fd9}\u{4e2a}\u{65b9}\u{6848}\u{6267}\u{884c}\u{ff0c}\u{7ee7}\u{7eed}\u{6267}\u{884c}\u{5230}\u{5b8c}\u{6210}",
      configuredMode: .planOnly
    )

    XCTAssertEqual(planOnly.mode, .planOnly)
    XCTAssertTrue(planOnly.explicitlyRequested)
    XCTAssertEqual(planOnly.matchedSignal, "\u{5148}\u{7ed9}\u{65b9}\u{6848}")
    XCTAssertEqual(autoComplete.mode, .autoComplete)
    XCTAssertTrue(autoComplete.explicitlyRequested)
    XCTAssertEqual(autoComplete.matchedSignal, "\u{6309}\u{8fd9}\u{4e2a}\u{65b9}\u{6848}\u{6267}\u{884c}")
  }

  func testAgentTaskExecutionModePolicyKeepsDefaultsAndScopedNegatives() {
    let configuredDefault = AgentTaskExecutionModePolicy.resolve(
      request: "\u{68c0}\u{67e5}\u{8fd9}\u{4e2a}\u{9879}\u{76ee}\u{7684}\u{6784}\u{5efa}\u{72b6}\u{6001}",
      configuredMode: .planOnly
    )
    let scopedNegative = AgentTaskExecutionModePolicy.resolve(
      request: "\u{68c0}\u{67e5}\u{9879}\u{76ee}\u{ff0c}\u{4f46}\u{4e0d}\u{8981}\u{6267}\u{884c}\u{5220}\u{9664}\u{64cd}\u{4f5c}",
      configuredMode: .autoComplete
    )

    XCTAssertEqual(configuredDefault.mode, .planOnly)
    XCTAssertFalse(configuredDefault.explicitlyRequested)
    XCTAssertEqual(scopedNegative.mode, .autoComplete)
    XCTAssertFalse(scopedNegative.explicitlyRequested)
    XCTAssertEqual(AgentTaskExecutionMode.fromWireValue("plan_only"), .planOnly)
    XCTAssertEqual(AgentTaskExecutionMode.fromWireValue("AUTO_COMPLETE"), .autoComplete)
  }

  func testCustomDeviceConnectorsDecodeAndroidFieldsAndStoreTokensInKeychain() throws {
    let connector = try JSONDecoder.galaxySSI.decode(
      CustomDeviceConnector.self,
      from: Data("""
      {
        "id": " custom-device-office ",
        "name": " Office Light ",
        "transport": "mqtt",
        "endpoint": " mqtt://broker.local ",
        "command_target": " topic/light/office ",
        "username": " user ",
        "auth_token": " token ",
        "risk": "HIGH",
        "enabled": true
      }
      """.utf8)
    )
    let encoded = try JSONEncoder.galaxySSI.encode(connector)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let secrets = InMemorySecretStore()
    let store = makeStore(secrets: secrets)

    XCTAssertEqual(connector.id, "custom-device-office")
    XCTAssertEqual(connector.name, "Office Light")
    XCTAssertEqual(connector.transport, .mqtt)
    XCTAssertEqual(connector.endpoint, "mqtt://broker.local")
    XCTAssertEqual(connector.commandTarget, "topic/light/office")
    XCTAssertEqual(connector.username, "user")
    XCTAssertEqual(connector.authToken, "token")
    XCTAssertEqual(connector.risk, .high)
    XCTAssertTrue(connector.configured)
    XCTAssertEqual(object["transport"] as? String, "MQTT")
    XCTAssertEqual(object["command_target"] as? String, "topic/light/office")
    XCTAssertEqual(object["auth_token"] as? String, "token")
    XCTAssertEqual(object["risk"] as? String, "HIGH")

    store.upsertCustomDeviceConnector(connector)

    XCTAssertEqual(store.customDeviceConnectors.count, 1)
    XCTAssertEqual(store.customDeviceConnectors[0].transport, .mqtt)
    XCTAssertEqual(secrets.string(account: "custom_device_connector.custom-device-office.auth_token"), "token")

    let overflow = (0..<55).map { index in
      CustomDeviceConnector(id: "device-\(index)", name: "Device \(index)", endpoint: "http://device-\(index).local")
    }
    for item in overflow {
      store.upsertCustomDeviceConnector(item)
    }

    XCTAssertEqual(store.customDeviceConnectors.count, CustomDeviceConnector.maximumConnectors)
    XCTAssertNil(store.customDeviceConnectors.first { $0.id == "custom-device-office" })

    store.upsertCustomDeviceConnector(connector)
    XCTAssertTrue(store.deleteCustomDeviceConnector(id: connector.id))
    XCTAssertNil(secrets.string(account: "custom_device_connector.custom-device-office.auth_token"))
  }

  func testModelPlannerSettingsDecodeAndroidFieldsAndNormalizeBounds() throws {
    let longContactId = String(repeating: "x", count: 160)
    let settings = try JSONDecoder.galaxySSI.decode(
      AgentModelPlannerSettings.self,
      from: Data("""
      {
        "version": 5,
        "enabled": true,
        "share_screen_text": true,
        "max_actions": 99,
        "cloud_contact_id": "  \(longContactId)  ",
        "dynamic_replanning": false,
        "max_replans": 99,
        "multi_agent_coordination": false,
        "share_agent_outputs_with_planner": true,
        "max_agent_hops": 99,
        "max_tool_calls": 1,
        "max_loop_iterations": 99,
        "max_phase_retries": -1,
        "no_progress_timeout_seconds": 99999
      }
      """.utf8)
    )
    let encoded = try JSONEncoder.galaxySSI.encode(settings)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let store = makeStore()

    XCTAssertTrue(settings.enabled)
    XCTAssertTrue(settings.shareScreenText)
    XCTAssertEqual(settings.maxActions, AgentModelPlannerSettings.maximumActions)
    XCTAssertEqual(settings.cloudContactId.count, AgentModelPlannerSettings.maximumCloudContactIdLength)
    XCTAssertFalse(settings.dynamicReplanning)
    XCTAssertEqual(settings.maxReplans, AgentModelPlannerSettings.maximumReplans)
    XCTAssertFalse(settings.multiAgentCoordination)
    XCTAssertTrue(settings.shareAgentOutputsWithPlanner)
    XCTAssertEqual(settings.maxAgentHops, AgentModelPlannerSettings.maximumAgentHops)
    XCTAssertEqual(settings.maxToolCalls, AgentModelPlannerSettings.minimumToolCalls)
    XCTAssertEqual(settings.maxLoopIterations, AgentModelPlannerSettings.maximumLoopIterations)
    XCTAssertEqual(settings.maxPhaseRetries, AgentModelPlannerSettings.minimumPhaseRetries)
    XCTAssertEqual(settings.noProgressTimeoutSeconds, AgentModelPlannerSettings.maximumNoProgressTimeoutSeconds)
    XCTAssertEqual(object["version"] as? Int, 5)
    XCTAssertEqual(object["max_actions"] as? Int, AgentModelPlannerSettings.maximumActions)
    XCTAssertEqual(object["max_tool_calls"] as? Int, AgentModelPlannerSettings.minimumToolCalls)
    XCTAssertEqual(object["no_progress_timeout_seconds"] as? Int, AgentModelPlannerSettings.maximumNoProgressTimeoutSeconds)

    XCTAssertEqual(store.modelPlannerSettings, .default)
    store.updateModelPlannerSettings {
      $0.enabled = true
      $0.maxActions = 0
      $0.maxPhaseRetries = 99
      $0.noProgressTimeoutSeconds = 30
    }

    XCTAssertTrue(store.modelPlannerSettings.enabled)
    XCTAssertEqual(store.modelPlannerSettings.maxActions, 1)
    XCTAssertEqual(store.modelPlannerSettings.maxPhaseRetries, AgentModelPlannerSettings.maximumPhaseRetries)
    XCTAssertEqual(store.modelPlannerSettings.noProgressTimeoutSeconds, AgentModelPlannerSettings.minimumNoProgressTimeoutSeconds)
  }

  func testHomeAssistantSettingsDecodeAndroidFieldsAndStoreTokenInKeychain() throws {
    let longURL = "http://homeassistant.local:8123/" + String(repeating: "x", count: 2_200)
    let longToken = String(repeating: "t", count: 8_400)
    let settings = try JSONDecoder.galaxySSI.decode(
      HomeAssistantSettings.self,
      from: Data("""
      {
        "version": 1,
        "enabled": true,
        "base_url": "  \(longURL)//  ",
        "access_token": "  \(longToken)  ",
        "default_entity_id": "  light.living_room  "
      }
      """.utf8)
    )
    let encoded = try JSONEncoder.galaxySSI.encode(settings)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let secrets = InMemorySecretStore()
    let store = makeStore(secrets: secrets)

    XCTAssertTrue(settings.enabled)
    XCTAssertTrue(settings.credentialsConfigured)
    XCTAssertTrue(settings.configured)
    XCTAssertFalse(settings.baseUrl.hasSuffix("/"))
    XCTAssertEqual(settings.baseUrl.count, HomeAssistantSettings.maximumBaseURLLength)
    XCTAssertEqual(settings.accessToken.count, HomeAssistantSettings.maximumAccessTokenLength)
    XCTAssertEqual(settings.defaultEntityId, "light.living_room")
    XCTAssertEqual(object["version"] as? Int, 1)
    XCTAssertEqual(object["base_url"] as? String, settings.baseUrl)
    XCTAssertEqual(object["access_token"] as? String, settings.accessToken)

    store.updateHomeAssistantSettings {
      $0.enabled = true
      $0.baseUrl = " http://homeassistant.local:8123/ "
      $0.accessToken = " ha-token "
      $0.defaultEntityId = " light.office "
    }

    XCTAssertTrue(store.homeAssistantSettings.configured)
    XCTAssertEqual(store.homeAssistantSettings.baseUrl, "http://homeassistant.local:8123")
    XCTAssertEqual(store.homeAssistantSettings.accessToken, "ha-token")
    XCTAssertEqual(store.homeAssistantSettings.defaultEntityId, "light.office")
    XCTAssertEqual(secrets.string(account: "home_assistant.access_token"), "ha-token")

    store.updateHomeAssistantSettings {
      $0.accessToken = ""
    }

    XCTAssertFalse(store.homeAssistantSettings.credentialsConfigured)
    XCTAssertNil(secrets.string(account: "home_assistant.access_token"))
  }

  func testAgentRuntimeCapabilityMatrixKeepsUnavailableAndBlockedVisibleButNotExecutable() throws {
    let available = try nativeToolDescriptor("galaxyssi.test.available")
    let setup = try nativeToolDescriptor(
      "galaxyssi.test.setup",
      availability: AgentNativeToolAvailability(
        status: .requiresSetup,
        reason: "Permission missing"
      )
    )
    let unavailable = try nativeToolDescriptor(
      "galaxyssi.test.unavailable",
      availability: AgentNativeToolAvailability(
        status: .unavailable,
        reason: "Runtime missing"
      )
    )
    let blocked = try nativeToolDescriptor("galaxyssi.test.blocked", risk: .blocked)

    let snapshot = AgentRuntimeCapabilityMatrix.build(
      nativeTools: [available, setup, unavailable, blocked],
      systemTools: [],
      targets: []
    )

    XCTAssertEqual(snapshot.availableNativeToolIds, Set([available.id]))
    XCTAssertEqual(snapshot.entries.count, 4)
    XCTAssertEqual(snapshot.setupRequiredEntries.count, 1)
    XCTAssertEqual(snapshot.unavailableEntries.count, 2)
    XCTAssertFalse(snapshot.isNativeToolExecutable(id: setup.id))
    XCTAssertFalse(snapshot.isNativeToolExecutable(id: unavailable.id))
    XCTAssertFalse(snapshot.isNativeToolExecutable(id: blocked.id))
  }

  func testAgentRuntimeCapabilityMatrixUsesLiveNativeAdapterStateForSystemTools() throws {
    let native = try nativeToolDescriptor(
      AgentNativeToolAgentActionAdapter.defaultToolId(.openApp),
      availability: AgentNativeToolAvailability(
        status: .requiresSetup,
        reason: "No matching activity"
      ),
      requiredPermissions: [
        AgentNativePermissionRequirement(id: "ios.open_app")
      ]
    )
    let action = AgentSystemTool(
      id: "open-app",
      title: "Open app",
      kind: .openApp,
      risk: .low,
      capabilities: [.appNavigation]
    )
    let workflow = AgentSystemTool(
      id: "workflow:daily",
      title: "Daily workflow",
      kind: .draftPlan,
      risk: .low,
      capabilities: [.taskExecution]
    )

    let snapshot = AgentRuntimeCapabilityMatrix.build(
      nativeTools: [native],
      systemTools: [action, workflow],
      targets: []
    )
    let actionEntry = try XCTUnwrap(snapshot.entry(source: .systemTool, id: action.id))
    let workflowEntry = try XCTUnwrap(snapshot.entry(source: .systemTool, id: workflow.id))

    XCTAssertEqual(actionEntry.state, .requiresSetup)
    XCTAssertEqual(actionEntry.reason, "No matching activity")
    XCTAssertEqual(actionEntry.requiredPermissions, ["ios.open_app"])
    XCTAssertEqual(workflowEntry.state, .available)
    XCTAssertEqual(workflowEntry.reason, "Host-owned workflow is installed")
  }

  func testAgentRuntimeCapabilityMatrixProjectsConnectorAndNativeStatusTogether() throws {
    let available = try nativeToolDescriptor("galaxyssi.test.available")
    let unavailable = try nativeToolDescriptor(
      "galaxyssi.test.unavailable",
      availability: AgentNativeToolAvailability(status: .unavailable, reason: "Missing")
    )
    let target = AgentCallableTarget(
      id: "codex",
      title: "Codex",
      kind: .agent,
      status: .disconnected,
      capabilities: [.code],
      failureDomain: "desktop"
    )

    let snapshot = AgentRuntimeCapabilityMatrix.build(
      nativeTools: [available, unavailable],
      systemTools: [],
      targets: [target]
    )

    XCTAssertEqual(snapshot.entry(source: .connector, id: "codex")?.state, .unavailable)
    XCTAssertEqual(snapshot.entry(source: .nativeTool, id: available.id)?.state, .available)
    XCTAssertEqual(snapshot.entry(source: .nativeTool, id: unavailable.id)?.state, .unavailable)
    XCTAssertEqual(
      AgentRuntimeCapabilityMatrix.availableNativeTools(
        nativeTools: [available, unavailable],
        targets: [target]
      ).map(\.id),
      [available.id]
    )
  }

  func testAgentRuntimeCapabilityMatrixModelsUseAndroidWireNames() throws {
    let descriptor = try nativeToolDescriptor(
      "galaxyssi.test.wire",
      capabilities: ["test.execute", "test.inspect"],
      requiredPermissions: [
        AgentNativePermissionRequirement(id: "ios.camera", title: "Camera")
      ],
      requiredConsents: [
        AgentNativeConsentRequirement(id: "capture.once", title: "Capture once")
      ]
    )
    let snapshot = AgentRuntimeCapabilityMatrix.build(
      nativeTools: [descriptor],
      systemTools: [],
      targets: []
    )
    let descriptorObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(descriptor)) as? [String: Any]
    )
    let entryObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot.entries[0])) as? [String: Any]
    )
    let source = try JSONDecoder().decode(
      AgentRuntimeCapabilitySource.self,
      from: Data(#""NATIVE_TOOL""#.utf8)
    )
    let capability = try JSONDecoder().decode(
      AgentCapability.self,
      from: Data(#""app-navigation""#.utf8)
    )

    XCTAssertNotNil(descriptorObject["input_schema"] as? [String: Any])
    XCTAssertNotNil(descriptorObject["output_schema"] as? [String: Any])
    XCTAssertNotNil(descriptorObject["required_permissions"] as? [[String: Any]])
    XCTAssertNotNil(descriptorObject["required_consents"] as? [[String: Any]])
    XCTAssertEqual(descriptorObject["timeout_millis"] as? Int, 30_000)
    XCTAssertEqual((descriptorObject["availability"] as? [String: Any])?["status"] as? String, "available")
    XCTAssertEqual(entryObject["source"] as? String, "NATIVE_TOOL")
    XCTAssertEqual(entryObject["state"] as? String, "AVAILABLE")
    XCTAssertEqual(entryObject["required_permissions"] as? [String], ["ios.camera"])
    XCTAssertEqual(entryObject["required_consents"] as? [String], ["capture.once"])
    XCTAssertEqual(source, .nativeTool)
    XCTAssertEqual(capability, .appNavigation)
  }

  func testAgentNativeToolResultModelsUseAndroidWireNames() throws {
    let result = nativeToolResult(
      invocationId: "invoke-1",
      idempotencyKey: "native-replay-key",
      verification: AgentNativeToolVerification(
        status: .passed,
        evidence: ["receipt": .string("verified")]
      )
    )
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any]
    )
    let receipt = try XCTUnwrap(object["receipt"] as? [String: Any])
    let provenance = try XCTUnwrap(object["provenance"] as? [String: Any])
    let verification = try XCTUnwrap(object["verification"] as? [String: Any])
    let decodedStatus = try JSONDecoder().decode(
      AgentNativeToolResultStatus.self,
      from: Data(#""unknown_status""#.utf8)
    )
    let decodedVerification = try JSONDecoder().decode(
      AgentNativeVerificationStatus.self,
      from: Data(#""unknown_verification""#.utf8)
    )
    let roundTripped = try XCTUnwrap(AgentNativeToolResult.fromJSONObject(result.toJSONObject()))

    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(object["status"] as? String, "succeeded")
    XCTAssertNotNil(object["output"] as? [String: Any])
    XCTAssertEqual(receipt["invocation_id"] as? String, "invoke-1")
    XCTAssertEqual(receipt["idempotency_key"] as? String, "native-replay-key")
    XCTAssertEqual(receipt["started_at_epoch_ms"] as? Int, 1_000)
    XCTAssertEqual(receipt["finished_at_epoch_ms"] as? Int, 1_050)
    XCTAssertEqual(receipt["duration_ms"] as? Int, 50)
    XCTAssertEqual(receipt["input_sha256"] as? String, String(repeating: "a", count: 64))
    XCTAssertEqual(receipt["output_sha256"] as? String, String(repeating: "b", count: 64))
    XCTAssertEqual(receipt["replayed"] as? Bool, false)
    XCTAssertEqual(provenance["tool_id"] as? String, "galaxyssi.test.native")
    XCTAssertEqual(provenance["tool_version"] as? String, "1.0.0")
    XCTAssertEqual(provenance["executor_id"] as? String, "ios-native")
    XCTAssertEqual(provenance["contract_version"] as? String, "galaxyssi.native-tool/1.0")
    XCTAssertEqual(verification["status"] as? String, "passed")
    XCTAssertEqual(decodedStatus, .failed)
    XCTAssertEqual(decodedVerification, .skipped)
    XCTAssertEqual(roundTripped, result)
  }

  func testAgentNativeToolReplayStoreEvictsOldestAndClears() throws {
    let store = InMemoryAgentNativeToolReplayStore()
    let firstKey = AgentNativeToolReplayKey(
      toolId: "galaxyssi.test.first",
      toolVersion: "1.0.0",
      idempotencyKey: "first"
    )
    try store.put(firstKey, result: nativeToolResult(invocationId: "first", idempotencyKey: "first"))

    for index in 1...InMemoryAgentNativeToolReplayStore.maxEntries {
      let key = AgentNativeToolReplayKey(
        toolId: "galaxyssi.test.\(index)",
        toolVersion: "1.0.0",
        idempotencyKey: "key-\(index)"
      )
      try store.put(key, result: nativeToolResult(invocationId: "invoke-\(index)", idempotencyKey: key.idempotencyKey))
    }

    let retainedKey = AgentNativeToolReplayKey(
      toolId: "galaxyssi.test.1",
      toolVersion: "1.0.0",
      idempotencyKey: "key-1"
    )
    let lastKey = AgentNativeToolReplayKey(
      toolId: "galaxyssi.test.\(InMemoryAgentNativeToolReplayStore.maxEntries)",
      toolVersion: "1.0.0",
      idempotencyKey: "key-\(InMemoryAgentNativeToolReplayStore.maxEntries)"
    )

    XCTAssertNil(store.get(firstKey))
    XCTAssertEqual(store.get(retainedKey)?.receipt.invocationId, "invoke-1")
    XCTAssertEqual(store.get(lastKey)?.receipt.invocationId, "invoke-\(InMemoryAgentNativeToolReplayStore.maxEntries)")

    store.clear()

    XCTAssertNil(store.get(retainedKey))
    XCTAssertNil(store.get(lastKey))
  }

  func testAgentNativeToolReplaySnapshotStoreKeepsSuccessfulFreshResults() throws {
    var now: Int64 = 1_000
    let key = AgentNativeToolReplayKey(
      toolId: "galaxyssi.test.native",
      toolVersion: "1.0.0",
      idempotencyKey: "replay-once"
    )
    let store = AgentNativeToolReplaySnapshotStore(nowMillis: { now })

    try store.put(key, result: nativeToolResult(invocationId: "fresh", idempotencyKey: "replay-once"))

    let serialized = store.serializedSnapshot()
    let entries = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(serialized.utf8)) as? [[String: Any]])
    let first = try XCTUnwrap(entries.first)
    let restored = AgentNativeToolReplaySnapshotStore(serializedEntries: serialized, nowMillis: { now })
    let replayed = try XCTUnwrap(restored.get(key))

    XCTAssertEqual(first["tool_id"] as? String, "galaxyssi.test.native")
    XCTAssertEqual(first["tool_version"] as? String, "1.0.0")
    XCTAssertEqual(first["idempotency_key"] as? String, "replay-once")
    XCTAssertEqual(first["saved_at_millis"] as? Int, 1_000)
    XCTAssertNotNil(first["result"] as? [String: Any])
    XCTAssertEqual(replayed.receipt.invocationId, "fresh")
    XCTAssertThrowsError(
      try restored.put(
        AgentNativeToolReplayKey(toolId: "galaxyssi.test.native", toolVersion: "1.0.0", idempotencyKey: "failed"),
        result: nativeToolResult(status: .failed, invocationId: "failed", idempotencyKey: "failed")
      )
    ) { error in
      XCTAssertEqual(error as? AgentNativeToolReplayError, .unsuccessfulResult)
    }

    now += AgentNativeToolReplaySnapshotStore.retentionMillis + 1

    XCTAssertNil(restored.get(key))
    XCTAssertEqual(restored.serializedSnapshot(), "[]")
  }

  func testFileAgentNativeToolReplayStorePersistsPrunesAndClears() throws {
    var now: Int64 = 5_000
    let root = try temporaryDirectory("native-tool-replay-file")
    defer { try? FileManager.default.removeItem(at: root) }
    let fileURL = relativeFile("replay/entries.json", under: root)
    let key = AgentNativeToolReplayKey(
      toolId: "galaxyssi.test.native",
      toolVersion: "1.0.0",
      idempotencyKey: "file-replay"
    )
    let store = FileAgentNativeToolReplayStore(fileURL: fileURL, nowMillis: { now })

    try store.put(key, result: nativeToolResult(invocationId: "stored", idempotencyKey: "file-replay"))

    let restored = FileAgentNativeToolReplayStore(fileURL: fileURL, nowMillis: { now })
    let replayed = try XCTUnwrap(restored.get(key))

    XCTAssertEqual(replayed.receipt.invocationId, "stored")
    XCTAssertThrowsError(
      try restored.put(
        AgentNativeToolReplayKey(toolId: "galaxyssi.test.native", toolVersion: "1.0.0", idempotencyKey: "failed"),
        result: nativeToolResult(status: .failed, invocationId: "failed", idempotencyKey: "failed")
      )
    ) { error in
      XCTAssertEqual(error as? AgentNativeToolReplayError, .unsuccessfulResult)
    }

    now += AgentNativeToolReplaySnapshotStore.retentionMillis + 1

    XCTAssertNil(restored.get(key))
    XCTAssertEqual((try? String(contentsOf: fileURL, encoding: .utf8)) ?? "", "[]")

    try restored.put(key, result: nativeToolResult(invocationId: "fresh", idempotencyKey: "file-replay"))
    XCTAssertNotNil(FileAgentNativeToolReplayStore(fileURL: fileURL, nowMillis: { now }).get(key))

    restored.clear()

    XCTAssertNil(FileAgentNativeToolReplayStore(fileURL: fileURL, nowMillis: { now }).get(key))
    XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
  }

  func testAgentNativeToolReplayJsonCodecSkipsMalformedEntries() throws {
    let key = AgentNativeToolReplayKey(
      toolId: "galaxyssi.test.native",
      toolVersion: "1.0.0",
      idempotencyKey: "valid"
    )
    let valid = AgentNativeToolReplayEntry(
      key: key,
      result: nativeToolResult(invocationId: "valid", idempotencyKey: "valid"),
      savedAtMillis: 2_000
    )
    let raw = AgentMcpJSONCodec.stringify(.array([
      .string("ignored"),
      .object([
        "tool_id": .string(""),
        "tool_version": .string("1.0.0"),
        "idempotency_key": .string("blank"),
        "saved_at_millis": .int(1_000),
        "result": valid.result.toJsonValue()
      ]),
      .object([
        "tool_id": .string(valid.key.toolId),
        "tool_version": .string(valid.key.toolVersion),
        "idempotency_key": .string(valid.key.idempotencyKey),
        "saved_at_millis": .int(valid.savedAtMillis),
        "result": valid.result.toJsonValue()
      ])
    ]))
    let decoded = AgentNativeToolReplayJsonCodec.decode(raw)

    XCTAssertEqual(decoded, [valid])
    XCTAssertTrue(AgentNativeToolReplayJsonCodec.decode("{broken").isEmpty)
  }

  func makeStore() -> GalaxySSIStore {
    makeStore(secrets: InMemorySecretStore())
  }

  func makeStore(secrets: GalaxySSISecretStore) -> GalaxySSIStore {
    let suite = "GalaxySSIStoreTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return GalaxySSIStore(defaults: defaults, secrets: secrets)
  }

  func providerCloudModel(
    provider: String,
    modelId: String,
    endpoint: String,
    apiStyle: GalaxySSICloudAPIStyle = .openAICompatible
  ) -> CloudModelConfig {
    CloudModelConfig(
      id: "\(provider)-\(modelId)",
      displayName: modelId,
      provider: provider,
      modelId: modelId,
      endpoint: endpoint,
      apiStyle: apiStyle,
      keychainAccount: "cloud.\(provider).\(modelId)",
      updatedAt: Date(timeIntervalSince1970: 0)
    )
  }

  func routeTarget(
    _ id: String,
    kind: AgentConnectorKind,
    status: AgentConnectorStatus = .available,
    capabilities: [AgentCapability] = [.chat, .reasoning, .research]
  ) -> AgentCallableTarget {
    AgentCallableTarget(
      id: id,
      title: id,
      kind: kind,
      status: status,
      capabilities: capabilities
    )
  }

  func planFactoryTarget(
    id: String = "desktop:codex",
    title: String = "Codex",
    kind: AgentConnectorKind = .agent,
    status: AgentConnectorStatus = .available,
    capabilities: [AgentCapability] = [.chat, .reasoning]
  ) -> AgentCallableTarget {
    AgentCallableTarget(
      id: id,
      title: title,
      kind: kind,
      status: status,
      capabilities: capabilities,
      failureDomain: "desktop",
      desktopAccessProfile: GalaxySSILinkProtocol.accessDesktopExecutor
    )
  }

  func planFactoryRequest(
    targets: [AgentCallableTarget]? = nil,
    nativeTools: [AgentNativeToolDescriptor] = []
  ) -> AgentPlanRequest {
    let resolvedTargets = targets ?? [planFactoryTarget()]
    return AgentPlanRequest(
      goal: "Convert the file",
      screen: AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent"),
      targets: resolvedTargets,
      nativeTools: nativeTools,
      contextDigest: "context"
    )
  }

  func planConnectorAction(
    id: String,
    connectorId: String,
    target: String = "Codex"
  ) -> AgentAction {
    AgentAction(
      id: id,
      kind: .callConnector,
      target: target,
      risk: .low,
      status: .pendingConfirmation,
      description: "Run the task",
      parameters: [
        "connector_id": connectorId,
        "prompt": "Convert the file"
      ]
    )
  }

  func routingResource(
    targetId: String,
    type: AgentResourceType,
    location: AgentResourceLocation
  ) -> AgentResourceDescriptor {
    AgentResourceDescriptor(
      id: "resource:\(targetId)",
      title: targetId,
      type: type,
      location: location,
      status: .available,
      capabilities: [.research],
      cost: .free,
      latency: .fast,
      quality: .strong,
      supportsTools: type == .localTool,
      targetId: targetId
    )
  }

  func resourceCandidate(
    _ resource: AgentResourceDescriptor,
    score: Int
  ) -> AgentResourceCandidate {
    AgentResourceCandidate(resource: resource, score: score)
  }

  func routingDecision(
    primary: AgentResourceCandidate,
    fallbacks: [AgentResourceCandidate],
    catalog: [AgentResourceDescriptor]
  ) -> AgentRoutingDecision {
    AgentRoutingDecision(
      requirements: AgentTaskRequirements(
        capabilities: [.research],
        mode: .balanced,
        liveDataRequired: true,
        estimatedInputTokens: 200
      ),
      primary: primary,
      fallbacks: fallbacks,
      catalog: catalog
    )
  }

  private var remoteReputationDesktopId: String { "desktop_0123456789abcdef" }
  private var remoteReputationTaskId: String { "task-123" }
  private var remoteReputationContactId: String { "\(remoteReputationDesktopId):codex" }

  func remoteReputationReceiptObject() -> AgentMcpJSONObject {
    [
      "version": .int(1),
      "receipt_id": .string("receipt-1"),
      "run_id": .string("run-1"),
      "task_id_hash": .string(agentReputationSha256(Data(remoteReputationTaskId.utf8))),
      "agent_id": .string(remoteReputationContactId),
      "installation_id": .string(remoteReputationDesktopId),
      "executor_failure_domain": .string(remoteReputationDesktopId),
      "capabilities": .array([.string("CHAT"), .string("CODE")]),
      "outcome": .string("SUCCEEDED"),
      "provenance": .string("HOST_OBSERVED"),
      "started_at_millis": .int(1_000),
      "completed_at_millis": .int(2_000),
      "deadline_at_millis": .int(0),
      "estimated_cost_units": .int(0),
      "actual_cost_units": .int(0),
      "output_hash": .string(String(repeating: "b", count: 64)),
      "evidence_hash": .string(String(repeating: "c", count: 64)),
      "signer_id": .string(remoteReputationDesktopId),
      "signature_key_id": .string(String(repeating: "a", count: 64)),
      "signature": .string("signature")
    ]
  }

  func remoteReputationEnvelope(
    desktopId: String? = nil,
    taskId: String? = nil,
    agentId: String = "codex",
    contactId: String? = nil
  ) -> AgentMcpJSONObject {
    let resolvedDesktopId = desktopId ?? remoteReputationDesktopId
    let resolvedTaskId = taskId ?? remoteReputationTaskId
    let resolvedContactId = contactId ?? "\(resolvedDesktopId):\(agentId)"
    return [
      "desktop_id": .string(resolvedDesktopId),
      "task_id": .string(resolvedTaskId),
      "agent_id": .string(agentId),
      "contact_id": .string(resolvedContactId),
      "execution_receipt": .object(remoteReputationReceiptObject())
    ]
  }

  func remoteReputationAttestationObject(
    for receipt: AgentSignedExecutionReceipt
  ) -> AgentMcpJSONObject {
    [
      "version": .int(1),
      "attestation_id": .string(agentReputationSha256(Data("\(receipt.receiptId):PASSED".utf8))),
      "receipt_id": .string(receipt.receiptId),
      "receipt_payload_hash": .string(agentReputationSha256(receipt.canonicalPayload())),
      "verifier_agent_id": .string("independent-verifier"),
      "verifier_installation_id": .string("verifier-host"),
      "verifier_failure_domain": .string("phone-b"),
      "verdict": .string("PASSED"),
      "evidence_hash": .string(agentReputationSha256(Data("evidence-\(receipt.receiptId)".utf8))),
      "created_at_millis": .int(receipt.completedAtMillis + 100),
      "signer_id": .string("verifier-host"),
      "signature_key_id": .string(String(repeating: "d", count: 64)),
      "signature": .string("attestation-signature")
    ]
  }

  private var reputationNow: Int64 { 10_000_000 }

  func reputationReceipt(
    _ runId: String,
    outcome: AgentReputationOutcome,
    agentId: String = "codex-agent",
    capabilities: Set<AgentCapability> = [.chat, .reasoning],
    completedAtMillis: Int64? = nil,
    deadlineAtMillis: Int64 = 0,
    estimatedCostUnits: Int = 0,
    actualCostUnits: Int = 0
  ) -> AgentSignedExecutionReceipt {
    let completedAt = completedAtMillis ?? reputationNow
    return AgentSignedExecutionReceipt(
      receiptId: agentReputationSha256(Data("\(agentId):\(runId):\(outcome.rawValue):\(completedAt)".utf8)),
      runId: runId,
      taskIdHash: agentReputationSha256(Data("task-\(runId)".utf8)),
      agentId: agentId,
      installationId: "executor-host",
      executorFailureDomain: "executor-host",
      capabilities: capabilities,
      outcome: outcome,
      provenance: .executorSigned,
      startedAtMillis: completedAt - 1_000,
      completedAtMillis: completedAt,
      deadlineAtMillis: deadlineAtMillis,
      estimatedCostUnits: estimatedCostUnits,
      actualCostUnits: actualCostUnits,
      outputHash: outcome == .succeeded ? agentReputationSha256(Data("output-\(runId)".utf8)) : "",
      evidenceHash: "",
      signerId: "executor-host",
      signatureKeyId: String(repeating: "a", count: 64),
      signature: "receipt-signature"
    )
  }

  func reputationAttestation(
    for receipt: AgentSignedExecutionReceipt,
    verdict: AgentReputationVerificationVerdict
  ) -> AgentSignedReputationAttestation {
    AgentSignedReputationAttestation(
      attestationId: agentReputationSha256(Data("\(receipt.receiptId):\(verdict.rawValue)".utf8)),
      receiptId: receipt.receiptId,
      receiptPayloadHash: agentReputationSha256(receipt.canonicalPayload()),
      verifierAgentId: "independent-verifier",
      verifierInstallationId: "verifier-host",
      verifierFailureDomain: "phone-b",
      verdict: verdict,
      evidenceHash: agentReputationSha256(Data("evidence-\(receipt.receiptId)".utf8)),
      createdAtMillis: receipt.completedAtMillis + 100,
      signerId: "verifier-host",
      signatureKeyId: String(repeating: "d", count: 64),
      signature: "attestation-signature"
    )
  }

  func networkRegistration(
    agentId: String,
    displayName: String,
    providerId: String = "desktop-provider",
    deviceId: String = "desktop-device",
    location: AgentResourceLocation = .trustedDesktop,
    status: AgentEndpointStatus = .online,
    capabilities: Set<AgentCapability> = [.chat],
    cost: AgentResourceCost = .free,
    latency: AgentResourceLatency = .normal,
    trust: AgentResourceTrust = .verifiedPaired,
    activeRuns: Int = 0,
    maxParallelRuns: Int = 4,
    failureDomain: String = "",
    runtimeFailureDomain: String = "",
    adapterType: String = "",
    lastHeartbeatMillis: Int64 = 0
  ) -> AgentRegistration {
    AgentRegistration(
      agentId: agentId,
      installationId: "installation-\(agentId)",
      deviceId: deviceId,
      providerId: providerId,
      displayName: displayName,
      kind: .agent,
      location: location,
      status: status,
      capabilities: capabilities,
      protocol: AgentProtocolRange(
        preferred: "1.1",
        minimum: "1.0",
        maximum: "1.1",
        features: ["run.cancel", "run.recover"]
      ),
      connectionKind: .galaxyssiLink,
      cost: cost,
      latency: latency,
      trust: trust,
      activeRuns: activeRuns,
      maxParallelRuns: maxParallelRuns,
      failureDomain: failureDomain,
      runtimeFailureDomain: runtimeFailureDomain,
      adapterType: adapterType,
      lastHeartbeatMillis: lastHeartbeatMillis
    )
  }

  func assertGlobalCapabilityEventDoesNotExpose(
    _ event: GlobalConversationEvent,
    secrets: [String],
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let metadata = event.metadata
      .sorted { $0.key < $1.key }
      .map { "\($0.key)=\($0.value)" }
      .joined(separator: "\n")
    let publicText = [
      event.id,
      event.messageId,
      event.content,
      event.contentRef,
      event.conversationTitle,
      event.topicHints.sorted().joined(separator: "\n"),
      metadata
    ].joined(separator: "\n")

    for secret in secrets where !secret.isEmpty {
      XCTAssertFalse(
        publicText.contains(secret),
        "Capability observation exposed secret: \(secret)",
        file: file,
        line: line
      )
    }
  }

  func runStartRequest(
    conversationId: String = "conversation",
    messageId: String = "message",
    taskId: String = "task",
    runId: String = "run",
    parentRunId: String = "",
    goal: String = "execute once",
    deliveryMode: AgentDeliveryMode = .respond,
    requiredCapabilities: Set<AgentCapability> = [.chat, .code],
    context: AgentMcpJSONObject = ["z": .int(2), "a": .string("x")],
    idempotencyKey: String = "key",
    createdAtMillis: Int64 = 0
  ) -> AgentRunRequest {
    AgentRunRequest(
      conversationId: conversationId,
      messageId: messageId,
      taskId: taskId,
      runId: runId,
      parentRunId: parentRunId,
      goal: goal,
      deliveryMode: deliveryMode,
      requiredCapabilities: requiredCapabilities,
      context: context,
      idempotencyKey: idempotencyKey,
      createdAtMillis: createdAtMillis
    )
  }

  func teamBridgePlan(_ actions: AgentAction...) -> AgentPlan {
    teamBridgePlan(goal: "Research and synthesize a verified answer", actions)
  }

  func teamBridgePlan(goal: String, _ actions: AgentAction...) -> AgentPlan {
    teamBridgePlan(goal: goal, actions)
  }

  func teamBridgePlan(goal: String, _ actions: [AgentAction]) -> AgentPlan {
    var plan = AgentPlan(
      goal: goal,
      screen: AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent"),
      steps: [],
      actions: actions,
      route: AgentRoute(kind: .desktopAgent)
    )
    plan.validation = AgentPlanValidator.validate(plan)
    return plan
  }

  func teamAgentAction(
    _ id: String,
    _ connectorId: String,
    dependsOn: [String] = [],
    outputSources: [String] = []
  ) -> AgentAction {
    teamConnectorAction(id, connectorId, kind: .agent, dependsOn: dependsOn, outputSources: outputSources)
  }

  func teamConnectorAction(
    _ id: String,
    _ connectorId: String,
    kind: AgentConnectorKind = .agent,
    dependsOn: [String] = [],
    outputSources: [String] = []
  ) -> AgentAction {
    AgentAction(
      id: id,
      kind: .callConnector,
      target: connectorId,
      risk: .medium,
      status: .pendingConfirmation,
      description: "Run \(id)",
      parameters: [
        "connector_id": connectorId,
        "prompt": "Complete \(id)",
        "node_ref": id,
        "depends_on": dependsOn.joined(separator: ","),
        "use_outputs_from": outputSources.joined(separator: ","),
        "_galaxyssi_conversation_id": "conversation",
        "_galaxyssi_turn_id": "turn",
        "connector_kind": kind.rawValue
      ]
    )
  }

  func teamActionWithAgentKnowledge(_ action: AgentAction, _ value: String) -> AgentAction {
    var copy = action
    copy.parameters["_galaxyssi_agent_knowledge_context"] = value
    return copy
  }

  func teamTargets() -> [AgentCallableTarget] {
    [
      teamTarget("researcher", kind: .agent, capability: .research),
      teamTarget("reviewer", kind: .agent, capability: .research),
      teamTarget("lead", kind: .agent, capability: .reasoning)
    ]
  }

  func teamTarget(
    _ id: String,
    kind: AgentConnectorKind,
    capability: AgentCapability = .chat
  ) -> AgentCallableTarget {
    AgentCallableTarget(
      id: id,
      title: id,
      kind: kind,
      status: .available,
      capabilities: [capability]
    )
  }

  func teamRegistration(_ target: AgentCallableTarget) -> AgentRegistration {
    networkRegistration(
      agentId: target.id,
      displayName: target.title,
      capabilities: Set(target.capabilities),
      failureDomain: target.failureDomain,
      adapterType: target.adapterType
    )
  }

  private var crossTeamNow: Int64 { 2_000_000 }
  private var crossTeamSourceTeam: String { "team-source" }
  private var crossTeamDestinationTeamId: String { "team-destination" }

  func crossTeamFixture() -> CrossTeamFixture {
    let grants = InMemoryAgentPermissionGrantStore(nowMillis: { self.crossTeamNow })
    let firewall = AgentPersonalPolicyFirewall(
      grantStore: grants,
      replayStore: InMemoryAgentPolicyReplayStore(),
      auditStore: InMemoryAgentPolicyFirewallAuditStore(),
      clock: { self.crossTeamNow }
    )
    return CrossTeamFixture(
      grants: grants,
      coordinator: AgentCrossTeamDelegationCoordinator(
        firewall: firewall,
        store: InMemoryAgentCrossTeamDelegationStore(),
        clock: { self.crossTeamNow }
      )
    )
  }

  func crossTeamInput(
    delegationId: String = "delegation-one",
    nonce: String = "delegation-nonce-0001",
    goal: String = "Complete the delegated analysis",
    constraints: [String] = [],
    expectedOutput: String = "",
    evidence: [AgentDelegationEvidence] = [],
    artifacts: [AgentDelegationArtifactManifest] = [],
    delegationDepth: Int = 1,
    secureTransport: Bool = true
  ) -> AgentCrossTeamDelegationInput {
    AgentCrossTeamDelegationInput(
      delegationId: delegationId,
      nonce: nonce,
      sourceTeamId: crossTeamSourceTeam,
      sourceRunId: "source-run",
      requesterAgentId: "galaxyssi-mobile",
      goal: goal,
      constraints: constraints,
      expectedOutput: expectedOutput,
      requiredCapabilities: [.chat],
      evidence: evidence,
      artifacts: artifacts,
      delegationDepth: delegationDepth,
      secureTransport: secureTransport,
      identityProofVerified: true,
      createdAtMillis: crossTeamNow,
      expiresAtMillis: crossTeamNow + 60_000
    )
  }

  func crossTeamDestinationTeam(includeObserver: Bool = false) -> AgentTeamDefinition {
    var members = [
      AgentTeamMember(
        agentId: "codex-destination",
        deliveryMode: .respond,
        requiredCapabilities: [.chat],
        role: "lead synthesizer",
        objective: "",
        dependsOnAgentIds: [],
        context: [:]
      )
    ]
    if includeObserver {
      members.append(AgentTeamMember(
        agentId: "hermes-observer",
        deliveryMode: .observe,
        requiredCapabilities: [],
        role: "research specialist",
        objective: "",
        dependsOnAgentIds: [],
        context: [:]
      ))
    }
    return AgentTeamDefinition(
      teamId: crossTeamDestinationTeamId,
      primaryAgentId: "codex-destination",
      members: members,
      visibilityMode: .background,
      collectiveCapabilities: [.chat]
    )
  }

  func crossTeamRegistrations(includeObserver: Bool = false) -> [AgentRegistration] {
    var registrations = [
      networkRegistration(
        agentId: "codex-destination",
        displayName: "codex-destination",
        providerId: "codex",
        deviceId: "device-codex-destination",
        capabilities: [.chat],
        trust: .verifiedPaired
      )
    ]
    if includeObserver {
      registrations.append(networkRegistration(
        agentId: "hermes-observer",
        displayName: "hermes-observer",
        providerId: "hermes",
        deviceId: "device-hermes-observer",
        capabilities: [.chat],
        trust: .verifiedPaired
      ))
    }
    return registrations
  }

  func crossTeamGrant(
    subjectId: String,
    lifetime: AgentPermissionGrantLifetime
  ) -> AgentPermissionGrant {
    AgentPermissionGrant(
      grantId: "grant-\(subjectId)",
      subjectType: .agent,
      subjectId: subjectId,
      scope: AgentPersonalPolicyFirewall.DELEGATION_SCOPE,
      action: "outbound",
      resource: crossTeamSourceTeam,
      target: crossTeamDestinationTeamId,
      issuer: .user,
      evidence: "user-confirmed",
      lifetime: lifetime,
      maxUses: lifetime == .singleUse ? 1 : 0,
      createdAtMillis: crossTeamNow,
      expiresAtMillis: lifetime == .temporary ? crossTeamNow + 60_000 : 0
    )
  }

  private struct CrossTeamFixture {
    var grants: InMemoryAgentPermissionGrantStore
    var coordinator: AgentCrossTeamDelegationCoordinator
  }

  func riskHardenerAction(
    id: String,
    kind: AgentActionKind,
    risk: AgentRisk = .low,
    target: String = "iOS",
    description: String? = nil,
    parameters: [String: String] = [:]
  ) -> AgentAction {
    AgentAction(
      id: id,
      kind: kind,
      target: target,
      risk: risk,
      status: .pendingConfirmation,
      description: description ?? "Harden \(id)",
      parameters: parameters
    )
  }

  func riskHardenerPlan(_ actions: [AgentAction]) -> AgentPlan {
    var plan = AgentPlan(
      goal: "Harden action risks",
      screen: AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent"),
      steps: [],
      actions: actions,
      route: AgentRoute(kind: .deviceConnector)
    )
    plan.validation = AgentPlanValidator.validate(plan)
    return plan
  }

  func agentScreenElement(
    label: String,
    viewId: String,
    className: String,
    bounds: String,
    origin: AgentElementOrigin = .accessibility,
    confidence: Double = 1,
    visualRole: AgentVisualRole = .unknown,
    actionable: Bool = true
  ) -> AgentScreenElement {
    AgentScreenElement(
      label: label,
      viewId: viewId,
      className: className,
      bounds: bounds,
      origin: origin,
      confidence: confidence,
      visualRole: visualRole,
      actionable: actionable
    )
  }

  func assertToolHandleError(
    _ code: String,
    retryable: Bool = false,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ body: () throws -> Void
  ) {
    do {
      try body()
      XCTFail("Expected AgentExplicitToolHandleError.", file: file, line: line)
    } catch let error as AgentExplicitToolHandleError {
      XCTAssertEqual(error.code, code, file: file, line: line)
      XCTAssertEqual(error.retryable, retryable, file: file, line: line)
    } catch {
      XCTFail("Unexpected error: \(error)", file: file, line: line)
    }
  }

  func agentRecoveryAction(
    id: String,
    kind: AgentActionKind,
    risk: AgentRisk
  ) -> AgentAction {
    AgentAction(
      id: id,
      kind: kind,
      target: "iOS",
      risk: risk,
      status: .failed,
      description: "Recover \(kind.rawValue)"
    )
  }

  func phoneAuthorityAction(
    id: String,
    kind: AgentActionKind,
    taskId: String
  ) -> AgentAction {
    AgentAction(
      id: id,
      kind: kind,
      target: "GalaxySSI",
      risk: .low,
      status: .pendingConfirmation,
      description: id,
      parameters: ["_galaxyssi_task_id": taskId]
    )
  }

  func phoneAuthorityScreen() -> AgentScreenContext {
    AgentScreenContext(
      foregroundApp: "GalaxySSI",
      pageTitle: "Agent",
      visibleTextCount: 3,
      clickableNodeCount: 2,
      isAccessibilityEnabled: true
    )
  }

  func nativeToolDescriptor(
    _ id: String,
    risk: AgentNativeToolRisk = .low,
    availability: AgentNativeToolAvailability = .available,
    capabilities: Set<String> = ["test.execute"],
    requiredPermissions: [AgentNativePermissionRequirement] = [],
    requiredConsents: [AgentNativeConsentRequirement] = [],
    inputSchema: AgentMcpJSONObject = AgentNativeToolDescriptor.objectSchema(),
    outputSchema: AgentMcpJSONObject = AgentNativeToolDescriptor.objectSchema(),
    timeoutMillis: Int64 = AgentNativeToolDescriptor.defaultTimeoutMillis,
    idempotency: AgentNativeToolIdempotency = .nonIdempotent
  ) throws -> AgentNativeToolDescriptor {
    try AgentNativeToolDescriptor(
      id: id,
      version: "1.0.0",
      title: id,
      description: "Test capability",
      location: .application,
      inputSchema: inputSchema,
      outputSchema: outputSchema,
      risk: risk,
      capabilities: capabilities,
      requiredPermissions: requiredPermissions,
      requiredConsents: requiredConsents,
      timeoutMillis: timeoutMillis,
      idempotency: idempotency,
      availability: availability
    )
  }

  func readyPhoneCapabilityStatuses() -> [AgentPhoneCapabilityStatus] {
    AgentPhoneCapabilityCatalog.capabilities.map { boundary in
      AgentPhoneCapabilityStatus(
        boundary: boundary,
        availability: .ready,
        evidence: "Ready for test"
      )
    }
  }

  func nativeToolResult(
    status: AgentNativeToolResultStatus = .succeeded,
    invocationId: String,
    idempotencyKey: String?,
    replayed: Bool = false,
    verification: AgentNativeToolVerification? = nil
  ) -> AgentNativeToolResult {
    AgentNativeToolResult(
      status: status,
      output: [
        "ok": .bool(status == .succeeded),
        "invocation_id": .string(invocationId)
      ],
      message: status == .succeeded ? "Done" : "Failed",
      metadata: ["platform": .string("ios")],
      error: status == .succeeded ? nil : AgentNativeToolError(
        code: "test_failure",
        message: "Failed",
        retryable: false
      ),
      verification: verification,
      receipt: AgentNativeToolReceipt(
        invocationId: invocationId,
        idempotencyKey: idempotencyKey,
        startedAtEpochMillis: 1_000,
        finishedAtEpochMillis: 1_050,
        durationMillis: 50,
        status: status,
        inputSha256: String(repeating: "a", count: 64),
        outputSha256: String(repeating: "b", count: 64),
        replayed: replayed
      ),
      provenance: AgentNativeToolProvenance(
        toolId: "galaxyssi.test.native",
        toolVersion: "1.0.0",
        location: .application,
        executorId: "ios-native",
        contractVersion: "galaxyssi.native-tool/1.0",
        metadata: ["platform": "ios"]
      )
    )
  }

  func agentObservation(
    _ decision: AgentObservationDecision,
    sampleCount: Int = 1,
    durationMillis: Int64 = 0,
    changed: Bool = false,
    stable: Bool = false
  ) -> AgentObservationOutcome {
    AgentObservationOutcome(
      screen: AgentScreenContext(
        foregroundApp: "SpringBoard",
        pageTitle: "Home",
        visibleTextCount: 3,
        clickableNodeCount: 2,
        isAccessibilityEnabled: true
      ),
      decision: decision,
      sampleCount: sampleCount,
      durationMillis: durationMillis,
      screenChanged: changed,
      screenStable: stable,
      evidence: "decision=\(decision.rawValue); samples=\(sampleCount)"
    )
  }

  func agentObservationScreen(
    pageTitle: String,
    visibleTextCount: Int,
    selectedText: String = "",
    clickableNodeCount: Int = 2,
    inputFieldCount: Int = 0,
    scrollableRegionCount: Int = 0
  ) -> AgentScreenContext {
    AgentScreenContext(
      foregroundApp: "SpringBoard",
      activityName: "MainActivity",
      pageTitle: pageTitle,
      visibleTextCount: visibleTextCount,
      clickableNodeCount: clickableNodeCount,
      inputFieldCount: inputFieldCount,
      scrollableRegionCount: scrollableRegionCount,
      selectedText: selectedText,
      isAccessibilityEnabled: true
    )
  }

  func agentLivenessPolicy() -> AgentTaskLivenessPolicy {
    AgentTaskLivenessPolicy(
      queuedWarningMillis: 10,
      queuedTimeoutMillis: 20,
      runningWarningMillis: 100,
      runningTimeoutMillis: 200,
      waitingResponseWarningMillis: 300,
      waitingResponseTimeoutMillis: 400,
      absoluteTimeoutMillis: 1_000,
      watchdogIntervalMillis: 60_000,
      heartbeatWriteThrottleMillis: 0
    )
  }

  func runtimeCatalog(
    now: Int64,
    entries: [AgentRuntimePackCatalogEntry]
  ) -> AgentRuntimePackCatalog {
    AgentRuntimePackCatalog(
      catalogVersion: "1.0.0",
      generatedAtMillis: now - 1_000,
      expiresAtMillis: now + 60_000,
      entries: entries,
      signatureKeyId: String(repeating: "a", count: 64),
      signature: "signed"
    )
  }

  func runtimeCatalogEntry(
    packId: String,
    architecture: String,
    dependencies: [String] = []
  ) -> AgentRuntimePackCatalogEntry {
    AgentRuntimePackCatalogEntry(
      packId: packId,
      version: "1.0.0",
      architecture: architecture,
      downloadUrl: "https://downloads.example.com/\(packId).sarpack",
      archiveSha256: String(repeating: "b", count: 64),
      archiveSizeBytes: 1_024,
      installedSizeBytes: 2_048,
      dependencies: dependencies,
      license: "Apache-2.0",
      minimumHostVersionCode: 1,
      guestApiVersion: AgentRuntimeGuestProtocol.version
    )
  }

  func embeddedRuntimeIndexJson() -> String {
    let architecture = AgentRuntimePackCatalogPolicy.defaultSupportedArchitectures.first ?? "arm64"
    """
    {"format_version":1,"architecture":"\(architecture)","packs":[
      {"pack_id":"linux-base","version":"1.0.0","architecture":"\(architecture)","asset_path":"runtime/bootstrap/linux-base.sarpack","archive_sha256":"\(String(repeating: "A", count: 64))","archive_size_bytes":1024,"installed_size_bytes":2048,"dependencies":[]},
      {"pack_id":"python-uv","version":"1.0.0","architecture":"\(architecture)","asset_path":"runtime/bootstrap/python-uv.sarpack","archive_sha256":"\(String(repeating: "b", count: 64))","archive_size_bytes":2048,"installed_size_bytes":4096,"dependencies":["linux-base"]}
    ]}
    """
  }

  func agentWorkspace(
    status: AgentWorkspaceStatus,
    events: [AgentWorkspaceEvent] = [],
    cancellationRequested: Bool = false
  ) -> AgentWorkspace {
    AgentWorkspace(
      workspaceId: "workspace",
      sessionId: "session",
      conversationId: "conversation",
      taskId: "task",
      status: status,
      eventSequence: events.map(\.sequence).max() ?? 0,
      eventJournal: events,
      cancellationRequested: cancellationRequested,
      createdAtMillis: 1_000,
      updatedAtMillis: events.map(\.timestampMillis).max() ?? 1_000
    )
  }

  func agentWorkspaceEvent(
    _ sequence: Int64,
    _ kind: String,
    _ timestampMillis: Int64
  ) -> AgentWorkspaceEvent {
    AgentWorkspaceEvent(
      sequence: sequence,
      kind: kind,
      timestampMillis: timestampMillis
    )
  }

  func lifecycleAction(
    id: String,
    kind: AgentActionKind,
    target: String,
    status: AgentActionStatus,
    result: String = ""
  ) -> AgentAction {
    AgentAction(
      id: id,
      kind: kind,
      target: target,
      risk: .low,
      status: status,
      description: id,
      result: result
    )
  }

  func lifecyclePlan(_ actions: AgentAction...) -> AgentPlan {
    let needsRoute = actions.contains {
      $0.kind == .callConnector || $0.kind == .controlDevice
    }
    return AgentPlan(
      goal: "Correct the worksheet",
      screen: AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent"),
      steps: [],
      actions: actions,
      route: needsRoute ? AgentRoute(kind: .desktopAgent, targetTitle: "Codex") : AgentRoute()
    )
  }

  func lifecycleSession(
    phase: AgentPhase,
    plan: AgentPlan,
    result: AgentActionResult?,
    auditTrail: [AgentAuditEntry] = []
  ) -> AgentSessionSnapshot {
    AgentSessionSnapshot(
      sessionId: "session",
      phase: phase,
      currentGoal: plan.goal,
      currentScreen: plan.screen,
      currentPlan: plan,
      auditTrail: auditTrail,
      lastActionResult: result,
      updatedAtMillis: 1
    )
  }

  func agentTaskRecord(
    taskId: String = "task",
    sessionId: String = "conversation",
    goal: String = "goal",
    phase: AgentPhase = .executing,
    routeKind: AgentRouteKind = .desktopAgent,
    targetTitle: String = "Codex",
    risk: AgentRisk = .low,
    blocked: Bool = false,
    result: String = "",
    verification: String = "",
    outputFiles: [String] = [],
    executionLog: [String] = [],
    createdAtMillis: Int64 = 1,
    updatedAtMillis: Int64 = 1
  ) -> AgentTaskRecord {
    AgentTaskRecord(
      taskId: taskId,
      sessionId: sessionId,
      goal: goal,
      phase: phase,
      routeKind: routeKind,
      targetTitle: targetTitle,
      risk: risk,
      blocked: blocked,
      result: result,
      verification: verification,
      outputFiles: outputFiles,
      executionLog: executionLog,
      createdAtMillis: createdAtMillis,
      updatedAtMillis: updatedAtMillis
    )
  }

  func terminalReplyTranscript(
    role: AgentTranscriptRole,
    dedupeKey: String,
    turnId: String,
    taskId: String? = nil
  ) -> AgentTranscriptEntry {
    AgentTranscriptEntry(
      id: "\(role.rawValue)-\(dedupeKey)",
      role: role,
      text: "message",
      timestampMillis: 1_000,
      dedupeKey: dedupeKey,
      conversationId: "conversation",
      turnId: turnId,
      taskId: taskId ?? turnId
    )
  }

  func agentConversation(
    id: String,
    title: String,
    summary: String = "",
    status: AgentConversationStatus = .active,
    createdByAgent: Bool = false,
    parentConversationId: String = "",
    privateMode: Bool = false,
    inputTokens: Int64 = 0,
    outputTokens: Int64 = 0,
    costMicros: Int64 = 0
  ) -> AgentConversation {
    AgentConversation(
      id: id,
      title: title,
      createdAt: 1,
      updatedAt: 1,
      summary: summary,
      status: status,
      privateMode: privateMode,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      costMicros: costMicros,
      createdByAgent: createdByAgent,
      parentConversationId: parentConversationId
    )
  }

  func agentMergeEntry(
    id: String,
    role: AgentTranscriptRole,
    conversationId: String,
    text: String,
    dedupeKey: String = "",
    richOutputJson: String = ""
  ) -> AgentTranscriptEntry {
    AgentTranscriptEntry(
      id: id,
      role: role,
      text: text,
      timestampMillis: Int64(id.count),
      dedupeKey: dedupeKey,
      conversationId: conversationId,
      turnId: "turn",
      taskId: "task",
      richOutputJson: richOutputJson
    )
  }

  func loopEvent(
    _ phase: AgentExecutionLoopPhase,
    previousPhase: AgentExecutionLoopPhase? = nil,
    actionId: String = "",
    toolCall: Bool = false,
    retry: Bool = false,
    revision: Int64 = 1,
    usage: AgentExecutionLoopUsage = AgentExecutionLoopUsage(),
    reason: String = ""
  ) -> AgentExecutionLoopEvent {
    AgentExecutionLoopEvent(
      previousPhase: previousPhase,
      phase: phase,
      reason: reason,
      snapshot: AgentExecutionLoopSnapshot(
        taskId: "task",
        phase: phase,
        usage: usage,
        lastActionId: actionId,
        startedAtMillis: 1_000,
        updatedAtMillis: 1_000,
        revision: revision
      ),
      toolCall: toolCall,
      retry: retry
    )
  }

  func runControlEvent(
    type: AgentRunControlEventType,
    toolCallId: String = "",
    sequence: Int64 = 1,
    payload: AgentRunControlPayload = [:]
  ) -> AgentRunControlEvent {
    AgentRunControlEvent(
      eventId: "event",
      conversationId: "conversation",
      messageId: "turn",
      taskId: "task",
      runId: "run",
      toolCallId: toolCallId,
      agentId: "galaxyssi-mobile",
      deviceId: "phone",
      type: type,
      sequence: sequence,
      payload: payload
    )
  }

  func runControlSnapshot(
    state: AgentRunControlState,
    sequence: Int64 = 4
  ) -> AgentRunControlSnapshot {
    AgentRunControlSnapshot(
      runId: "run",
      taskId: "task",
      state: state,
      agentId: "codex",
      deviceId: "desktop",
      lastSequence: sequence,
      lastEvent: runControlEvent(type: .waitingForDevice, sequence: sequence)
    )
  }

  func runRecoveryRegistration(
    agentId: String = "codex",
    location: AgentResourceLocation = .trustedDesktop,
    connectionKind: AgentConnectionKind = .galaxyssiLink
  ) -> AgentRunRecoveryRegistration {
    AgentRunRecoveryRegistration(
      agentId: agentId,
      location: location,
      connectionKind: connectionKind
    )
  }

  func proactiveIntervalTask(
    taskId: String = "test-task",
    policy: AgentProactivePolicy,
    nextRunAtMillis: Int64,
    runCount: Int = 0,
    consecutiveFailures: Int = 0
  ) throws -> AgentProactiveTask {
    try AgentProactiveTask(
      taskId: taskId,
      name: "Test task",
      trigger: try AgentProactiveTrigger(
        kind: .interval,
        intervalSeconds: 60
      ),
      action: try AgentProactiveAction(
        kind: .agent,
        targetId: "codex",
        prompt: "Check status"
      ),
      policy: policy,
      nextRunAtMillis: nextRunAtMillis,
      runCount: runCount,
      consecutiveFailures: consecutiveFailures
    )
  }

  func globalProactiveMessage(
    _ id: String,
    target: GlobalProactiveTarget = .currentConversation,
    status: GlobalProactiveMessageStatus = .delivered,
    title: String = "GalaxySSI insight",
    content: String = "A material result is ready.",
    topic: String = "GalaxySSI autonomy",
    urgent: Bool = false,
    deliveredAtMillis: Int64 = 2_000,
    deliveredConversationId: String = "destination",
    deliveryGroupId: String? = nil,
    viewedAtMillis: Int64 = 0
  ) -> GlobalProactiveMessage {
    GlobalProactiveMessage(
      id: id,
      sourceEventId: "event-\(id)",
      sourceConversationId: "source",
      target: target,
      title: title,
      content: content,
      topic: topic,
      urgent: urgent,
      status: status,
      createdAtMillis: 1_000,
      deliveredAtMillis: deliveredAtMillis,
      deliveredConversationId: deliveredConversationId,
      deliveryGroupId: deliveryGroupId ?? id,
      viewedAtMillis: viewedAtMillis
    )
  }

  func globalAgentFeedback(
    messageId: String,
    kind: GlobalAgentFeedbackKind,
    createdAtMillis: Int64 = 3_000
  ) -> GlobalAgentFeedback {
    GlobalAgentFeedback(
      proactiveMessageId: messageId,
      deliveryGroupId: messageId,
      conversationId: "destination",
      topic: "GalaxySSI autonomy",
      target: .currentConversation,
      kind: kind,
      createdAtMillis: createdAtMillis
    )
  }

  func mcpAuditRecord(
    _ auditId: String,
    connectionId: String,
    timestampMillis: Int64
  ) -> AgentMcpAuditRecord {
    AgentMcpAuditRecord(
      auditId: auditId,
      timestampMillis: timestampMillis,
      connectionId: connectionId,
      connectionName: "Relay",
      toolName: "relay.switch",
      transport: "streamable_http",
      source: "ios-mcp:\(connectionId)",
      callerId: "planner",
      taskId: "task-\(auditId)",
      conversationId: "chat",
      risk: "medium",
      permissions: ["mcp.network.connect", "mcp.data.write"],
      permissionMode: "ask_for_changes",
      permissionDecision: "allowed_explicit_change",
      parameterPreview: ["enabled": .bool(true)],
      inputSha256: String(repeating: "a", count: 64),
      status: "succeeded",
      durationMillis: 10
    )
  }

  func mcpTool(
    _ name: String,
    readOnly: Bool? = nil,
    destructive: Bool? = nil
  ) -> AgentMcpTool {
    var annotations: AgentMcpJSONObject = [:]
    if let readOnly {
      annotations["readOnlyHint"] = .bool(readOnly)
    }
    if let destructive {
      annotations["destructiveHint"] = .bool(destructive)
    }
    return AgentMcpTool(
      name: name,
      inputSchema: [:],
      annotations: annotations,
      raw: ["name": .string(name)]
    )
  }

  func mcpDeclarativePackageManifest() -> String {
    #"""
    {
      "format_version": 1,
      "id": "example.relay",
      "version": "1.0.0",
      "name": "Relay Controller",
      "description": "Authenticated relay control",
      "catalog_id": "galaxyssi.mcp.relay",
      "author": "GalaxySSI",
      "website": "https://relay.example",
      "transport": {
        "type": "declarative_http",
        "endpoint": "https://relay.example/api/"
      },
      "authentication": [
        {
          "method": "dynamic",
          "access_token_ttl_seconds": 86400,
          "steps": [
            {
              "id": "login",
              "title": "Sign in",
              "fields": [
                {"id": "username", "label": "Username", "type": "text"},
                {"id": "password", "label": "Password", "type": "password"}
              ],
              "exchange": {
                "method": "POST",
                "path": "/api/login",
                "body_template": "{\"username\":{{field.username}},\"password\":{{field.password}}}",
                "response_mappings": {
                  "access_token": "$.session.access_token"
                },
                "accepted_status_codes": [200, 201]
              }
            }
          ]
        }
      ],
      "tools": [
        {
          "name": "relay.switch",
          "title": "Switch relay",
          "description": "Turns a relay on or off",
          "input_schema": {
            "type": "object",
            "properties": {
              "device_id": {"type": "string"},
              "enabled": {"type": "boolean"}
            },
            "required": ["device_id", "enabled"]
          },
          "request": {
            "method": "POST",
            "path": "/api/relay/{{args.device_id}}",
            "headers": {
              "Authorization": "Bearer {{auth.access_token}}"
            },
            "body_template": "{\"enabled\":{{args.enabled}}}"
          },
          "result_json_path": "$.relay",
          "mutating": true
        }
      ]
    }
    """#
  }

  func mcpLocalStdioPackageManifest(
    entrypoint: String = "runtime/server.py",
    authentication: String = #"[{"method":"bearer_token"}]"#,
    allowedNetworkDomains: String = ""
  ) -> String {
    let domains = allowedNetworkDomains.isEmpty ? "[]" : "[\(allowedNetworkDomains)]"
    return #"""
    {
      "format_version": 1,
      "id": "example.local_mcp",
      "version": "1.0.0",
      "name": "Local MCP",
      "description": "Runs inside the on-device Linux sandbox",
      "transport": {
        "type": "local_stdio",
        "runtime": "python",
        "entrypoint": "\#(entrypoint)",
        "arguments": ["--stdio"],
        "environment": {
          "ACCESS_TOKEN": "{{auth.access_token}}"
        },
        "allowed_network_domains": \#(domains),
        "timeout_ms": 45000
      },
      "authentication": \#(authentication),
      "tools": []
    }
    """#
  }

  func mcpPackageIntegrity(for manifest: String) -> String {
    let digest = AgentMcpPackageInstaller.sha256(Data(manifest.utf8))
    return #"{"manifest_sha256":"\#(digest)"}"#
  }

  func temporaryDirectory(_ label: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("galaxyssi-\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }

  func relativeFile(_ relative: String, under root: URL) -> URL {
    relative
      .split(separator: "/")
      .map(String.init)
      .reduce(root) { partial, segment in
        partial.appendingPathComponent(segment)
      }
  }

  func storedMcpPackage(_ files: (String, String)...) -> Data {
    var output = Data()
    var centralRecords: [(name: String, data: Data, crc32: UInt32, localOffset: Int)] = []
    for file in files {
      let nameBytes = Data(file.0.utf8)
      let body = Data(file.1.utf8)
      let crc = mcpPackageCRC32(body)
      let size = UInt32(body.count)
      let localOffset = output.count
      appendMcpZipUInt32LE(0x04034b50, to: &output)
      appendMcpZipUInt16LE(20, to: &output)
      appendMcpZipUInt16LE(0x0800, to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      appendMcpZipUInt32LE(crc, to: &output)
      appendMcpZipUInt32LE(size, to: &output)
      appendMcpZipUInt32LE(size, to: &output)
      appendMcpZipUInt16LE(UInt16(nameBytes.count), to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      output.append(nameBytes)
      output.append(body)
      centralRecords.append((file.0, body, crc, localOffset))
    }
    let centralStart = output.count
    for record in centralRecords {
      let nameBytes = Data(record.name.utf8)
      let size = UInt32(record.data.count)
      appendMcpZipUInt32LE(0x02014b50, to: &output)
      appendMcpZipUInt16LE(20, to: &output)
      appendMcpZipUInt16LE(20, to: &output)
      appendMcpZipUInt16LE(0x0800, to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      appendMcpZipUInt32LE(record.crc32, to: &output)
      appendMcpZipUInt32LE(size, to: &output)
      appendMcpZipUInt32LE(size, to: &output)
      appendMcpZipUInt16LE(UInt16(nameBytes.count), to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      appendMcpZipUInt32LE(0, to: &output)
      appendMcpZipUInt32LE(UInt32(record.localOffset), to: &output)
      output.append(nameBytes)
    }
    let centralSize = output.count - centralStart
    appendMcpZipUInt32LE(0x06054b50, to: &output)
    appendMcpZipUInt16LE(0, to: &output)
    appendMcpZipUInt16LE(0, to: &output)
    appendMcpZipUInt16LE(UInt16(centralRecords.count), to: &output)
    appendMcpZipUInt16LE(UInt16(centralRecords.count), to: &output)
    appendMcpZipUInt32LE(UInt32(centralSize), to: &output)
    appendMcpZipUInt32LE(UInt32(centralStart), to: &output)
    appendMcpZipUInt16LE(0, to: &output)
    return output
  }

  func deflatedZipArchive(_ files: (String, String)...) -> Data {
    var output = Data()
    var centralRecords: [(name: String, body: Data, compressed: Data, crc32: UInt32, localOffset: Int)] = []
    for file in files {
      let nameBytes = Data(file.0.utf8)
      let body = Data(file.1.utf8)
      let compressed = rawDeflateStoredBlocks(body)
      let crc = mcpPackageCRC32(body)
      let localOffset = output.count
      appendMcpZipUInt32LE(0x04034b50, to: &output)
      appendMcpZipUInt16LE(20, to: &output)
      appendMcpZipUInt16LE(0x0800, to: &output)
      appendMcpZipUInt16LE(8, to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      appendMcpZipUInt32LE(crc, to: &output)
      appendMcpZipUInt32LE(UInt32(compressed.count), to: &output)
      appendMcpZipUInt32LE(UInt32(body.count), to: &output)
      appendMcpZipUInt16LE(UInt16(nameBytes.count), to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      output.append(nameBytes)
      output.append(compressed)
      centralRecords.append((file.0, body, compressed, crc, localOffset))
    }
    let centralStart = output.count
    for record in centralRecords {
      let nameBytes = Data(record.name.utf8)
      appendMcpZipUInt32LE(0x02014b50, to: &output)
      appendMcpZipUInt16LE(20, to: &output)
      appendMcpZipUInt16LE(20, to: &output)
      appendMcpZipUInt16LE(0x0800, to: &output)
      appendMcpZipUInt16LE(8, to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      appendMcpZipUInt32LE(record.crc32, to: &output)
      appendMcpZipUInt32LE(UInt32(record.compressed.count), to: &output)
      appendMcpZipUInt32LE(UInt32(record.body.count), to: &output)
      appendMcpZipUInt16LE(UInt16(nameBytes.count), to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      appendMcpZipUInt32LE(0, to: &output)
      appendMcpZipUInt32LE(UInt32(record.localOffset), to: &output)
      output.append(nameBytes)
    }
    let centralSize = output.count - centralStart
    appendMcpZipUInt32LE(0x06054b50, to: &output)
    appendMcpZipUInt16LE(0, to: &output)
    appendMcpZipUInt16LE(0, to: &output)
    appendMcpZipUInt16LE(UInt16(centralRecords.count), to: &output)
    appendMcpZipUInt16LE(UInt16(centralRecords.count), to: &output)
    appendMcpZipUInt32LE(UInt32(centralSize), to: &output)
    appendMcpZipUInt32LE(UInt32(centralStart), to: &output)
    appendMcpZipUInt16LE(0, to: &output)
    return output
  }

  func rawDeflateStoredBlocks(_ data: Data) -> Data {
    var output = Data()
    var offset = 0
    repeat {
      let count = min(data.count - offset, 0xffff)
      let finalBlock = offset + count == data.count
      output.append(finalBlock ? 0x01 : 0x00)
      appendMcpZipUInt16LE(UInt16(count), to: &output)
      appendMcpZipUInt16LE(~UInt16(count), to: &output)
      output.append(data.subdata(in: offset..<(offset + count)))
      offset += count
    } while offset < data.count
    return output
  }

  func appendMcpZipUInt16LE(_ value: UInt16, to data: inout Data) {
    data.append(UInt8(value & 0x00ff))
    data.append(UInt8((value >> 8) & 0x00ff))
  }

  func appendMcpZipUInt32LE(_ value: UInt32, to data: inout Data) {
    data.append(UInt8(value & 0x000000ff))
    data.append(UInt8((value >> 8) & 0x000000ff))
    data.append(UInt8((value >> 16) & 0x000000ff))
    data.append(UInt8((value >> 24) & 0x000000ff))
  }

  func mcpPackageCRC32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xffffffff
    for byte in data {
      let index = Int((crc ^ UInt32(byte)) & 0xff)
      crc = (crc >> 8) ^ Self.mcpPackageCRC32Table[index]
    }
    return crc ^ 0xffffffff
  }

  private static let mcpPackageCRC32Table: [UInt32] = {
    (0..<256).map { value -> UInt32 in
      var crc = UInt32(value)
      for _ in 0..<8 {
        if crc & 1 == 1 {
          crc = (crc >> 1) ^ 0xedb88320
        } else {
          crc >>= 1
        }
      }
      return crc
    }
  }()

  func transcriptEntry(
    _ id: String,
    role: AgentTranscriptRole = .process,
    conversationId: String = "conversation",
    turnId: String = "turn",
    timestampMillis: Int64 = 1,
    text: String? = nil,
    dedupeKey: String = "",
    taskId: String = "task",
    richOutputJson: String = ""
  ) -> AgentTranscriptEntry {
    AgentTranscriptEntry(
      id: id,
      role: role,
      text: text ?? id,
      timestampMillis: timestampMillis,
      dedupeKey: dedupeKey,
      conversationId: conversationId,
      turnId: turnId,
      taskId: taskId,
      richOutputJson: richOutputJson
    )
  }

  func richDocument(_ blocks: [[String: Any]]) -> String {
    let data = try! JSONSerialization.data(
      withJSONObject: ["version": 1, "blocks": blocks],
      options: [.sortedKeys]
    )
    return String(decoding: data, as: UTF8.self)
  }

  func richBlocks(_ raw: String) throws -> [[String: Any]] {
    let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
    return try XCTUnwrap(payload["blocks"] as? [[String: Any]])
  }

  func finalTranscriptEntry(
    id: String,
    role: AgentTranscriptRole = .assistant,
    text: String = "CODEX_OK",
    turnId: String = "",
    taskId: String,
    dedupeKey: String,
    timestampMillis: Int64,
    richOutputJson: String = ""
  ) -> AgentTranscriptEntry {
    AgentTranscriptEntry(
      id: id,
      role: role,
      text: text,
      timestampMillis: timestampMillis,
      dedupeKey: dedupeKey,
      conversationId: "conversation",
      turnId: turnId,
      taskId: taskId,
      richOutputJson: richOutputJson
    )
  }

  func makeFriendRequest(galaxySSIId: String, name: String) -> GalaxySSIFriendRequest {
    GalaxySSIFriendRequest(
      id: "req-\(galaxySSIId)",
      galaxySSIId: galaxySSIId,
      name: name,
      type: "person",
      identityPublicKey: "public-key-\(galaxySSIId)",
      identityFingerprint: String(repeating: "a", count: 64),
      mqttTopic: "galaxyssi/contact/\(galaxySSIId)",
      mqttInboxTopic: "galaxyssi/contact/\(galaxySSIId)/inbox"
    )
  }

  func makePairingQRCode() -> PairingQRCode {
    PairingQRCode(
      desktopId: "desktop-1",
      desktopName: "GalaxySSI Desktop",
      desktopFingerprint: String(repeating: "f", count: 64),
      pairingTopic: GalaxySSILinkProtocol.pairingTopic(
        secret: Data(repeating: 1, count: 32).base64URLEncodedString()
      ),
      pairingToken: String(repeating: "t", count: 43),
      pairingSecret: Data(repeating: 1, count: 32),
      access: PairingAccess(
        profile: GalaxySSILinkProtocol.accessDesktopExecutor,
        scopes: [GalaxySSILinkProtocol.scopeDesktopExecutor]
      ),
      controlAuthorizationToken: "control-token",
      raw: [:]
    )
  }
}
