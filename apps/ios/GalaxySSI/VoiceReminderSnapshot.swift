import EventKit
import Foundation

struct VoiceReminderSnapshot: Codable, Equatable, Sendable {
  struct TaskRow: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let conversationID: String
    let title: String
    let phase: String
    let atMillis: Int64
  }

  struct CalendarRow: Codable, Equatable, Identifiable, Sendable {
    let resourceID: String
    let title: String
    let start: Date
    var id: String { "\(resourceID):\(start.timeIntervalSince1970)" }
  }

  struct PersonalRow: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let conversationID: String
    let content: String
    let atMillis: Int64
  }

  let tasks: [TaskRow]
  let personal: [PersonalRow]
  // A missing source is distinct from an available source with no entries.
  let calendar: [CalendarRow]?
  let unreadNewsCount: Int?

  var toolOutput: AgentMcpJSONObject {
    func row(_ id: String, _ kind: String, _ title: String, _ content: String, _ at: Int64,
             resourceID: String = "", conversationID: String = "", state: String) -> AgentMcpJSONValue {
      .object([
        "id": .string(id), "kind": .string(kind), "title": .string(title), "content": .string(content),
        "at_epoch_ms": .int(at), "resource_id": .string(resourceID), "conversation_id": .string(conversationID),
        "state": .string(state)
      ])
    }
    var items = tasks.map {
      row("task:\($0.id)", "task", "Task", $0.title, $0.atMillis, resourceID: $0.id,
          conversationID: $0.conversationID, state: $0.phase.lowercased())
    }
    items += (calendar ?? []).map {
      row("calendar:\($0.id)", "calendar", "Calendar", $0.title, Int64($0.start.timeIntervalSince1970 * 1_000),
          resourceID: $0.resourceID, state: "upcoming")
    }
    items += personal.map {
      row($0.id, "personal", "Personal reminder", $0.content, $0.atMillis,
          conversationID: $0.conversationID, state: "unread")
    }
    if let unreadNewsCount, unreadNewsCount > 0 {
      items.append(row("news:unread", "news", "Discoveries", "Unread updates: \(unreadNewsCount)",
                       0, state: "unread"))
    }
    return [
      "reminders": .array(items),
      "sources": .object([
        "tasks": .string("available"), "personal": .string("available"),
        "calendar": .string(calendar == nil ? "unavailable" : "available"),
        "news": .string(unreadNewsCount == nil ? "unavailable" : "available"),
        "weather": .string("not_connected")
      ]),
      "scope": .string("personal_reminders_and_news_summary"),
      "news_bodies_included": .bool(false)
    ]
  }

  static func taskRows(_ records: [AgentTaskRecord], limit: Int = 2) -> [TaskRow] {
    Array(records.lazy.filter {
      [.waitingConfirmation, .paused, .blocked].contains($0.phase) &&
        !$0.taskId.isEmpty && AgentTaskCenterPolicy.isReusableGoal($0.goal)
    }.prefix(max(0, limit)).map {
      TaskRow(id: $0.taskId, conversationID: $0.sessionId, title: String($0.goal.prefix(240)),
              phase: $0.phase.rawValue, atMillis: $0.updatedAtMillis)
    })
  }

  static func personalRows(_ items: [GlobalProactiveInboxItem], limit: Int = 2) -> [PersonalRow] {
    Array(items.lazy.filter {
      $0.isNew && !$0.content.isBlank && !$0.key.hasPrefix("attention-feed:") &&
        !$0.messageIds.contains(where: { $0.hasPrefix("attention-feed:") })
    }.prefix(max(0, limit)).map {
      PersonalRow(id: $0.key, conversationID: $0.destinationConversationId.ifBlank($0.sourceConversationId),
                  content: String($0.content.prefix(480)), atMillis: $0.createdAtMillis)
    })
  }

  static func calendarRows(now: Date = Date()) -> [CalendarRow]? {
    let authorization = EKEventStore.authorizationStatus(for: .event)
    if #available(iOS 17.0, *) {
      guard authorization == .fullAccess else { return nil }
    } else {
      guard authorization == .authorized else { return nil }
    }
    let store = EKEventStore()
    guard let end = Calendar.current.date(byAdding: .day, value: 1, to: now) else { return nil }
    let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
    return store.events(matching: predicate).compactMap { event -> CalendarRow? in
      guard let identifier = event.eventIdentifier, let start = event.startDate,
            start >= now, start < end, event.status != .canceled,
            event.attendees?.contains(where: { $0.isCurrentUser && $0.participantStatus == .declined }) != true
      else { return nil }
      return CalendarRow(resourceID: identifier, title: String((event.title ?? "").prefix(240)), start: start)
    }.sorted { ($0.start, $0.id) < ($1.start, $1.id) }.prefix(2).map { $0 }
  }
}

enum VoiceReminderNativeTool {
  static let id = "galaxyssi.app.reminders"
  static let consentID = "voice_reminders.read"

  static func executable(load: @escaping (AgentNativeToolInvocationContext) -> VoiceReminderSnapshot?)
    throws -> AgentNativeToolExecutableDefinition {
    let descriptor = try AgentNativeToolDescriptor(
      id: id, version: AgentPhoneNativeToolCatalog.version, title: "Read voice reminders",
      description: "Reads personal reminders, actionable tasks, authorized upcoming calendar events, and one unread news count. Does not include articles.",
      location: .application,
      inputSchema: ["type": .string("object"), "properties": .object([:]), "additionalProperties": .bool(false)],
      outputSchema: AgentNativeToolDescriptor.objectSchema(),
      risk: .high, capabilities: ["app.reminders.read"],
      requiredConsents: [
        AgentNativeConsentRequirement(id: consentID, title: "Share voice reminders",
          description: "Allows the current Agent to read personal reminders, tasks, and authorized calendar events.")
      ],
      timeoutMillis: 5_000, idempotency: .idempotent, effect: .readOnly
    )
    return AgentNativeToolExecutableDefinition(
      definition: AgentPhoneNativeToolDefinition(descriptor: descriptor, executorId: "ios.voice_reminders"),
      executor: { invocation in
        try invocation.checkpoint()
        guard let snapshot = load(invocation.context) else {
          return .failure(code: "reminders_unavailable", message: "Voice reminders are unavailable in this context.")
        }
        try invocation.checkpoint()
        return .success(output: snapshot.toolOutput, message: "Voice reminders read")
      }
    )
  }
}

extension GalaxySSIStore {
  func voiceReminderSnapshot(calendar: [VoiceReminderSnapshot.CalendarRow]?) -> VoiceReminderSnapshot? {
    guard canReadVoiceReminderSnapshot else { return nil }
    var allowed: [String: Bool] = [:]
    func isActiveAndShareable(_ id: String) -> Bool {
      guard !id.isEmpty else { return false }
      if let cached = allowed[id] { return cached }
      let session = agentSession(id: id)
      let permitted = session?.status == .active && session?.privateMode == false && session?.trackingPaused == false
      allowed[id] = permitted
      return permitted
    }
    let cancelled = Set(agentWorkspaceStore.list().filter(\.cancellationRequested).map(\.taskId))
    let tasks = mergedAgentTaskRecords().filter {
      !cancelled.contains($0.taskId) && isActiveAndShareable($0.sessionId)
    }
    let messages = globalProactiveMessages.filter { message in
      !message.id.hasPrefix("attention-feed:") && !message.sourceEventId.hasPrefix("attention-feed:") &&
        (message.sourceConversationId.isEmpty || isActiveAndShareable(message.sourceConversationId)) &&
        isActiveAndShareable(message.deliveredConversationId.ifBlank(message.sourceConversationId))
    }
    let inbox = GlobalProactiveInboxPolicy.project(messages: messages, feedback: globalAgentFeedback, limit: 100)
    let archive = PublicNewsArchive()
    archive.load()
    return VoiceReminderSnapshot(tasks: VoiceReminderSnapshot.taskRows(tasks),
                                 personal: VoiceReminderSnapshot.personalRows(inbox),
                                 calendar: calendar, unreadNewsCount: archive.reminderUnreadCount)
  }
}
