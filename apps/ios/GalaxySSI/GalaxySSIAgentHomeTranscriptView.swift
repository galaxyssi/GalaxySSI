import SwiftUI

struct GalaxySSIAgentHomeTranscriptView<Content: View>: View {
  @Binding var visibleMessageLimit: Int
  @Binding var olderTranscriptAnchor: UUID?
  @Binding var transcriptTopLoadTriggered: Bool
  @Binding var transcriptAutoFollow: Bool
  @Binding var transcriptShowLatestButton: Bool
  @Binding var transcriptContentMinY: CGFloat
  @Binding var pendingAgentSwipeDirection: String

  let agentSwipeRequest: Int
  let activeAgentConversationID: String
  let messages: [ChatMessage]
  let transcriptMessages: [ChatMessage]
  let hasOlderTranscriptMessages: Bool
  let latestWaitingIndicatorID: String?
  let waitingIndicatorCount: Int
  let voiceTranscriptionPending: Bool
  let voicePendingAttachments: [GalaxySSIDraftAttachment]
  let waitingForAgentReply: Bool
  let activeAgentPhase: AgentPhase?
  let activeAgentTasks: [AgentTaskRecord]
  let pageSize: Int
  let reduceMotion: Bool
  let voiceTranscriptionPendingViewID: String
  let replyWaitingViewID: String
  let latestButtonTitle: String
  let onLoadOlderTranscriptMessages: () -> Void
  let onMessagesChanged: () -> Void
  let onExecutionStateChanged: () -> Void
  private let content: () -> Content

  init(
    visibleMessageLimit: Binding<Int>,
    olderTranscriptAnchor: Binding<UUID?>,
    transcriptTopLoadTriggered: Binding<Bool>,
    transcriptAutoFollow: Binding<Bool>,
    transcriptShowLatestButton: Binding<Bool>,
    transcriptContentMinY: Binding<CGFloat>,
    agentSwipeRequest: Int,
    pendingAgentSwipeDirection: Binding<String>,
    activeAgentConversationID: String,
    messages: [ChatMessage],
    transcriptMessages: [ChatMessage],
    hasOlderTranscriptMessages: Bool,
    latestWaitingIndicatorID: String?,
    waitingIndicatorCount: Int,
    voiceTranscriptionPending: Bool,
    voicePendingAttachments: [GalaxySSIDraftAttachment],
    waitingForAgentReply: Bool,
    activeAgentPhase: AgentPhase?,
    activeAgentTasks: [AgentTaskRecord],
    pageSize: Int,
    reduceMotion: Bool,
    voiceTranscriptionPendingViewID: String,
    replyWaitingViewID: String,
    latestButtonTitle: String,
    onLoadOlderTranscriptMessages: @escaping () -> Void,
    onMessagesChanged: @escaping () -> Void,
    onExecutionStateChanged: @escaping () -> Void,
    @ViewBuilder content: @escaping () -> Content
  ) {
    _visibleMessageLimit = visibleMessageLimit
    _olderTranscriptAnchor = olderTranscriptAnchor
    _transcriptTopLoadTriggered = transcriptTopLoadTriggered
    _transcriptAutoFollow = transcriptAutoFollow
    _transcriptShowLatestButton = transcriptShowLatestButton
    _transcriptContentMinY = transcriptContentMinY
    _pendingAgentSwipeDirection = pendingAgentSwipeDirection
    self.agentSwipeRequest = agentSwipeRequest
    self.activeAgentConversationID = activeAgentConversationID
    self.messages = messages
    self.transcriptMessages = transcriptMessages
    self.hasOlderTranscriptMessages = hasOlderTranscriptMessages
    self.latestWaitingIndicatorID = latestWaitingIndicatorID
    self.waitingIndicatorCount = waitingIndicatorCount
    self.voiceTranscriptionPending = voiceTranscriptionPending
    self.voicePendingAttachments = voicePendingAttachments
    self.waitingForAgentReply = waitingForAgentReply
    self.activeAgentPhase = activeAgentPhase
    self.activeAgentTasks = activeAgentTasks
    self.pageSize = pageSize
    self.reduceMotion = reduceMotion
    self.voiceTranscriptionPendingViewID = voiceTranscriptionPendingViewID
    self.replyWaitingViewID = replyWaitingViewID
    self.latestButtonTitle = latestButtonTitle
    self.onLoadOlderTranscriptMessages = onLoadOlderTranscriptMessages
    self.onMessagesChanged = onMessagesChanged
    self.onExecutionStateChanged = onExecutionStateChanged
    self.content = content
  }

  var body: some View {
    GalaxySSIAgentTranscriptScrollView(
      visibleMessageLimit: $visibleMessageLimit,
      olderTranscriptAnchor: $olderTranscriptAnchor,
      transcriptTopLoadTriggered: $transcriptTopLoadTriggered,
      transcriptAutoFollow: $transcriptAutoFollow,
      transcriptShowLatestButton: $transcriptShowLatestButton,
      transcriptContentMinY: $transcriptContentMinY,
      agentSwipeRequest: agentSwipeRequest,
      pendingAgentSwipeDirection: $pendingAgentSwipeDirection,
      activeAgentConversationID: activeAgentConversationID,
      messages: messages,
      transcriptMessages: transcriptMessages,
      hasOlderTranscriptMessages: hasOlderTranscriptMessages,
      latestWaitingIndicatorID: latestWaitingIndicatorID,
      waitingIndicatorCount: waitingIndicatorCount,
      voiceTranscriptionPending: voiceTranscriptionPending,
      voicePendingAttachments: voicePendingAttachments,
      waitingForAgentReply: waitingForAgentReply,
      activeAgentPhase: activeAgentPhase,
      activeAgentTasks: activeAgentTasks,
      pageSize: pageSize,
      reduceMotion: reduceMotion,
      voiceTranscriptionPendingViewID: voiceTranscriptionPendingViewID,
      replyWaitingViewID: replyWaitingViewID,
      latestButtonTitle: latestButtonTitle,
      onLoadOlderTranscriptMessages: onLoadOlderTranscriptMessages,
      onMessagesChanged: onMessagesChanged,
      onExecutionStateChanged: onExecutionStateChanged
    ) {
      content()
    }
  }
}
