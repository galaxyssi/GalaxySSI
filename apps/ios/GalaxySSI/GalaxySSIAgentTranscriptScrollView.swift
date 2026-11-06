import SwiftUI

private let galaxySSIAgentTranscriptCoordinateSpace = "galaxyssi-agent-transcript"

struct GalaxySSIAgentTranscriptScrollView<Content: View>: View {
  @Environment(\.agentReplySpeechBlankTap) private var blankTap
  @State private var measuredContentBottom: CGFloat?
  @Binding var visibleMessageLimit: Int
  @Binding var olderTranscriptAnchor: UUID?
  @Binding var transcriptTopLoadTriggered: Bool
  @Binding var transcriptAutoFollow: Bool
  @Binding var transcriptShowLatestButton: Bool
  @Binding var transcriptContentMinY: CGFloat
  @Environment(\.scenePhase) private var scene
  @State private var scrollEpoch = GalaxySSIChatViewportEpoch()
  @State private var positionedConversation: String?
  @State private var draggingTranscript = false
  @State private var pinnedToLatest = false
  private let transcriptTail = "agent-transcript-tail"

  var agentSwipeRequest: Int
  @Binding var pendingAgentSwipeDirection: String
  var activeAgentConversationID: String
  var messages: [ChatMessage]
  var transcriptMessages: [ChatMessage]
  var hasOlderTranscriptMessages: Bool
  var latestWaitingIndicatorID: String?
  var waitingIndicatorCount: Int
  var voiceTranscriptionPending: Bool
  var voicePendingAttachments: [GalaxySSIDraftAttachment]
  var waitingForAgentReply: Bool
  var activeAgentPhase: AgentPhase?
  var activeAgentTasks: [AgentTaskRecord]
  var pageSize: Int
  var reduceMotion: Bool
  var voiceTranscriptionPendingViewID: String
  var replyWaitingViewID: String
  var latestButtonTitle: String
  var onLoadOlderTranscriptMessages: () -> Void
  var onMessagesChanged: () -> Void
  var onExecutionStateChanged: () -> Void
  private let content: Content

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
    @ViewBuilder content: () -> Content
  ) {
    _visibleMessageLimit = visibleMessageLimit
    _olderTranscriptAnchor = olderTranscriptAnchor
    _transcriptTopLoadTriggered = transcriptTopLoadTriggered
    _transcriptAutoFollow = transcriptAutoFollow
    _transcriptShowLatestButton = transcriptShowLatestButton
    _transcriptContentMinY = transcriptContentMinY
    self.agentSwipeRequest = agentSwipeRequest
    _pendingAgentSwipeDirection = pendingAgentSwipeDirection
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
    self.content = content()
  }

  var body: some View {
    ScrollViewReader { proxy in
      GeometryReader { viewport in
        ZStack(alignment: .bottomTrailing) {
          ScrollView {
            VStack(spacing: 0) {
              content
              Color.clear.frame(height: 1).id(transcriptTail).accessibilityHidden(true)
            }
              .padding(.horizontal, 12)
              .padding(.top, 8)
              .padding(.bottom, 16)
              .background(alignment: .leading) { blankSpeechTarget.frame(width: 12) }
              .background(alignment: .trailing) { blankSpeechTarget.frame(width: 12) }
              .background(alignment: .top) { blankSpeechTarget.frame(height: 8) }
              .background(alignment: .bottom) { blankSpeechTarget.frame(height: 16) }
              .background(
                GeometryReader { contentGeometry in
                  Color.clear.preference(
                    key: AgentTranscriptScrollMetricsKey.self,
                    value: AgentTranscriptScrollMetrics(
                      contentMinY: contentGeometry
                        .frame(in: .named(galaxySSIAgentTranscriptCoordinateSpace)).minY,
                      contentMaxY: contentGeometry
                        .frame(in: .named(galaxySSIAgentTranscriptCoordinateSpace)).maxY,
                      viewportHeight: viewport.size.height
                    )
                  )
                }
              )
          }
          if let bottom = measuredContentBottom, bottom < viewport.size.height {
            blankSpeechTarget
              .frame(height: max(0, viewport.size.height - max(0, bottom)))
              .frame(maxWidth: .infinity)
          }
          if transcriptShowLatestButton, let last = messages.last {
            GalaxySSIAgentLatestButton(title: latestButtonTitle) {
              scrollEpoch.invalidate()
              olderTranscriptAnchor = nil
              pinnedToLatest = true
              transcriptAutoFollow = true
              transcriptShowLatestButton = false
              withAnimation(reduceMotion ? nil : Animation.default) {
                proxy.scrollTo(last.id, anchor: .bottom)
              }
            }
            .padding(.trailing, 16)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
          }
        }
      }
      .background(Color.galaxySSIPageBackground)
      .simultaneousGesture(
        DragGesture(minimumDistance: 12)
          .onChanged { value in
            guard !draggingTranscript, abs(value.translation.height) >= abs(value.translation.width) else { return }
            draggingTranscript = true
            scrollEpoch.invalidate()
            pinnedToLatest = false
            olderTranscriptAnchor = nil
          }
          .onEnded { value in
            draggingTranscript = false
            guard hasOlderTranscriptMessages,
                  transcriptContentMinY >= -8,
                  value.translation.height >= 12,
                  abs(value.translation.height) >= abs(value.translation.width) else {
              return
            }
            onLoadOlderTranscriptMessages()
          }
      )
      .onChange(of: visibleMessageLimit) { _ in
        guard let anchor = olderTranscriptAnchor else { return }
        let ticket = scrollEpoch.revision
        DispatchQueue.main.async {
          guard scrollEpoch.accepts(ticket), olderTranscriptAnchor == anchor, scene == .active else { return }
          withAnimation(reduceMotion ? nil : Animation.default) {
            proxy.scrollTo(anchor, anchor: .top)
          }
          olderTranscriptAnchor = nil
        }
      }
      .onChange(of: agentSwipeRequest) { _ in
        applyPendingSwipe(with: proxy)
      }
      .onChange(of: activeAgentConversationID) { _ in
        scrollEpoch.invalidate()
        pinnedToLatest = false
        positionedConversation = activeAgentConversationID
        visibleMessageLimit = pageSize
        olderTranscriptAnchor = nil
        transcriptTopLoadTriggered = false
        transcriptAutoFollow = true
        transcriptShowLatestButton = false
        let ticket = scrollEpoch.revision
        DispatchQueue.main.async {
          guard scrollEpoch.accepts(ticket), scene == .active else { return }
          guard let last = messages.last else { return }
          withAnimation(reduceMotion ? nil : Animation.default) {
            proxy.scrollTo(last.id, anchor: .bottom)
          }
        }
      }
      .onAppear {
        guard positionedConversation != activeAgentConversationID else { return }
        positionedConversation = activeAgentConversationID
        transcriptAutoFollow = true
        transcriptShowLatestButton = false
        let ticket = scrollEpoch.revision
        DispatchQueue.main.async {
          guard scrollEpoch.accepts(ticket), scene == .active else { return }
          guard let last = messages.last else { return }
          proxy.scrollTo(last.id, anchor: .bottom)
        }
      }
      .onDisappear {
        scrollEpoch.invalidate()
        draggingTranscript = false
        olderTranscriptAnchor = nil
      }
      .onChange(of: scene) { phase in
        guard phase != .active else { return }
        scrollEpoch.invalidate()
        olderTranscriptAnchor = nil
        draggingTranscript = false
      }
      .onChange(of: messages.count) { _ in
        onMessagesChanged()
        if transcriptAutoFollow {
          if let waitingID = latestWaitingIndicatorID {
            withAnimation(reduceMotion ? nil : Animation.default) {
              proxy.scrollTo(waitingID, anchor: .bottom)
            }
          } else if waitingForAgentReply {
            withAnimation(reduceMotion ? nil : Animation.default) {
              proxy.scrollTo(replyWaitingViewID, anchor: .bottom)
            }
          } else if let last = messages.last {
            withAnimation(reduceMotion ? nil : Animation.default) {
              proxy.scrollTo(last.id, anchor: .bottom)
            }
          }
        } else if !messages.isEmpty {
          transcriptShowLatestButton = true
        }
      }
      .onChange(of: activeAgentPhase) { _ in
        onExecutionStateChanged()
      }
      .onChange(of: activeAgentTasks) { _ in
        onExecutionStateChanged()
      }
      .onChange(of: waitingIndicatorCount) { _ in
        guard let last = transcriptMessages.last else { return }
        guard transcriptAutoFollow else {
          transcriptShowLatestButton = true
          return
        }
        withAnimation(reduceMotion ? nil : Animation.default) {
          proxy.scrollTo(latestWaitingIndicatorID ?? last.id.uuidString, anchor: .bottom)
        }
      }
      .onChange(of: voiceTranscriptionPending) { pending in
        guard pending else { return }
        transcriptAutoFollow = true
        transcriptShowLatestButton = false
        withAnimation(reduceMotion ? nil : Animation.default) {
          proxy.scrollTo(voiceTranscriptionPendingViewID, anchor: .bottom)
        }
      }
      .onChange(of: waitingForAgentReply) { waiting in
        guard waiting else { return }
        guard transcriptAutoFollow else {
          transcriptShowLatestButton = true
          return
        }
        withAnimation(reduceMotion ? nil : Animation.default) {
          proxy.scrollTo(replyWaitingViewID, anchor: .bottom)
        }
      }
      .coordinateSpace(name: galaxySSIAgentTranscriptCoordinateSpace)
      .onPreferenceChange(AgentTranscriptScrollMetricsKey.self) { metrics in
        measuredContentBottom = metrics.contentMaxY
        transcriptContentMinY = metrics.contentMinY
        guard scene == .active else { return }
        if pinnedToLatest {
          transcriptAutoFollow = true
          transcriptShowLatestButton = false
          if metrics.contentMaxY > metrics.viewportHeight + 18 {
            proxy.scrollTo(transcriptTail, anchor: .bottom)
          }
          return
        }
        let atTop = metrics.contentMinY >= -8
        let userIsAwayFromLatest = metrics.contentMaxY > metrics.viewportHeight + 56
        if !atTop {
          transcriptTopLoadTriggered = false
        } else if userIsAwayFromLatest,
                  hasOlderTranscriptMessages,
                  !transcriptTopLoadTriggered {
          transcriptTopLoadTriggered = true
          onLoadOlderTranscriptMessages()
        }
        let nearBottom = metrics.contentMaxY <= metrics.viewportHeight + 56
        if nearBottom {
          transcriptAutoFollow = true
          transcriptShowLatestButton = false
        } else {
          transcriptAutoFollow = false
          transcriptShowLatestButton = true
        }
      }
    }
  }

  @ViewBuilder private var blankSpeechTarget: some View {
    if let blankTap {
      Color.clear
        .contentShape(Rectangle())
        .gesture(TapGesture(count: 2).exclusively(before: TapGesture()).onEnded { result in
          if case .second = result { blankTap() }
        })
        .accessibilityHidden(true)
    }
  }

  private func applyPendingSwipe(with proxy: ScrollViewProxy) {
    let direction = pendingAgentSwipeDirection
    pendingAgentSwipeDirection = ""
    guard direction == AgentIOSAgentSwipeDirection.up.rawValue ||
      direction == AgentIOSAgentSwipeDirection.down.rawValue else {
      return
    }
    scrollEpoch.invalidate()
    olderTranscriptAnchor = nil

    if direction == AgentIOSAgentSwipeDirection.up.rawValue {
      pinnedToLatest = false
      transcriptAutoFollow = false
      if hasOlderTranscriptMessages {
        onLoadOlderTranscriptMessages()
      } else if let first = transcriptMessages.first {
        withAnimation(reduceMotion ? nil : Animation.default) {
          proxy.scrollTo(first.id, anchor: .top)
        }
      }
      transcriptShowLatestButton = !messages.isEmpty
      return
    }

    pinnedToLatest = true
    transcriptAutoFollow = true
    transcriptShowLatestButton = false
    withAnimation(reduceMotion ? nil : Animation.default) {
      proxy.scrollTo(transcriptTail, anchor: .bottom)
    }
  }
}
