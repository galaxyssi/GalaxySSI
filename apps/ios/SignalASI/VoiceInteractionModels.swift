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
  var transcriptId: String
  var stablePrefixLength: Int
  var isFinal: Bool
  var language: String?
  var segmentStartMs: Int64
  var segmentEndMs: Int64
  var averageLogProb: Float?
  var noSpeechProbability: Float?
  var createdElapsedNs: Int64

  init(
    text: String,
    revision: Int,
    provider: String = "",
    modelProfileId: String = "",
    confidence: Float? = nil,
    transcriptId: String = "",
    stablePrefixLength: Int = 0,
    isFinal: Bool = false,
    language: String? = nil,
    segmentStartMs: Int64 = 0,
    segmentEndMs: Int64 = 0,
    averageLogProb: Float? = nil,
    noSpeechProbability: Float? = nil,
    createdElapsedNs: Int64 = 0
  ) {
    self.text = text
    self.revision = revision
    self.provider = provider
    self.modelProfileId = modelProfileId
    self.confidence = confidence
    self.transcriptId = transcriptId
    self.stablePrefixLength = max(0, stablePrefixLength)
    self.isFinal = isFinal
    self.language = language
    self.segmentStartMs = max(0, segmentStartMs)
    self.segmentEndMs = max(0, segmentEndMs)
    self.averageLogProb = averageLogProb
    self.noSpeechProbability = noSpeechProbability
    self.createdElapsedNs = max(0, createdElapsedNs)
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      text: try container.decode(String.self, forKey: .text),
      revision: try container.decode(Int.self, forKey: .revision),
      provider: try container.decodeIfPresent(String.self, forKey: .provider) ?? "",
      modelProfileId: try container.decodeIfPresent(String.self, forKey: .modelProfileId) ?? "",
      confidence: try container.decodeIfPresent(Float.self, forKey: .confidence),
      transcriptId: try container.decodeIfPresent(String.self, forKey: .transcriptId) ?? "",
      stablePrefixLength: try container.decodeIfPresent(Int.self, forKey: .stablePrefixLength) ?? 0,
      isFinal: try container.decodeIfPresent(Bool.self, forKey: .isFinal) ?? false,
      language: try container.decodeIfPresent(String.self, forKey: .language),
      segmentStartMs: try container.decodeIfPresent(Int64.self, forKey: .segmentStartMs) ?? 0,
      segmentEndMs: try container.decodeIfPresent(Int64.self, forKey: .segmentEndMs) ?? 0,
      averageLogProb: try container.decodeIfPresent(Float.self, forKey: .averageLogProb),
      noSpeechProbability: try container.decodeIfPresent(Float.self, forKey: .noSpeechProbability),
      createdElapsedNs: try container.decodeIfPresent(Int64.self, forKey: .createdElapsedNs) ?? 0
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(text, forKey: .text)
    try container.encode(revision, forKey: .revision)
    try container.encode(provider, forKey: .provider)
    try container.encode(modelProfileId, forKey: .modelProfileId)
    try container.encodeIfPresent(confidence, forKey: .confidence)
    try container.encode(transcriptId, forKey: .transcriptId)
    try container.encode(stablePrefixLength, forKey: .stablePrefixLength)
    try container.encode(isFinal, forKey: .isFinal)
    try container.encodeIfPresent(language, forKey: .language)
    try container.encode(segmentStartMs, forKey: .segmentStartMs)
    try container.encode(segmentEndMs, forKey: .segmentEndMs)
    try container.encodeIfPresent(averageLogProb, forKey: .averageLogProb)
    try container.encodeIfPresent(noSpeechProbability, forKey: .noSpeechProbability)
    try container.encode(createdElapsedNs, forKey: .createdElapsedNs)
  }

  enum CodingKeys: String, CodingKey {
    case text
    case revision
    case provider
    case modelProfileId = "model_profile_id"
    case confidence
    case transcriptId = "transcript_id"
    case stablePrefixLength = "stable_prefix_length"
    case isFinal = "is_final"
    case language
    case segmentStartMs = "segment_start_ms"
    case segmentEndMs = "segment_end_ms"
    case averageLogProb = "average_log_prob"
    case noSpeechProbability = "no_speech_probability"
    case createdElapsedNs = "created_elapsed_ns"
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
