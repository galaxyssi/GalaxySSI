import SwiftUI
import UIKit

struct FriendRequestDetailView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var store: GalaxySSIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var statusText = ""
  @State private var statusIsError = false
  var requestId: String
  var onContactAccepted: () -> Void = {}

  private var request: GalaxySSIFriendRequest? {
    store.friendRequest(id: requestId)
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: request?.name ?? t("galaxyssi.friend_request.title", "Friend Request"),
        leading: {
          GalaxySSIBackButton()
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
              galaxySSIId: galaxySSIId(for: request),
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
              title: t("galaxyssi.friend_request.not_found", "Friend request not found."),
              subtitle: t(
                "galaxyssi.friend_request.not_found_subtitle",
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
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private func identitySection(_ request: GalaxySSIFriendRequest) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("galaxyssi.contact.section_identity", "Identity"))
      copyRow(
        title: t("settings_galaxyssi_id", "GalaxySSI ID"),
        value: galaxySSIId(for: request),
        systemImage: "link",
        tint: .blue,
        copiedMessage: t("galaxyssi.friend_request.copied_id", "GalaxySSI ID copied")
      )
      copyRow(
        title: t("settings_identity_fingerprint", "Fingerprint"),
        value: GalaxySSISecurityFormatter.fingerprint(
          request.identityFingerprint,
          unknown: t("galaxyssi.common.unavailable", "Unavailable")
        ),
        copyValue: request.identityFingerprint,
        systemImage: "checkmark.shield",
        tint: .galaxySSIAccent,
        copiedMessage: t("galaxyssi.friend_request.copied_fingerprint", "Fingerprint copied"),
        monospacedSubtitle: true
      )
      statusRowIfNeeded
    }
  }

  @ViewBuilder
  private func messagingSection(_ request: GalaxySSIFriendRequest) -> some View {
    if !request.mqttTopic.isEmpty || !request.mqttInboxTopic.isEmpty || !request.signalBundleRef.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        GalaxySSISecuritySectionTitle(title: t("galaxyssi.contact.messaging", "Messaging"))
        if !request.mqttTopic.isEmpty {
          copyRow(
            title: t("galaxyssi.contact_detail.topic", "Topic"),
            value: request.mqttTopic,
            systemImage: "antenna.radiowaves.left.and.right",
            tint: .purple,
            copiedMessage: t("galaxyssi.friend_request.copied_topic", "Topic copied"),
            monospacedSubtitle: true
          )
        }
        if !request.mqttInboxTopic.isEmpty {
          copyRow(
            title: t("galaxyssi.contact_detail.inbox", "Inbox"),
            value: request.mqttInboxTopic,
            systemImage: "tray.and.arrow.down",
            tint: .teal,
            copiedMessage: t("galaxyssi.friend_request.copied_inbox", "Inbox copied"),
            monospacedSubtitle: true
          )
        }
        if !request.signalBundleRef.isEmpty {
          copyRow(
            title: t("galaxyssi.contact_detail.bundle", "Bundle"),
            value: request.signalBundleRef,
            systemImage: "shippingbox",
            tint: .orange,
            copiedMessage: t("galaxyssi.friend_request.copied_bundle", "Bundle copied"),
            monospacedSubtitle: true
          )
        }
      }
    }
  }

  @ViewBuilder
  private func connectorSection(_ request: GalaxySSIFriendRequest) -> some View {
    if hasConnectorDetails(request) {
      VStack(alignment: .leading, spacing: 8) {
        GalaxySSISecuritySectionTitle(title: t("contact_connector_section", "Connector"))
        if !request.desktopName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
           !request.desktopId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          copyRow(
            title: t("galaxyssi.pairing.section_desktop", "Desktop"),
            value: request.desktopName.ifBlank(request.desktopId),
            copyValue: request.desktopId.ifBlank(request.desktopName),
            systemImage: "desktopcomputer",
            tint: .galaxySSIInsightText,
            copiedMessage: t("galaxyssi.contact_detail.copied_desktop", "Desktop copied")
          )
        }
        if !request.setupDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          GalaxySSISecurityStatusRow(
            title: t("common_status", "Status"),
            subtitle: request.setupDetail,
            systemImage: "person.crop.circle.badge.checkmark",
            tint: .orange,
            badge: t("galaxyssi.friend_request.pending", "Pending Verification")
          )
        }
        if !request.setupNextStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          GalaxySSISecurityStatusRow(
            title: t("common_next_step", "Next Step"),
            subtitle: request.setupNextStep,
            systemImage: "arrow.right.circle",
            tint: .orange,
            badge: t("galaxyssi.common.view", "View")
          )
        }
        if !request.desktopAccessProfile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          GalaxySSISecurityStatusRow(
            title: t("galaxyssi.contact_detail.access_profile", "Access Profile"),
            subtitle: request.desktopAccessProfile,
            systemImage: "lock.shield",
            tint: .purple,
            badge: t("galaxyssi.contact_detail.desktop_access", "Desktop Access"),
            monospacedSubtitle: true
          )
        }
        if !request.desktopAccessScopes.isEmpty {
          GalaxySSISecurityStatusRow(
            title: t("galaxyssi.contact_detail.access_scopes", "Access Scopes"),
            subtitle: request.desktopAccessScopes.joined(separator: ", "),
            systemImage: "list.bullet",
            tint: .blue,
            badge: String(
              format: t("galaxyssi.contact_detail.scope_count", "%d scopes"),
              request.desktopAccessScopes.count
            ),
            monospacedSubtitle: true
          )
        }
      }
    }
  }

  private func requestStateSection(_ request: GalaxySSIFriendRequest) -> some View {
    let added = isAdded(request)
    return VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("common_status", "Status"))
      GalaxySSISecurityStatusRow(
        title: added || (request.status == .pending && request.direction == .outgoing)
          ? t("galaxyssi.friend_request.sent_section", "Requests Sent")
          : t("galaxyssi.friend_request.pending", "Pending Verification"),
        subtitle: statusSubtitle(for: request),
        systemImage: added || request.status != .pending ? "checkmark.circle" : "clock",
        tint: added || request.status != .pending ? .galaxySSIAccent : .orange,
        badge: statusLabel(for: request)
      )
      if request.previouslyDeleted || request.readdRequired {
        GalaxySSISecurityStatusRow(
          title: t("galaxyssi.friend_request.readd_required", "Re-add Required"),
          subtitle: t(
            "galaxyssi.friend_request.readd_required_subtitle",
            "A previous trust record was deleted; approving creates a fresh verified contact."
          ),
          systemImage: "arrow.clockwise.circle",
          tint: .orange,
          badge: t("galaxyssi.friend_request.pending", "Pending Verification")
        )
      }
    }
  }

  @ViewBuilder
  private func actionSection(_ request: GalaxySSIFriendRequest) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("galaxyssi.common.actions", "Actions"))
      if isAdded(request) {
        GalaxySSISecurityStatusRow(
          title: t("galaxyssi.friend_request.status_added", "Added"),
          subtitle: t("galaxyssi.friend_request.approved_subtitle", "This request has already been added to Contacts"),
          systemImage: "checkmark.circle",
          tint: .galaxySSIAccent,
          badge: t("galaxyssi.friend_request.status_added", "Added")
        )
      } else if request.status == .pending && request.direction == .outgoing {
        GalaxySSISecurityStatusRow(
          title: t("galaxyssi.friend_request.waiting", "Waiting"),
          subtitle: t(
            "galaxyssi.friend_request.waiting_subtitle",
            "This contact will appear after they approve your request"
          ),
          systemImage: "clock",
          tint: .orange,
          badge: t("galaxyssi.friend_request.waiting", "Waiting")
        )
      } else if request.status == .pending {
        GalaxySSISecurityPrimaryButton(
          title: t("galaxyssi.friend_request.approve", "Approve"),
          systemImage: "checkmark.circle",
          tint: .galaxySSIAccent
        ) {
          approve(request)
        }
        GalaxySSISecurityActionRow(
          title: t("galaxyssi.friend_request.reject", "Reject"),
          subtitle: t("galaxyssi.friend_request.reject_subtitle", "Reject this request without adding a contact"),
          systemImage: "xmark.circle",
          tint: .red,
          badge: t("galaxyssi.friend_request.reject", "Reject")
        ) {
          reject(request)
        }
      } else {
        GalaxySSISecurityStatusRow(
          title: t("galaxyssi.friend_request.processed", "Request Processed"),
          subtitle: statusSubtitle(for: request),
          systemImage: "checkmark.circle",
          tint: .galaxySSITextSecondary,
          badge: statusLabel(for: request)
        )
      }
    }
  }

  @ViewBuilder
  private var statusRowIfNeeded: some View {
    if !statusText.isEmpty {
      GalaxySSISecurityStatusRow(
        title: t("common_status", "Status"),
        subtitle: statusText,
        systemImage: statusIsError ? "xmark.circle" : "checkmark.circle",
        tint: statusIsError ? .red : .galaxySSIAccent,
        badge: statusIsError
          ? t("galaxyssi.status.needs_setup", "Needs Setup")
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
    GalaxySSISecurityActionRow(
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

  private func approve(_ request: GalaxySSIFriendRequest) {
    Task { @MainActor in
      if request.opaquePhoneRoutes != nil {
        let result = await coordinator.publishPhoneContactDecision(
          contactId: request.galaxySSIId,
          approved: true
        )
        guard result.accepted else {
          setStatus(
            t("galaxyssi.friend_request.decision_failed", "The contact decision could not be sent."),
            isError: true
          )
          return
        }
      }
      if store.approveFriendRequest(id: request.id) {
        await coordinator.recoverPhoneContactSessionIfNeeded(contactId: request.galaxySSIId)
        setStatus(t("galaxyssi.friend_request.added_to_contacts", "Added to Contacts"))
        onContactAccepted()
        dismiss()
      } else {
        setStatus(t("galaxyssi.friend_request.not_found", "Friend request not found."), isError: true)
      }
    }
  }

  private func reject(_ request: GalaxySSIFriendRequest) {
    Task { @MainActor in
      if request.opaquePhoneRoutes != nil {
        let result = await coordinator.publishPhoneContactDecision(
          contactId: request.galaxySSIId,
          approved: false
        )
        guard result.accepted else {
          setStatus(
            t("galaxyssi.friend_request.decision_failed", "The contact decision could not be sent."),
            isError: true
          )
          return
        }
      }
      if store.rejectFriendRequest(id: request.id) {
        setStatus(t("galaxyssi.common.rejected", "Rejected"))
        dismiss()
      } else {
        setStatus(t("galaxyssi.friend_request.not_found", "Friend request not found."), isError: true)
      }
    }
  }

  private func galaxySSIId(for request: GalaxySSIFriendRequest) -> String {
    request.galaxySSIId.ifBlank(request.id)
  }

  private func hasConnectorDetails(_ request: GalaxySSIFriendRequest) -> Bool {
    !request.desktopId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
      !request.desktopName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
      !request.setupDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
      !request.setupNextStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
      !request.desktopAccessProfile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
      !request.desktopAccessScopes.isEmpty
  }

  private func statusSubtitle(for request: GalaxySSIFriendRequest) -> String {
    if isAdded(request) {
      return t("galaxyssi.friend_request.approved_subtitle", "This request has already been added to Contacts")
    }
    switch request.status {
    case .pending:
      if request.direction == .outgoing {
        return t(
          "galaxyssi.friend_request.waiting_subtitle",
          "This contact will appear after they approve your request"
        )
      }
      return t("galaxyssi.friend_request.pending_subtitle", "Verify identity before approving this contact")
    case .approved:
      return t("galaxyssi.friend_request.approved_subtitle", "This request has already been added to Contacts")
    case .rejected:
      return t("galaxyssi.friend_request.rejected_subtitle", "This request was rejected on this device")
    case .deleted:
      return t("galaxyssi.friend_request.deleted_subtitle", "This request was deleted and requires a fresh QR scan")
    }
  }

  private func statusLabel(for request: GalaxySSIFriendRequest) -> String {
    if isAdded(request) {
      return t("galaxyssi.friend_request.status_added", "Added")
    }
    switch request.status {
    case .pending:
      if request.direction == .outgoing {
        return t("galaxyssi.friend_request.waiting", "Waiting")
      }
      return t("galaxyssi.friend_request.pending", "Pending Verification")
    case .approved:
      return t("galaxyssi.friend_request.status_approved", "Approved")
    case .rejected:
      return t("galaxyssi.common.rejected", "Rejected")
    case .deleted:
      return t("galaxyssi.security_center.status_revoked", "Revoked")
    }
  }

  private func isAdded(_ request: GalaxySSIFriendRequest) -> Bool {
    GalaxySSIFriendRequestPresentationPolicy.isAdded(
      request,
      contactIsVerified: store.contact(id: request.galaxySSIId)?.isCommunicable == true
    )
  }

  private func setStatus(_ message: String, isError: Bool = false) {
    statusText = message
    statusIsError = isError
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct FriendRequestHeroView: View {
  var name: String
  var galaxySSIId: String
  var badge: String
  var pending: Bool

  var body: some View {
    HStack(alignment: .center, spacing: 14) {
      ZStack {
        Circle()
          .fill(Color.galaxySSIAccent.opacity(0.16))
        Image(systemName: "person.crop.circle.badge.plus")
          .font(.system(size: 34, weight: .semibold))
          .foregroundColor(.galaxySSIAccent)
      }
      .frame(width: 72, height: 72)
      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 8) {
          Text(name)
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(.galaxySSITextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
          Text(badge)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(pending ? .orange : .galaxySSIAccent)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 7)
            .frame(minHeight: 22)
            .background((pending ? Color.orange : Color.galaxySSIAccent).opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        Text(galaxySSIId)
          .font(.system(size: 12, design: .monospaced))
          .foregroundColor(.galaxySSITextSecondary)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(Color.galaxySSISurface)
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
        .foregroundColor(.galaxySSITextSecondary)
      Text(title)
        .font(.system(size: 22, weight: .bold))
        .foregroundColor(.galaxySSITextPrimary)
      Text(subtitle)
        .font(.system(size: 14))
        .foregroundColor(.galaxySSITextSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
