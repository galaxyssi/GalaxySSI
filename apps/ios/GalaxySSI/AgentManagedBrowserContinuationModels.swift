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
