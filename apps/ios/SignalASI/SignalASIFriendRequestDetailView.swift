import SwiftUI
import UIKit

struct FriendRequestDetailView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var store: SignalASIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var statusText = ""
  @State private var statusIsError = false
  var requestId: String
  var onContactAccepted: () -> Void = {}

  private var request: SignalASIFriendRequest? {
    store.friendRequest(id: requestId)
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: request?.name ?? t("signalasi.friend_request.title", "Friend Request"),
        leading: {
          SignalASIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          if let request {
            FriendRequestHeroView(
              name: request.name,
              signalASIId: signalASIId(for: request),
              badge: statusLabel(for: request),
              pending: request.status == .pending && !isAdded(request)
            )
            identitySection(request)
            messagingSection(request)
            connectorSection(request)
            requestStateSection(request)
            actionSection(request)
          } else {
            FriendRequestEmptyView(
              title: t("signalasi.friend_request.not_found", "Friend request not found."),
              subtitle: t(
                "signalasi.friend_request.not_found_subtitle",
                "This request may already have been processed or deleted."
              )
            )
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private func identitySection(_ request: SignalASIFriendRequest) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("signalasi.contact.section_identity", "Identity"))
      copyRow(
        title: t("settings_signalasi_id", "SignalASI ID"),
        value: signalASIId(for: request),
        systemImage: "link",
        tint: .blue,
        copiedMessage: t("signalasi.friend_request.copied_id", "SignalASI ID copied")
      )
      copyRow(
        title: t("settings_identity_fingerprint", "Fingerprint"),
        value: SignalASISecurityFormatter.fingerprint(
          request.identityFingerprint,
          unknown: t("signalasi.common.unavailable", "Unavailable")
        ),
        copyValue: request.identityFingerprint,
        systemImage: "checkmark.shield",
        tint: .signalASIAccent,
        copiedMessage: t("signalasi.friend_request.copied_fingerprint", "Fingerprint copied"),
        monospacedSubtitle: true
      )
      statusRowIfNeeded
    }
  }

  @ViewBuilder
  private func messagingSection(_ request: SignalASIFriendRequest) -> some View {
    if !request.mqttTopic.isEmpty || !request.mqttInboxTopic.isEmpty || !request.signalBundleRef.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        SignalASISecuritySectionTitle(title: t("signalasi.contact.messaging", "Messaging"))
        if !request.mqttTopic.isEmpty {
          copyRow(
            title: t("signalasi.contact_detail.topic", "Topic"),
            value: request.mqttTopic,
            systemImage: "antenna.radiowaves.left.and.right",
            tint: .purple,
            copiedMessage: t("signalasi.friend_request.copied_topic", "Topic copied"),
            monospacedSubtitle: true
          )
        }
        if !request.mqttInboxTopic.isEmpty {
          copyRow(
            title: t("signalasi.contact_detail.inbox", "Inbox"),
            value: request.mqttInboxTopic,
            systemImage: "tray.and.arrow.down",
            tint: .teal,
            copiedMessage: t("signalasi.friend_request.copied_inbox", "Inbox copied"),
            monospacedSubtitle: true
          )
        }
        if !request.signalBundleRef.isEmpty {
          copyRow(
            title: t("signalasi.contact_detail.bundle", "Bundle"),
            value: request.signalBundleRef,
            systemImage: "shippingbox",
            tint: .orange,
            copiedMessage: t("signalasi.friend_request.copied_bundle", "Bundle copied"),
            monospacedSubtitle: true
          )
        }
      }
    }
  }

  @ViewBuilder
  private func connectorSection(_ request: SignalASIFriendRequest) -> some View {
    if hasConnectorDetails(request) {
      VStack(alignment: .leading, spacing: 8) {
        SignalASISecuritySectionTitle(title: t("contact_connector_section", "Connector"))
        if !request.desktopName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
           !request.desktopId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          copyRow(
            title: t("signalasi.pairing.section_desktop", "Desktop"),
            value: request.desktopName.ifBlank(request.desktopId),
            copyValue: request.desktopId.ifBlank(request.desktopName),
            systemImage: "desktopcomputer",
            tint: .signalASIInsightText,
            copiedMessage: t("signalasi.contact_detail.copied_desktop", "Desktop copied")
          )
        }
        if !request.setupDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          SignalASISecurityStatusRow(
            title: t("common_status", "Status"),
            subtitle: request.setupDetail,
            systemImage: "person.crop.circle.badge.checkmark",
            tint: .orange,
            badge: t("signalasi.friend_request.pending", "Pending Verification")
          )
        }
        if !request.setupNextStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          SignalASISecurityStatusRow(
            title: t("common_next_step", "Next Step"),
            subtitle: request.setupNextStep,
            systemImage: "arrow.right.circle",
            tint: .orange,
            badge: t("signalasi.common.view", "View")
          )
        }
        if !request.desktopAccessProfile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          SignalASISecurityStatusRow(
            title: t("signalasi.contact_detail.access_profile", "Access Profile"),
            subtitle: request.desktopAccessProfile,
            systemImage: "lock.shield",
            tint: .purple,
            badge: t("signalasi.contact_detail.desktop_access", "Desktop Access"),
            monospacedSubtitle: true
          )
        }
        if !request.desktopAccessScopes.isEmpty {
          SignalASISecurityStatusRow(
            title: t("signalasi.contact_detail.access_scopes", "Access Scopes"),
            subtitle: request.desktopAccessScopes.joined(separator: ", "),
            systemImage: "list.bullet",
            tint: .blue,
            badge: String(
              format: t("signalasi.contact_detail.scope_count", "%d scopes"),
              request.desktopAccessScopes.count
            ),
            monospacedSubtitle: true
          )
        }
      }
    }
  }

  private func requestStateSection(_ request: SignalASIFriendRequest) -> some View {
    let added = isAdded(request)
    return VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("common_status", "Status"))
      SignalASISecurityStatusRow(
        title: added || (request.status == .pending && request.direction == .outgoing)
          ? t("signalasi.friend_request.sent_section", "Requests Sent")
          : t("signalasi.friend_request.pending", "Pending Verification"),
        subtitle: statusSubtitle(for: request),
        systemImage: added || request.status != .pending ? "checkmark.circle" : "clock",
        tint: added || request.status != .pending ? .signalASIAccent : .orange,
        badge: statusLabel(for: request)
      )
      if request.previouslyDeleted || request.readdRequired {
        SignalASISecurityStatusRow(
          title: t("signalasi.friend_request.readd_required", "Re-add Required"),
          subtitle: t(
            "signalasi.friend_request.readd_required_subtitle",
            "A previous trust record was deleted; approving creates a fresh verified contact."
          ),
          systemImage: "arrow.clockwise.circle",
          tint: .orange,
          badge: t("signalasi.friend_request.pending", "Pending Verification")
        )
      }
    }
  }

  @ViewBuilder
  private func actionSection(_ request: SignalASIFriendRequest) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("signalasi.common.actions", "Actions"))
      if isAdded(request) {
        SignalASISecurityStatusRow(
          title: t("signalasi.friend_request.status_added", "Added"),
          subtitle: t("signalasi.friend_request.approved_subtitle", "This request has already been added to Contacts"),
          systemImage: "checkmark.circle",
          tint: .signalASIAccent,
          badge: t("signalasi.friend_request.status_added", "Added")
        )
      } else if request.status == .pending && request.direction == .outgoing {
        SignalASISecurityStatusRow(
          title: t("signalasi.friend_request.waiting", "Waiting"),
          subtitle: t(
            "signalasi.friend_request.waiting_subtitle",
            "This contact will appear after they approve your request"
          ),
          systemImage: "clock",
          tint: .orange,
          badge: t("signalasi.friend_request.waiting", "Waiting")
        )
      } else if request.status == .pending {
        SignalASISecurityPrimaryButton(
          title: t("signalasi.friend_request.approve", "Approve"),
          systemImage: "checkmark.circle",
          tint: .signalASIAccent
        ) {
          approve(request)
        }
        SignalASISecurityActionRow(
          title: t("signalasi.friend_request.reject", "Reject"),
          subtitle: t("signalasi.friend_request.reject_subtitle", "Reject this request without adding a contact"),
          systemImage: "xmark.circle",
          tint: .red,
          badge: t("signalasi.friend_request.reject", "Reject")
        ) {
          reject(request)
        }
      } else {
        SignalASISecurityStatusRow(
          title: t("signalasi.friend_request.processed", "Request Processed"),
          subtitle: statusSubtitle(for: request),
          systemImage: "checkmark.circle",
          tint: .signalASITextSecondary,
          badge: statusLabel(for: request)
        )
      }
    }
  }

  @ViewBuilder
  private var statusRowIfNeeded: some View {
    if !statusText.isEmpty {
      SignalASISecurityStatusRow(
        title: t("common_status", "Status"),
        subtitle: statusText,
        systemImage: statusIsError ? "xmark.circle" : "checkmark.circle",
        tint: statusIsError ? .red : .signalASIAccent,
        badge: statusIsError
          ? t("signalasi.status.needs_setup", "Needs Setup")
          : t("common_saved", "Saved")
      )
    }
  }

  private func copyRow(
    title: String,
    value: String,
    copyValue: String? = nil,
    systemImage: String,
    tint: Color,
    copiedMessage: String,
    monospacedSubtitle: Bool = false
  ) -> some View {
    SignalASISecurityActionRow(
      title: title,
      subtitle: value.ifBlank("-"),
      systemImage: systemImage,
      tint: tint,
      badge: t("common_copy", "Copy"),
      monospacedSubtitle: monospacedSubtitle
    ) {
      let copied = (copyValue ?? value).trimmingCharacters(in: .whitespacesAndNewlines)
      guard !copied.isEmpty else { return }
      UIPasteboard.general.string = copied
      setStatus(copiedMessage)
    }
  }

  private func approve(_ request: SignalASIFriendRequest) {
    Task { @MainActor in
      if request.opaquePhoneRoutes != nil {
        let result = await coordinator.publishPhoneContactDecision(
          contactId: request.signalASIId,
          approved: true
        )
        guard result.accepted else {
          setStatus(
            t("signalasi.friend_request.decision_failed", "The contact decision could not be sent."),
            isError: true
          )
          return
        }
      }
      if store.approveFriendRequest(id: request.id) {
        await coordinator.recoverPhoneContactSessionIfNeeded(contactId: request.signalASIId)
        setStatus(t("signalasi.friend_request.added_to_contacts", "Added to Contacts"))
        onContactAccepted()
        dismiss()
      } else {
        setStatus(t("signalasi.friend_request.not_found", "Friend request not found."), isError: true)
      }
    }
  }

  private func reject(_ request: SignalASIFriendRequest) {
    Task { @MainActor in
      if request.opaquePhoneRoutes != nil {
        let result = await coordinator.publishPhoneContactDecision(
          contactId: request.signalASIId,
          approved: false
        )
        guard result.accepted else {
          setStatus(
            t("signalasi.friend_request.decision_failed", "The contact decision could not be sent."),
            isError: true
          )
          return
        }
      }
      if store.rejectFriendRequest(id: request.id) {
        setStatus(t("signalasi.common.rejected", "Rejected"))
        dismiss()
      } else {
        setStatus(t("signalasi.friend_request.not_found", "Friend request not found."), isError: true)
      }
    }
  }

  private func signalASIId(for request: SignalASIFriendRequest) -> String {
    request.signalASIId.ifBlank(request.id)
  }

  private func hasConnectorDetails(_ request: SignalASIFriendRequest) -> Bool {
    !request.desktopId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
      !request.desktopName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
      !request.setupDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
      !request.setupNextStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
      !request.desktopAccessProfile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
      !request.desktopAccessScopes.isEmpty
  }

  private func statusSubtitle(for request: SignalASIFriendRequest) -> String {
    if isAdded(request) {
      return t("signalasi.friend_request.approved_subtitle", "This request has already been added to Contacts")
    }
    switch request.status {
    case .pending:
      if request.direction == .outgoing {
        return t(
          "signalasi.friend_request.waiting_subtitle",
          "This contact will appear after they approve your request"
        )
      }
      return t("signalasi.friend_request.pending_subtitle", "Verify identity before approving this contact")
    case .approved:
      return t("signalasi.friend_request.approved_subtitle", "This request has already been added to Contacts")
    case .rejected:
      return t("signalasi.friend_request.rejected_subtitle", "This request was rejected on this device")
    case .deleted:
      return t("signalasi.friend_request.deleted_subtitle", "This request was deleted and requires a fresh QR scan")
    }
  }

  private func statusLabel(for request: SignalASIFriendRequest) -> String {
    if isAdded(request) {
      return t("signalasi.friend_request.status_added", "Added")
    }
    switch request.status {
    case .pending:
      if request.direction == .outgoing {
        return t("signalasi.friend_request.waiting", "Waiting")
      }
      return t("signalasi.friend_request.pending", "Pending Verification")
    case .approved:
      return t("signalasi.friend_request.status_approved", "Approved")
    case .rejected:
      return t("signalasi.common.rejected", "Rejected")
    case .deleted:
      return t("signalasi.security_center.status_revoked", "Revoked")
    }
  }

  private func isAdded(_ request: SignalASIFriendRequest) -> Bool {
    SignalASIFriendRequestPresentationPolicy.isAdded(
      request,
      contactIsVerified: store.contact(id: request.signalASIId)?.isCommunicable == true
    )
  }

  private func setStatus(_ message: String, isError: Bool = false) {
    statusText = message
    statusIsError = isError
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct FriendRequestHeroView: View {
  var name: String
  var signalASIId: String
  var badge: String
  var pending: Bool

  var body: some View {
    HStack(alignment: .center, spacing: 14) {
      ZStack {
        Circle()
          .fill(Color.signalASIAccent.opacity(0.16))
        Image(systemName: "person.crop.circle.badge.plus")
          .font(.system(size: 34, weight: .semibold))
          .foregroundColor(.signalASIAccent)
      }
      .frame(width: 72, height: 72)
      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 8) {
          Text(name)
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(.signalASITextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
          Text(badge)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(pending ? .orange : .signalASIAccent)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 7)
            .frame(minHeight: 22)
            .background((pending ? Color.orange : Color.signalASIAccent).opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        Text(signalASIId)
          .font(.system(size: 12, design: .monospaced))
          .foregroundColor(.signalASITextSecondary)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct FriendRequestEmptyView: View {
  var title: String
  var subtitle: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Image(systemName: "person.2")
        .font(.system(size: 34, weight: .semibold))
        .foregroundColor(.signalASITextSecondary)
      Text(title)
        .font(.system(size: 22, weight: .bold))
        .foregroundColor(.signalASITextPrimary)
      Text(subtitle)
        .font(.system(size: 14))
        .foregroundColor(.signalASITextSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
