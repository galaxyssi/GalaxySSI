import SwiftUI
import UIKit

struct SignalASIMessageActionsView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var store: SignalASIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var statusMessage = ""
  @State private var statusIsError = false
  @State private var cancellingRemoteTaskIDs = Set<String>()

  var message: ChatMessage
  var contact: SignalASIContact

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("message_actions_title", "Message Actions"),
        leading: {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 16, weight: .semibold))
              .foregroundColor(.signalASITextPrimary)
          }
        },
        trailing: { Color.clear }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          hero
          if !statusMessage.isEmpty {
            SignalASISecurityStatusRow(
              title: statusMessage,
              subtitle: t("signalasi.message.actions_status_detail", "Action status for this message"),
              systemImage: statusIsError ? "exclamationmark.circle" : "checkmark.circle",
              tint: statusIsError ? .orange : .signalASIAccent,
              badge: statusIsError
                ? t("signalasi.status.error", "Error")
                : t("voice_health_ready", "Ready")
            )
          }
          actionsSection
          detailsSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
  }

  private var hero: some View {
    HStack(alignment: .center, spacing: 12) {
      if message.isMine {
        ZStack {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.signalASIAccent.opacity(0.16))
          Image(systemName: "person.crop.circle.fill")
            .font(.system(size: 26, weight: .semibold))
            .foregroundColor(.signalASIAccent)
        }
        .frame(width: 54, height: 54)
      } else {
        AvatarView(contact: contact, size: 54)
      }
      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 8) {
          Text(messageSenderTitle)
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(.signalASITextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
          Text(messageTime)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(heroTint)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 7)
            .frame(minHeight: 22)
            .background(heroTint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        Text(String(message.content.prefix(80)))
          .font(.system(size: 14))
          .foregroundColor(.signalASITextSecondary)
          .lineLimit(3)
          .fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
  }

  private var actionsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("section_actions", "Actions"))
      SignalASISecurityActionRow(
        title: t("message_copy_title", "Copy Message"),
        subtitle: t("message_copy_subtitle", "Copy message text"),
        systemImage: "doc.on.doc",
        tint: .blue,
        badge: t("signalasi.common.copy", "Copy")
      ) {
        UIPasteboard.general.string = message.content
        statusMessage = t("toast_copied", "Copied")
        statusIsError = false
      }
      if let remoteTask = remoteAgentTask, remoteTask.isCancellable {
        let cancelling = cancellingRemoteTaskIDs.contains(remoteTask.id)
        SignalASISecurityActionRow(
          title: cancelling
            ? t("signalasi.agent.remote_status.cancelling", "Cancelling...")
            : t("signalasi.agent.remote_status.cancel", "Cancel task"),
          subtitle: t("signalasi.message.cancel_task_subtitle", "Ask the connected Agent to stop this task"),
          systemImage: "xmark.circle",
          tint: .orange,
          badge: cancelling
            ? t("signalasi.agent.remote_status.cancelling", "Cancelling...")
            : t("signalasi.agent.remote_status.cancel", "Cancel task")
        ) {
          cancelRemoteAgentTask(remoteTask)
        }
        .disabled(cancelling)
      }
      SignalASISecurityActionRow(
        title: t("message_delete_title", "Delete Message"),
        subtitle: t("message_delete_subtitle", "Delete only from this device"),
        systemImage: "trash",
        tint: .red,
        badge: t("signalasi.common.delete", "Delete")
      ) {
        _ = store.deleteMessage(message.id, contactId: contact.id)
        statusMessage = t("toast_deleted", "Deleted")
        statusIsError = false
        dismiss()
      }
    }
  }

  private var detailsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("section_details", "Details"))
      SignalASISecurityStatusRow(
        title: t("message_sent_time", "Sent Time"),
        subtitle: messageFullTime,
        systemImage: "clock",
        tint: .blue,
        badge: messageTime
      )
      if let remoteTask = remoteAgentTask {
        SignalASISecurityStatusRow(
          title: t("signalasi.agent_task_details_title", "Agent task"),
          subtitle: remoteTask.taskId + remoteTaskStepSuffix(remoteTask),
          systemImage: "cpu",
          tint: SignalASIRemoteTaskStatusPresentation.tint(remoteTask.status),
          badge: SignalASIRemoteTaskStatusPresentation.title(
            remoteTask.status,
            language: interfaceLanguage
          ),
          monospacedSubtitle: true
        )
      }
      SignalASISecurityStatusRow(
        title: t("message_security_status", "Security Status"),
        subtitle: securityStatusText,
        systemImage: "shield",
        tint: .signalASIAccent,
        badge: securityBadge
      )
      SignalASISecurityStatusRow(
        title: t("message_delivery_trace", "Delivery Trace"),
        subtitle: deliveryTraceText,
        systemImage: "point.3.connected.trianglepath.dotted",
        tint: message.deliveryTrace.isEmpty ? .orange : .purple,
        badge: String(message.deliveryTrace.count),
        monospacedSubtitle: true
      )
      identifierRows
    }
  }

  @ViewBuilder
  private var identifierRows: some View {
    SignalASISecurityStatusRow(
      title: t("signalasi.identifier.message", "Message"),
      subtitle: message.id.uuidString,
      systemImage: "number",
      tint: .teal,
      badge: t("section_details", "Details"),
      monospacedSubtitle: true
    )
    if !message.conversationId.isBlank {
      SignalASISecurityStatusRow(
        title: t("signalasi.identifier.conversation", "Conversation"),
        subtitle: message.conversationId,
        systemImage: "bubble.left.and.bubble.right",
        tint: .teal,
        badge: t("section_details", "Details"),
        monospacedSubtitle: true
      )
    }
    if !message.turnId.isBlank {
      SignalASISecurityStatusRow(
        title: t("signalasi.identifier.turn", "Turn"),
        subtitle: message.turnId,
        systemImage: "arrow.triangle.branch",
        tint: .teal,
        badge: t("section_details", "Details"),
        monospacedSubtitle: true
      )
    }
    if !message.remoteMessageId.isBlank {
      SignalASISecurityStatusRow(
        title: t("signalasi.identifier.remote_message", "Remote Message"),
        subtitle: message.remoteMessageId,
        systemImage: "network",
        tint: .teal,
        badge: t("section_details", "Details"),
        monospacedSubtitle: true
      )
    }
  }

  private var messageSenderTitle: String {
    if message.isMine {
      return t("message_sent_by_me", "Sent by Me")
    }
    switch contact.id {
    case "system":
      return t("chat_system_notice", "System Notifications")
    case "me":
      return store.profile.name.ifBlank(SignalASIDeviceIdentityName.current(profile: store.profile))
    default:
      return contact.displayName
    }
  }

  private func remoteTaskStepSuffix(_ task: AgentRemoteTaskStatusSnapshot) -> String {
    let step = task.currentStep.ifBlank(task.detail)
    return step.isEmpty ? "" : "\n\(step)"
  }

  private var remoteAgentTask: AgentRemoteTaskStatusSnapshot? {
    let conversationID = message.conversationId.ifBlank(store.activeAgentConversationId)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !conversationID.isEmpty else { return nil }
    let turnID = message.turnId.trimmingCharacters(in: .whitespacesAndNewlines)
    let remoteMessageID = message.remoteMessageId.trimmingCharacters(in: .whitespacesAndNewlines)
    return coordinator.remoteAgentTaskStatuses.values
      .filter { snapshot in
        guard snapshot.conversationId == conversationID else {
          return false
        }
        let turnMatches = !turnID.isEmpty &&
          (snapshot.taskId == turnID || snapshot.turnId == turnID)
        let sourceID = snapshot.sourceMessageId > 0 ? String(snapshot.sourceMessageId) : ""
        let sourceMatches = !remoteMessageID.isEmpty && !sourceID.isEmpty &&
          (remoteMessageID == sourceID || remoteMessageID == "agent-stream-\(sourceID)")
        return turnMatches || sourceMatches
      }
      .max { lhs, rhs in
        if lhs.updatedAtMillis != rhs.updatedAtMillis {
          return lhs.updatedAtMillis < rhs.updatedAtMillis
        }
        return lhs.id < rhs.id
      }
  }

  private func cancelRemoteAgentTask(_ task: AgentRemoteTaskStatusSnapshot) {
    guard cancellingRemoteTaskIDs.insert(task.id).inserted else { return }
    statusMessage = t("signalasi.agent.remote_status.cancelling", "Sending cancellation...")
    statusIsError = false
    Task { @MainActor in
      let sent = await coordinator.cancelRemoteAgentTask(task)
      cancellingRemoteTaskIDs.remove(task.id)
      guard sent else {
        statusMessage = t("signalasi.agent.remote_status.cancel_failed", "The cancellation could not be sent.")
        statusIsError = true
        return
      }
      _ = store.appendDeliveryTrace(
        message.id,
        contactId: contact.id,
        stage: "agent_cancelling",
        detail: task.taskId
      )
      statusMessage = t("signalasi.agent.remote_status.cancel_sent", "Cancellation sent.")
    }
  }

  private var heroTint: Color {
    message.isMine ? .signalASIAccent : .blue
  }

  private var messageTime: String {
    timeFormatter.string(from: message.createdAt)
  }

  private var messageFullTime: String {
    fullDateFormatter.string(from: message.createdAt)
  }

  private var deliveryTraceText: String {
    guard !message.deliveryTrace.isEmpty else {
      return t("delivery_trace_empty", "No trace yet")
    }
    let origin = message.deliveryTrace.first?.createdAt ?? message.createdAt
    return message.deliveryTrace.suffix(32).map { event in
      let elapsed = max(0, Int(event.createdAt.timeIntervalSince(origin) * 1_000))
      let detail = event.detail.isBlank ? "" : " / \(event.detail)"
      return "\(traceTimeFormatter.string(from: event.createdAt)) +\(elapsed) ms \(traceLabel(event.stage))\(detail)"
    }.joined(separator: "\n")
  }

  private var securityStatusText: String {
    switch contact.deliveryMode {
    case .link, .pcConnector:
      return t("message_security_status_subtitle", "Protected by the SignalASI Link end-to-end session")
    case .cloudAPI:
      return t(
        "signalasi.security.cloud",
        "Protected locally; cloud model requests use the configured provider endpoint"
      )
    case .local:
      return t("signalasi.security.local", "Stored locally on this device")
    }
  }

  private var securityBadge: String {
    switch contact.deliveryMode {
    case .link, .pcConnector:
      return "E2E"
    case .cloudAPI:
      return t("signalasi.status.cloud_model", "Cloud model")
    case .local:
      return t("signalasi.status.local", "Local")
    }
  }

  private var displayLocale: Locale {
    SignalASILocalization.dateLocale(language: interfaceLanguage)
  }

  private func traceLabel(_ stage: String) -> String {
    switch stage {
    case "created": return t("delivery_trace_created", "Created")
    case "persisted": return t("delivery_trace_persisted", "Persisted")
    case "queued": return t("delivery_trace_queued", "Queued")
    case "sent": return t("delivery_trace_sent", "Sent")
    case "delivered": return t("delivery_trace_delivered", "Delivered")
    case "read": return t("delivery_trace_read", "Read")
    case "failed": return t("delivery_trace_failed", "Failed")
    case "mqtt_published": return t("delivery_trace_mqtt_published", "Published to MQTT")
    case "publish_failed": return t("delivery_trace_publish_failed", "Publish failed")
    case "delivered_local_estimate": return t("delivery_trace_delivered_estimate", "Delivery estimated")
    case "desktop_received": return t("delivery_trace_desktop_received", "Desktop received")
    case "desktop_plain": return t("delivery_trace_desktop_plain", "Desktop plaintext debug")
    case "desktop_decrypted": return t("delivery_trace_desktop_decrypted", "Desktop decrypted")
    case "agent_started": return t("delivery_trace_agent_started", "Agent started")
    case "agent_first_output": return t("delivery_trace_agent_first_output", "First Agent output")
    case "agent_replied": return t("delivery_trace_agent_replied", "Agent replied")
    case "agent_accepted": return t("agent_task_status_accepted", "Accepted")
    case "agent_queued": return t("agent_task_status_queued", "Queued")
    case "agent_starting": return t("agent_task_status_starting", "Starting")
    case "agent_recovering": return t("agent_task_status_recovering", "Recovering")
    case "agent_running": return t("agent_task_status_running", "Running")
    case "agent_waiting_input": return t("agent_task_status_waiting_input", "Waiting for input")
    case "agent_waiting_approval": return t("agent_task_status_waiting_approval", "Waiting for approval")
    case "agent_completed": return t("agent_task_status_completed", "Completed")
    case "agent_failed": return t("agent_task_status_failed", "Failed")
    case "agent_cancelled": return t("agent_task_status_cancelled", "Cancelled")
    case "agent_timed_out": return t("agent_task_status_timed_out", "Timed out")
    case "agent_cancelling": return t("agent_task_status_cancelling", "Cancelling")
    case "desktop_reply_publish_queued": return t("delivery_trace_desktop_reply_queued", "Desktop reply queued")
    case "desktop_reply_broker_ack": return t("delivery_trace_desktop_reply_ack", "Desktop reply Broker ACK")
    case "desktop_broker_ack": return t("delivery_trace_desktop_broker_ack", "Broker confirmed")
    case "phone_contact_delivered": return t("delivery_trace_phone_contact_delivered", "Phone contact confirmed delivery")
    case "desktop_mobile_test_queued": return t("delivery_trace_desktop_mobile_test_queued", "Desktop test queued")
    case "desktop_agent_push_queued": return t("delivery_trace_agent_push_queued", "Agent Push queued")
    case "desktop_connector_status": return t("delivery_trace_connector_status", "Connector status synced")
    case "desktop_pairing_confirmed": return t("delivery_trace_pairing_confirmed", "Pairing confirmed")
    case "desktop_pairing_revocation_queued": return t("delivery_trace_pairing_revocation_queued", "Pairing revocation queued")
    case "received": return t("delivery_trace_received", "Received")
    case "decrypted": return t("delivery_trace_decrypted", "Decrypted")
    case "cloud_request": return t("delivery_trace_cloud_request", "Model request")
    case "cloud_reply": return t("delivery_trace_cloud_reply", "Model replied")
    case "cloud_reply_received": return t("delivery_trace_cloud_reply_received", "Model reply received")
    case "cloud_error": return t("delivery_trace_cloud_error", "Model error")
    case "local_saved": return t("delivery_status_local_saved", "Saved locally")
    default: return stage
    }
  }

  private var timeFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = displayLocale
    formatter.dateFormat = "HH:mm"
    return formatter
  }

  private var traceTimeFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = displayLocale
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter
  }

  private var fullDateFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = displayLocale
    formatter.dateStyle = .medium
    formatter.timeStyle = .medium
    return formatter
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
