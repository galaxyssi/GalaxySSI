import Foundation

enum VoiceInteractionPhase: String, Codable, CaseIterable, Identifiable {
  case idle = "IDLE"
  case preparing = "PREPARING"
  case listening = "LISTENING"
  case endpointing = "ENDPOINTING"
  case finalizingASR = "FINALIZING_ASR"
  case routing = "ROUTING"
  case executingLocalAction = "EXECUTING_LOCAL_ACTION"
  case waitingModelFirstToken = "WAITING_MODEL_FIRST_TOKEN"
  case streamingModelText = "STREAMING_MODEL_TEXT"
  case playingTTS = "PLAYING_TTS"
  case startingAgent = "STARTING_AGENT"
  case agentRunning = "AGENT_RUNNING"
  case completed = "COMPLETED"
  case cancelled = "CANCELLED"
  case failed = "FAILED"

  var id: String { rawValue }

  var isTerminal: Bool {
    self == .completed || self == .cancelled || self == .failed
  }
}

struct TranscriptHypothesis: Codable, Equatable {
  var text: String
  var revision: Int
  var provider: String
  var modelProfileId: String
  var confidence: Float?

  init(
    text: String,
    revision: Int,
    provider: String = "",
    modelProfileId: String = "",
    confidence: Float? = nil
  ) {
    self.text = text
    self.revision = revision
    self.provider = provider
    self.modelProfileId = modelProfileId
    self.confidence = confidence
  }

  enum CodingKeys: String, CodingKey {
    case text
    case revision
    case provider
    case modelProfileId = "model_profile_id"
    case confidence
  }
}

enum VoiceRouteKind: String, Codable, CaseIterable, Identifiable {
  case localAction = "LOCAL_ACTION"
  case cloudModel = "CLOUD_MODEL"
  case remoteAgent = "REMOTE_AGENT"

  var id: String { rawValue }
}

struct VoiceRouteDecision: Codable, Equatable {
  var kind: VoiceRouteKind
  var targetId: String
  var reasonCode: String

  init(
    kind: VoiceRouteKind,
    targetId: String = "",
    reasonCode: String = ""
  ) {
    self.kind = kind
    self.targetId = targetId
    self.reasonCode = reasonCode
  }

  enum CodingKeys: String, CodingKey {
    case kind
    case targetId = "target_id"
    case reasonCode = "reason_code"
  }
}

struct VoiceFailure: Codable, Equatable {
  var code: String
  var recoverable: Bool
  var stage: VoiceInteractionPhase
  var detail: String

  init(
    code: String,
    recoverable: Bool,
    stage: VoiceInteractionPhase,
    detail: String = ""
  ) {
    self.code = code
    self.recoverable = recoverable
    self.stage = stage
    self.detail = detail
  }
}

struct VoiceInteractionState: Codable, Equatable {
  var sessionId: String
  var phase: VoiceInteractionPhase
  var partialText: String
  var stableText: String
  var finalText: String?
  var finalTranscriptRevision: Int?
  var correctedText: String?
  var asrProvider: String?
  var modelProfileId: String?
  var route: VoiceRouteDecision?
  var agentRunId: String?
  var canInterrupt: Bool
  var failure: VoiceFailure?
  var revision: Int64
  var createdAtElapsedNs: Int64
  var updatedAtElapsedNs: Int64

  init(
    sessionId: String = "",
    phase: VoiceInteractionPhase = .idle,
    partialText: String = "",
    stableText: String = "",
    finalText: String? = nil,
    finalTranscriptRevision: Int? = nil,
    correctedText: String? = nil,
    asrProvider: String? = nil,
    modelProfileId: String? = nil,
    route: VoiceRouteDecision? = nil,
    agentRunId: String? = nil,
    canInterrupt: Bool = true,
    failure: VoiceFailure? = nil,
    revision: Int64 = 0,
    createdAtElapsedNs: Int64 = 0,
    updatedAtElapsedNs: Int64 = 0
  ) {
    self.sessionId = sessionId
    self.phase = phase
    self.partialText = partialText
    self.stableText = stableText
    self.finalText = finalText
    self.finalTranscriptRevision = finalTranscriptRevision
    self.correctedText = correctedText
    self.asrProvider = asrProvider
    self.modelProfileId = modelProfileId
    self.route = route
    self.agentRunId = agentRunId
    self.canInterrupt = canInterrupt
    self.failure = failure
    self.revision = max(0, revision)
    self.createdAtElapsedNs = max(0, createdAtElapsedNs)
    self.updatedAtElapsedNs = max(0, updatedAtElapsedNs)
  }

  enum CodingKeys: String, CodingKey {
    case sessionId = "session_id"
    case phase
    case partialText = "partial_text"
    case stableText = "stable_text"
    case finalText = "final_text"
    case finalTranscriptRevision = "final_transcript_revision"
    case correctedText = "corrected_text"
    case asrProvider = "asr_provider"
    case modelProfileId = "model_profile_id"
    case route
    case agentRunId = "agent_run_id"
    case canInterrupt = "can_interrupt"
    case failure
    case revision
    case createdAtElapsedNs = "created_at_elapsed_ns"
    case updatedAtElapsedNs = "updated_at_elapsed_ns"
  }
}

struct VoiceSessionConfig: Codable, Equatable {
  var requestedSessionId: String
  var source: String
  var language: String
  var targetId: String
  var routingMode: String
  var speakReplies: Bool
  var continueInBackground: Bool

  init(
    requestedSessionId: String = "",
    source: String,
    language: String = "auto",
    targetId: String = "",
    routingMode: String = "",
    speakReplies: Bool = false,
    continueInBackground: Bool = false
  ) {
    self.requestedSessionId = requestedSessionId
    self.source = source
    self.language = language
    self.targetId = targetId
    self.routingMode = routingMode
    self.speakReplies = speakReplies
    self.continueInBackground = continueInBackground
  }

  enum CodingKeys: String, CodingKey {
    case requestedSessionId = "requested_session_id"
    case source
    case language
    case targetId = "target_id"
    case routingMode = "routing_mode"
    case speakReplies = "speak_replies"
    case continueInBackground = "continue_in_background"
  }
}

struct VoiceSessionResult: Codable, Equatable {
  var sessionId: String
  var completed: Bool
  var cancelled: Bool
  var route: VoiceRouteDecision?
  var failure: VoiceFailure?
  var finalTranscriptRevision: Int?

  init(
    sessionId: String,
    completed: Bool,
    cancelled: Bool,
    route: VoiceRouteDecision? = nil,
    failure: VoiceFailure? = nil,
    finalTranscriptRevision: Int? = nil
  ) {
    self.sessionId = sessionId
    self.completed = completed
    self.cancelled = cancelled
    self.route = route
    self.failure = failure
    self.finalTranscriptRevision = finalTranscriptRevision
  }

  enum CodingKeys: String, CodingKey {
    case sessionId = "session_id"
    case completed
    case cancelled
    case route
    case failure
    case finalTranscriptRevision = "final_transcript_revision"
  }
}
