import Foundation

struct AgentManagedBrowserDispatchBinding: Codable, Equatable {
  let owner: AgentCollaborationToolEvidenceScope
  let profileID: String
  let teamID: String
  let agentID: String
  let deliveryMode: AgentDeliveryMode
  let modelID: String
  let assignmentDigest: String
  let hostContextDigest: String

  init?(owner: AgentCollaborationToolEvidenceScope, team: AgentTeamExecutionSnapshot,
        profileID: String, modelID: String, hostContextDigest: String) {
    guard !profileID.isBlank, !modelID.isBlank, !hostContextDigest.isBlank,
          let member = Self.member(owner, in: team), team.state == .running,
          !member.status.isTerminal, !team.teamId.isBlank else { return nil }
    self.owner = owner
    self.profileID = profileID
    teamID = team.teamId
    agentID = member.agentId
    deliveryMode = member.deliveryMode
    self.modelID = modelID
    assignmentDigest = Self.assignment(member)
    self.hostContextDigest = hostContextDigest
  }

  var key: String {
    AgentMcpJSONCodec.sha256([
      "profile": .string(profileID), "run": .string(owner.runId), "team": .string(teamID),
      "conversation": .string(owner.conversationId), "turn": .string(owner.turnId),
      "member": .string(owner.memberId), "source": .string(owner.sourceId)
    ])
  }

  func matches(team: AgentTeamExecutionSnapshot, profileID: String, modelID: String,
               hostContextDigest: String) -> Bool {
    guard self.profileID == profileID, self.modelID == modelID, self.hostContextDigest == hostContextDigest,
          teamID == team.teamId, let member = Self.member(owner, in: team) else { return false }
    return member.agentId == agentID && member.deliveryMode == deliveryMode &&
      Self.assignment(member) == assignmentDigest
  }

  private static func member(_ owner: AgentCollaborationToolEvidenceScope,
                             in team: AgentTeamExecutionSnapshot) -> AgentTeamMemberSnapshot? {
    guard !owner.runId.isBlank, !owner.conversationId.isBlank, !owner.turnId.isBlank,
          !owner.memberId.isBlank, !owner.sourceId.isBlank, team.supervisorRunId == owner.runId,
          team.conversationId == owner.conversationId, team.taskId == owner.turnId else { return nil }
    return team.members.first {
      !$0.agentId.isBlank && $0.memberId == owner.memberId && $0.sourceMessageId == owner.sourceId &&
        $0.deliveryMode != .ignore && ($0.dispatchCheckpoint == .dispatching || $0.dispatchCheckpoint == .accepted)
    }
  }

  private static func assignment(_ member: AgentTeamMemberSnapshot) -> String {
    AgentMcpJSONCodec.sha256([
      "role": .string(member.role), "research_stage": member.researchStage.map(AgentMcpJSONValue.string) ?? .null,
      "dependencies": member.dispatchDependencyMemberIds.map { .array($0.sorted().map(AgentMcpJSONValue.string)) } ?? .null,
      "resources": member.dispatchResourceObservation.map(AgentMcpJSONValue.object) ?? .null
    ])
  }
}

struct AgentManagedBrowserLoopInput: Codable, Equatable {
  let loopID: String
  let inputIdentity: String
  let toolManifestHash: String
  let systemPrompt: String
  let prompt: String
  let hasAttachments: Bool

  var isValid: Bool {
    [loopID, inputIdentity, toolManifestHash].allSatisfy { !$0.isBlank && $0.utf8.count <= 256 } &&
      !prompt.isBlank && prompt.utf8.count <= 256 * 1_024 && systemPrompt.utf8.count <= 128 * 1_024
  }
}

struct AgentManagedBrowserHandoff: Codable, Equatable, Identifiable {
  struct Ticket: Codable, Equatable {
    let dispatchKey: String
    let callID: String
    let generation: UUID
  }

  struct Observation: Codable, Equatable {
    let address: String
    let title: String
    let text: String

    var isValid: Bool {
      !address.isBlank && address.utf8.count <= 4_096 && title.utf8.count <= 1_024 && text.utf8.count <= 16_384 &&
        AgentManagedBrowserHandoff.url(address) != nil
    }

    var toolOutput: AgentMcpJSONObject {
      var components = URLComponents(string: address)
      components?.query = nil
      components?.fragment = nil
      let publicAddress = components?.string ?? ""
      return [
        "state": .string("returned"), "control_owner": .string("agent"),
        "business_success_verified": .bool(false),
        "evidence": .object(AgentUntrustedEvidenceBoundary.markJson(sourceType: "browser_user_return",
          sourceId: AgentModelToolProtocolJSON.sha256(publicAddress),
          content: .object(["address": .string(publicAddress), "title": .string(title), "text": .string(text)])))
      ]
    }
  }

  enum State: String, Codable { case awaitingUser, returned, stopped }

  let ticket: Ticket
  let address: String
  let invocationID: String
  var state: State
  var observation: Observation?

  var id: UUID { ticket.generation }

  static func url(_ address: String) -> URL? {
    guard AgentIOSWebRenderURLPolicy.allows(address) else { return nil }
    return URLComponents(string: address)?.url
  }
}

struct AgentManagedBrowserMemberReceipt: Codable, Equatable {
  enum State: String, Codable { case completed, cancelled }

  let id: UUID
  let state: State
  let text: String
}

struct AgentManagedBrowserPresentation: Identifiable {
  let binding: AgentManagedBrowserDispatchBinding
  let handoff: AgentManagedBrowserHandoff

  var id: UUID { handoff.id }
}

struct AgentManagedBrowserCookie: Codable, Equatable {
  let name: String
  let value: String
  let domain: String
  let path: String
  let expires: Date?
  let secure: Bool
  let httpOnly: Bool
  let sameSite: String?

  init?(_ cookie: HTTPCookie, host: String, now: Date = Date()) {
    name = cookie.name
    value = cookie.value
    domain = cookie.domain
    path = cookie.path
    expires = cookie.expiresDate
    secure = cookie.isSecure
    httpOnly = cookie.isHTTPOnly
    sameSite = (cookie.properties?[HTTPCookiePropertyKey(rawValue: "SameSite")] as? String).flatMap {
      ["lax", "strict", "none"].contains($0.lowercased()) ? $0 : nil
    }
    guard matches(host: host, now: now) else { return nil }
  }

  func matches(host: String, now: Date) -> Bool {
    let cookieDomain = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    let host = host.lowercased()
    let delimiter = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: ";"))
    return !name.isEmpty && name.utf8.count <= 256 && value.utf8.count <= 4_096 &&
      [name, value, path, domain].allSatisfy { $0.rangeOfCharacter(from: delimiter) == nil } &&
      path.hasPrefix("/") && path.utf8.count <= 512 && cookieDomain.contains(".") && cookieDomain.utf8.count <= 253 &&
      (host == cookieDomain || host.hasSuffix("." + cookieDomain)) &&
      (expires.map { $0 > now } ?? true)
  }

  func restore(host: String, now: Date = Date()) -> HTTPCookie? {
    guard matches(host: host, now: now) else { return nil }
    var fields: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: path]
    if secure { fields[.secure] = "TRUE" }
    if httpOnly { fields[HTTPCookiePropertyKey(rawValue: "HttpOnly")] = "TRUE" }
    if let sameSite { fields[HTTPCookiePropertyKey(rawValue: "SameSite")] = sameSite }
    if let expires { fields[.expires] = expires }
    else { fields[.discard] = "TRUE" }
    if let cookie = HTTPCookie(properties: fields), cookie.isHTTPOnly == httpOnly, cookie.isSecure == secure {
      return cookie
    }
    // Some Foundation versions do not honor HttpOnly in the properties initializer.
    guard let origin = URL(string: "https://" + host + "/") else { return nil }
    var header = "\(name)=\(value); Domain=\(domain); Path=\(path)"
    if secure { header += "; Secure" }
    if httpOnly { header += "; HttpOnly" }
    if let sameSite { header += "; SameSite=\(sameSite)" }
    if let expires {
      let format = DateFormatter()
      format.locale = Locale(identifier: "en_US_POSIX")
      format.timeZone = TimeZone(secondsFromGMT: 0)
      format.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
      header += "; Expires=" + format.string(from: expires)
    }
    return HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": header], for: origin).first {
      $0.name == name && $0.value == value && $0.path == path && $0.isHTTPOnly == httpOnly && $0.isSecure == secure
    }
  }
}

struct AgentManagedBrowserTeamDispatch: Codable, Equatable {
  enum MemberRecovery: Equatable {
    case dispatch, reuse(String), awaitOriginal, stop

    init(_ member: AgentTeamMemberSnapshot) {
      if member.status == .succeeded, let result = member.replyContent ?? member.output.nilIfEmpty {
        self = .reuse(result)
      } else if [.failed, .cancelled, .skipped, .succeeded].contains(member.status) {
        self = .stop
      } else if member.dispatchCheckpoint == .notStarted &&
                  [.pending, .queued, .interrupted].contains(member.status) {
        self = .dispatch
      } else if member.dispatchCheckpoint == .dispatching || member.dispatchCheckpoint == .accepted {
        self = .awaitOriginal
      } else {
        self = .stop
      }
    }
  }

  struct Attachment: Codable, Equatable {
    let id: String
    let staged: AgentStagedAttachment
  }

  let profileID: String
  let runID: String
  let teamID: String
  let generation: Int64
  let conversationID: String
  let turnID: String
  let outgoingID: UUID
  let contactID: String
  let plan: AgentPlan
  let executionMode: AgentTaskExecutionMode
  let goal: String
  let attachments: [Attachment]

  var key: String {
    AgentMcpJSONCodec.sha256(["profile": .string(profileID), "run": .string(runID)])
  }

  func matches(_ team: AgentTeamExecutionSnapshot, outgoing: ChatMessage, profileID: String) -> Bool {
    self.profileID == profileID && runID == team.supervisorRunId && teamID == team.teamId &&
      generation == team.createdAtMillis && conversationID == team.conversationId && turnID == team.taskId &&
      team.goal == goal && outgoing.id == outgoingID && outgoing.isMine && outgoing.contactId == contactID &&
      outgoing.conversationId == conversationID && outgoing.turnId.ifBlank(outgoing.id.uuidString) == turnID
  }

  func restoreAttachments() throws -> [GalaxySSIDraftAttachment] {
    try attachments.map { reference in
      let components = reference.staged.relativePath.split(separator: "/")
      guard components.count == 3, components[0] == "inputs" else {
        throw AgentManagedBrowserContinuationStore.Failure.scopeChanged
      }
      let mime = reference.staged.mimeType.lowercased()
      let type: AgentRichBlockType = mime.hasPrefix("image/") ? .image : mime.hasPrefix("audio/") ? .audio : .file
      let block = AgentRichBlock(id: reference.id, type: type, title: reference.staged.name,
        mimeType: reference.staged.mimeType, metadata: ["source": "user_attachment"])
      let restored = AgentAttachmentWorkspaceStager.restore(conversationId: conversationID, turnId: String(components[1]),
        blocks: [block], matchExactIDs: true)
      guard let entry = restored.first, entry.staged == reference.staged, entry.attachment.id == reference.id else {
        throw AgentManagedBrowserContinuationStore.Failure.unavailable
      }
      return entry.attachment
    }
  }
}
