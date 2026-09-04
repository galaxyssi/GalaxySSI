import SwiftUI
import UIKit

extension Notification.Name {
  static let galaxySSIDesktopPairingDidComplete = Notification.Name(
    "galaxyssi.desktopPairingDidComplete"
  )
  static let galaxySSIContactImportDidComplete = Notification.Name(
    "galaxyssi.contactImportDidComplete"
  )
}

struct AddContactView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var myQRCodePresented = false
  @State private var contactScannerPresented = false
  @State private var manualPastePresented = false
  @State private var contactImportStatus = ""
  @State private var contactImportIsError = false
  @State private var scannedQRCodeText = ""
  @State private var pastedQRCodeText = ""
  @State private var pendingPairing: PairingQRCode?
  @State private var pendingFriendRequest: GalaxySSIFriendRequest?
  @State private var pendingScannedRequests: [GalaxySSIFriendRequest] = []
  @State private var pairedDesktopName = ""
  @State private var pairedDesktopAgentNames: [String] = []
  @State private var pairingInFlight = false
  @State private var scannerAutoOpened = false

  private let autoOpenScanner: Bool
  private let onAgentAdded: (([String]) -> Void)?
  private let onImportCompleted: (() -> Void)?
  private let onCloudModelAdded: ((GalaxySSIContact) -> Void)?

  init(
    autoOpenScanner: Bool = false,
    onAgentAdded: (([String]) -> Void)? = nil,
    onImportCompleted: (() -> Void)? = nil,
    onCloudModelAdded: ((GalaxySSIContact) -> Void)? = nil
  ) {
    self.autoOpenScanner = autoOpenScanner
    self.onAgentAdded = onAgentAdded
    self.onImportCompleted = onImportCompleted
    self.onCloudModelAdded = onCloudModelAdded
  }

  private var pendingScannedAgentRequests: [GalaxySSIFriendRequest] {
    pendingScannedRequests.filter { $0.type == "agent" }
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("galaxyssi.add_contact.title", "Add"),
        leading: {
          GalaxySSIBackButton()
        },
        trailing: {
          Button {
            myQRCodePresented = true
          } label: {
            Image(systemName: "qrcode")
              .font(.system(size: 19, weight: .semibold))
              .foregroundColor(.galaxySSITextPrimary)
          }
          .buttonStyle(.plain)
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          AddContactHeroView(
            title: t("galaxyssi.add_contact.hero_title", "Add Contact"),
            subtitle: t(
              "galaxyssi.add_contact.hero_subtitle",
              "Scan trusted contacts, or add multiple cloud models directly on the phone."
            )
          )
          sectionTitle(t("galaxyssi.add_contact.section_methods", "Methods"))
          VStack(spacing: 8) {
            AddContactActionRow(
              title: t("galaxyssi.add_contact.scan_title", "Scan to Add Contact"),
              subtitle: t("galaxyssi.add_contact.scan_subtitle", "Add Hermes, computers, friends, or devices"),
              systemImage: "qrcode.viewfinder",
              tint: .galaxySSIAccent,
              badge: t("galaxyssi.pairing.action_scan", "Scan")
            ) {
              contactScannerPresented = true
            }
            AddContactNavigationRow(
              title: t("galaxyssi.add_contact.cloud_title", "Add Cloud Model"),
              subtitle: t(
                "galaxyssi.add_contact.cloud_subtitle",
                "Provider, model, and API key are configured directly on the phone."
              ),
              systemImage: "cloud.fill",
              tint: .galaxySSIInsightText,
              badge: t("galaxyssi.add_contact.title", "Add")
            ) {
              if let onCloudModelAdded {
                CloudModelProviderSelectionView { contact in
                  notifyImportCompleted()
                  onCloudModelAdded(contact)
                }
              } else {
                CloudModelProviderSelectionView()
              }
            }
            AddContactActionRow(
              title: t("galaxyssi.add_contact.my_qr_title", "My QR Code"),
              subtitle: t("galaxyssi.add_contact.my_qr_subtitle", "Show this device identity"),
              systemImage: "qrcode",
              tint: .galaxySSITextPrimary,
              badge: t("galaxyssi.common.show", "Show")
            ) {
              myQRCodePresented = true
            }
            AddContactActionRow(
              title: t("galaxyssi.add_contact.paste_title", "Paste QR Payload"),
              subtitle: t("galaxyssi.add_contact.paste_subtitle", "Use a copied GalaxySSI QR code when camera scan is unavailable"),
              systemImage: "doc.on.clipboard",
              tint: .orange,
              badge: t("galaxyssi.common.import", "Import")
            ) {
              manualPastePresented.toggle()
            }
          }
          if manualPastePresented {
            AddContactPasteCard(
              title: t("galaxyssi.add_contact.paste_title", "Paste QR Payload"),
              placeholder: t("galaxyssi.add_contact.paste_placeholder", "Paste GalaxySSI QR JSON here"),
              actionTitle: t("galaxyssi.common.import", "Import"),
              text: $pastedQRCodeText
            ) {
              importScannedQR(pastedQRCodeText)
            }
          }
          if let pendingPairing {
            sectionTitle(t("galaxyssi.pairing.confirm_title", "Confirm Pairing"))
            AddContactPairingConfirmCard(
              pairing: pendingPairing,
              phoneFingerprint: store.profile.identityFingerprint,
              isSubmitting: pairingInFlight,
              confirmTitle: t("galaxyssi.pairing.confirm_title", "Confirm Pairing"),
              cancelTitle: t("galaxyssi.common.cancel", "Cancel"),
              onConfirm: {
                Task { await confirmDesktopPairing() }
              },
              onCancel: clearPendingScanResult,
              t: t
            )
          }
          if !pendingScannedAgentRequests.isEmpty {
            let agentCount = pendingScannedAgentRequests.count
            sectionTitle(t("galaxyssi.pairing.scanned_agents_title", "Scanned Agents"))
            AddContactBulkAgentImportCard(
              count: agentCount,
              title: t("galaxyssi.pairing.scanned_agents_title", "Scanned Agents"),
              subtitle: scannedAgentsSubtitle(count: agentCount),
              approveTitle: scannedAgentsApproveTitle(count: agentCount),
              cancelTitle: t("galaxyssi.common.cancel", "Cancel"),
              onApprove: approvePendingScannedRequests,
              onCancel: clearPendingScanResult
            )
          }
          if let pendingFriendRequest, pendingScannedAgentRequests.isEmpty {
            sectionTitle(
              pendingFriendRequest.direction == .outgoing
                ? t("galaxyssi.friend_request.sent_section", "Requests Sent")
                : t("galaxyssi.friend_request.received_section", "Requests Received")
            )
            AddContactFriendRequestCard(
              request: pendingFriendRequest,
              approveTitle: t("galaxyssi.friend_request.approve", "Approve"),
              rejectTitle: t("galaxyssi.friend_request.reject", "Reject"),
              waitingTitle: t("galaxyssi.friend_request.waiting", "Waiting"),
              allowsDecision: pendingFriendRequest.direction == .incoming,
              onApprove: {
                approveFriendRequest(pendingFriendRequest)
              },
              onReject: {
                rejectFriendRequest(pendingFriendRequest)
              },
              t: t
            )
          }
          if !pairedDesktopAgentNames.isEmpty {
            sectionTitle(t("galaxyssi.pairing.added_agents_title", "Added Agents"))
            AddContactPairedAgentsCard(
              desktopName: pairedDesktopName,
              agentNames: pairedDesktopAgentNames,
              title: t("galaxyssi.pairing.added_agents_title", "Added Agents"),
              subtitle: String(
                format: t(
                  "galaxyssi.pairing.added_agents_subtitle",
                  "%d Agents from %@ are available in Contacts."
                ),
                pairedDesktopAgentNames.count,
                pairedDesktopName.ifBlank(t("desktop_control_title", "Control Computer"))
              ),
              viewContactsTitle: t("galaxyssi.pairing.view_contacts", "View Contacts"),
              t: t
            )
          }
          if !store.pendingFriendRequests.isEmpty {
            friendRequestList(
              title: t("galaxyssi.friend_request.received_section", "Requests Received"),
              requests: store.pendingFriendRequests.filter { $0.direction == .incoming },
              allowsDecision: true
            )
            friendRequestList(
              title: t("galaxyssi.friend_request.sent_section", "Requests Sent"),
              requests: store.pendingFriendRequests.filter { $0.direction == .outgoing },
              allowsDecision: false
            )
          }
          if !contactImportStatus.isEmpty {
            Text(contactImportStatus)
              .font(.system(size: 13))
              .foregroundColor(contactImportIsError ? .red : .galaxySSITextSecondary)
              .padding(.horizontal, 4)
              .padding(.top, 4)
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .sheet(isPresented: $myQRCodePresented) {
      MyContactQRCodeView()
    }
    .fullScreenCover(isPresented: $contactScannerPresented) {
      QRCodeScannerView(
        onCode: { value in
          contactScannerPresented = false
          importScannedQR(value, autoConfirmPairing: true)
        },
        onError: { message in
          contactScannerPresented = false
          setImportStatus(message, isError: true)
        },
        onCancel: {
          contactScannerPresented = false
        }
      )
    }
    .task {
      guard autoOpenScanner, !scannerAutoOpened else { return }
      scannerAutoOpened = true
      // SwiftUI cancels this task when the Add page disappears, so a delayed
      // scanner presentation cannot outlive the sheet that requested it.
      try? await Task.sleep(nanoseconds: 350_000_000)
      guard !Task.isCancelled, autoOpenScanner else { return }
      contactScannerPresented = true
    }
  }

  @ViewBuilder
  private func friendRequestList(
    title: String,
    requests: [GalaxySSIFriendRequest],
    allowsDecision: Bool
  ) -> some View {
    if !requests.isEmpty {
      sectionTitle(title)
      VStack(spacing: 0) {
        ForEach(requests) { request in
          AddContactFriendRequestRow(
            request: request,
            approveTitle: t("galaxyssi.friend_request.approve", "Approve"),
            rejectTitle: t("galaxyssi.friend_request.reject", "Reject"),
            waitingTitle: t("galaxyssi.friend_request.waiting", "Waiting"),
            allowsDecision: allowsDecision,
            onApprove: { approveFriendRequest(request) },
            onReject: { rejectFriendRequest(request) },
            t: t
          )
          if request.id != requests.last?.id {
            Divider()
              .background(Color.galaxySSISeparator)
              .padding(.leading, 58)
          }
        }
      }
      .background(Color.galaxySSISurface)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.galaxySSITextSecondary)
      .padding(.horizontal, 4)
      .padding(.top, 2)
  }

  private func importScannedQR(_ value: String, autoConfirmPairing: Bool = false) {
    let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else {
      setImportStatus(t("galaxyssi.pairing.invalid_qr", "Invalid QR code"), isError: true)
      return
    }
    scannedQRCodeText = cleaned
    pastedQRCodeText = cleaned
    pairedDesktopName = ""
    pairedDesktopAgentNames = []
    do {
      switch try GalaxySSIContactExchange.classifyQRCode(cleaned) {
      case .desktopPairing(let pairing):
        pendingPairing = pairing
        pendingFriendRequest = nil
        pendingScannedRequests = []
        setImportStatus(
          t("galaxyssi.pairing.ready_to_confirm", "Review fingerprints, then save trust."),
          isError: false
        )
        if autoConfirmPairing, GalaxySSILinkProtocol.hasVerifiedDesktopIdentity(pairing) {
          Task { await confirmDesktopPairing(pairing: pairing) }
        }
      case .contact(let request):
        if request.type == "agent" {
          importScannedAgentContacts(cleaned, requests: [request])
          return
        }
        importScannedPhoneContact(request, qrText: cleaned)
      case .contacts(let requests):
        if requests.allSatisfy({ $0.type == "agent" }) {
          importScannedAgentContacts(cleaned, requests: requests)
          return
        }
        let stored = requests.map { store.addFriendRequest($0) }
        pendingPairing = nil
        pendingFriendRequest = stored.first
        pendingScannedRequests = stored
        setImportStatus(requestsReceivedStatus(stored), isError: false)
        notifyImportCompleted()
      }
    } catch {
      importDesktopAgentQRCodeFallback(cleaned, fallbackError: error)
    }
  }

  private func importScannedAgentContacts(
    _ value: String,
    requests: [GalaxySSIFriendRequest]
  ) {
    let existingAgentIDs = Set(
      store.visibleContacts
        .filter { $0.type == "agent" }
        .map(\.id)
    )
    do {
      let importedCount = try store.importDesktopAgentQRCodeAsContacts(value)
      guard importedCount > 0 else {
        let stored = requests.map { store.addFriendRequest($0) }
        pendingPairing = nil
        pendingFriendRequest = stored.first
        pendingScannedRequests = stored
        setImportStatus(requestsReceivedStatus(stored), isError: false)
        return
      }
      _ = coordinator.requestCapabilityManifestRefresh(force: true)
      let importedAgentIDs = importedAgentIDsFromQRCode(
        value,
        fallback: store.visibleContacts
          .filter { $0.type == "agent" && !existingAgentIDs.contains($0.id) }
          .map(\.id)
      )
      clearPendingScanResult()
      pendingPairing = nil
      pendingFriendRequest = nil
      pendingScannedRequests = []
      let message = importedCount == 1
        ? t("galaxyssi.pairing.agent_request_added", "Agent added to Contacts.")
        : String(
            format: t("galaxyssi.pairing.agent_requests_added", "%d Agents added to Contacts."),
            importedCount
          )
      setImportStatus(message, isError: false)
      onAgentAdded?(importedAgentIDs)
      notifyImportCompleted()
    } catch {
      let stored = requests.map { store.addFriendRequest($0) }
      pendingPairing = nil
      pendingFriendRequest = stored.first
      pendingScannedRequests = stored
      setImportStatus(requestsReceivedStatus(stored), isError: false)
    }
  }

  private func importScannedPhoneContact(
    _ request: GalaxySSIFriendRequest,
    qrText: String
  ) {
    var outgoing = request
    outgoing.direction = .outgoing
    outgoing.isRead = true
    let stored = store.addFriendRequest(outgoing)
    pendingPairing = nil
    pendingFriendRequest = nil
    pendingScannedRequests = []
    setImportStatus(
      String(
        format: t("galaxyssi.phone_contact.request_sent", "Request sent to %@. Waiting for approval."),
        stored.name
      ),
      isError: false
    )
    Task { @MainActor in
      if stored.type == "person" {
        let result = await coordinator.requestPhoneContactPairing(qrText: qrText)
        if !result.accepted {
          setImportStatus(
            String(
              format: t(
                "galaxyssi.phone_contact.request_pending",
                "%@ was saved. The request will be sent when GalaxySSI Link reconnects."
              ),
              stored.name
            ),
            isError: false
          )
        }
      }
    }
    notifyImportCompleted()
  }

  private func importDesktopAgentQRCodeFallback(_ value: String, fallbackError: Error) {
    do {
      let existingAgentIDs = Set(
        store.visibleContacts
          .filter { $0.type == "agent" }
          .map(\.id)
      )
      let importedCount = try store.importDesktopAgentQRCodeAsContacts(value)
      guard importedCount > 0 else {
        throw fallbackError
      }
      _ = coordinator.requestCapabilityManifestRefresh(force: true)
      let importedAgentIDs = importedAgentIDsFromQRCode(value, fallback: store.visibleContacts
        .filter { $0.type == "agent" && !existingAgentIDs.contains($0.id) }
        .map(\.id))
      clearPendingScanResult()
      let message = importedCount == 1
        ? t("galaxyssi.pairing.agent_request_added", "Agent added to Contacts.")
        : String(
            format: t("galaxyssi.pairing.agent_requests_added", "%d Agents added to Contacts."),
            importedCount
          )
      setImportStatus(message, isError: false)
      onAgentAdded?(importedAgentIDs)
      notifyImportCompleted()
    } catch {
      clearPendingScanResult()
      setImportStatus(
        String(format: t("galaxyssi.pairing.scan_failed", "Scan failed: %@"), fallbackError.localizedDescription),
        isError: true
      )
    }
  }

  private func importedAgentIDsFromQRCode(_ value: String, fallback: [String]) -> [String] {
    guard let object = try? GalaxySSIQRCodePayload.decodeObject(from: value, label: "Agent QR") else {
      return fallback
    }
    let source = GalaxySSIContactExchange.connectorAgentSource(from: object)
    let agentObjects = source?.agents ?? [object]
    let rawAgentIDs: [String] = agentObjects.flatMap { agent in
      [
        agent.string("agent_id"),
        agent.string("mobile_contact_id"),
        agent.string("id")
      ]
    }
    let requestedIDs = Set(
      rawAgentIDs.flatMap { rawID -> [String] in
        let cleanID = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanID.isEmpty else { return [] }
        return [cleanID, cleanID.split(separator: ":").last.map(String.init) ?? cleanID]
      }
    )
    let parent = source?.parentPayload ?? object
    let requestedDesktopID = parent.string("desktop_id")
      .ifBlank(parent.dictionary("server")?.string("desktop_id") ?? "")
      .ifBlank(parent.dictionary("desktop")?.string("desktop_id") ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let matches = store.visibleContacts
      .filter { contact in
        guard contact.type == "agent" else { return false }
        let knownIDs = [
          contact.id,
          contact.galaxySSIId,
          contact.agentId ?? "",
          contact.connectorAgentId
        ]
          .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
          .filter { !$0.isEmpty }
        if !requestedIDs.isEmpty && knownIDs.contains(where: requestedIDs.contains) {
          return true
        }
        return !requestedDesktopID.isEmpty && contact.desktopId == requestedDesktopID
      }
      .map(\.id)
    return matches.isEmpty ? fallback : matches
  }

  private func confirmDesktopPairing(pairing: PairingQRCode? = nil) async {
    guard let pairing = pairing ?? pendingPairing else { return }
    pairingInFlight = true
    setImportStatus(
      String(format: t("galaxyssi.pairing.desktop_claim_sending", "Adding %@..."), pairing.desktopName),
      isError: false
    )
    do {
      try await coordinator.pair(using: scannedQRCodeText)
      pendingPairing = nil
      pendingScannedRequests = []
      pairedDesktopName = pairing.desktopName
      pairedDesktopAgentNames = Self.desktopAgentNames(from: pairing)
      setImportStatus(
        String(
          format: t(
            "galaxyssi.pairing.desktop_claim_sent_detailed",
            "%@ added with %@. %d Agents are ready in Contacts."
          ),
          pairing.desktopName,
          pairing.access.fullDesktopExecutor
            ? t("galaxyssi.pairing.access_full", "Full Desktop Access")
            : t("galaxyssi.pairing.access_restricted", "Restricted Desktop Access"),
          Self.desktopAgentCount(pairing)
        ),
        isError: false
      )
      if !pairedDesktopAgentNames.isEmpty {
        let agentIDs = Self.desktopAgentIDs(from: pairing)
        onAgentAdded?(agentIDs)
        NotificationCenter.default.post(
          name: .galaxySSIDesktopPairingDidComplete,
          object: nil,
          userInfo: ["agentIDs": agentIDs]
        )
      }
      notifyImportCompleted()
    } catch {
      setImportStatus(error.localizedDescription, isError: true)
    }
    pairingInFlight = false
  }

  private func approveFriendRequest(_ request: GalaxySSIFriendRequest) {
    if store.approveFriendRequest(id: request.id) {
      Task { await coordinator.recoverPhoneContactSessionIfNeeded(contactId: request.galaxySSIId) }
      if pendingFriendRequest?.id == request.id {
        pendingFriendRequest = pendingScannedRequests.first
      }
      pendingScannedRequests.removeAll { $0.id == request.id }
      pendingFriendRequest = pendingScannedRequests.first
      setImportStatus(t("galaxyssi.friend_request.added_to_contacts", "Added to Contacts"), isError: false)
      notifyImportCompleted()
      if request.type == "agent" {
        onAgentAdded?([request.galaxySSIId])
      }
    } else {
      setImportStatus(t("galaxyssi.friend_request.not_found", "Friend request not found."), isError: true)
    }
  }

  private func rejectFriendRequest(_ request: GalaxySSIFriendRequest) {
    if store.rejectFriendRequest(id: request.id) {
      if pendingFriendRequest?.id == request.id {
        pendingFriendRequest = pendingScannedRequests.first
      }
      pendingScannedRequests.removeAll { $0.id == request.id }
      pendingFriendRequest = pendingScannedRequests.first
      setImportStatus(t("galaxyssi.common.rejected", "Rejected"), isError: false)
    } else {
      setImportStatus(t("galaxyssi.friend_request.not_found", "Friend request not found."), isError: true)
    }
  }

  private func approvePendingScannedRequests() {
    let requests = pendingScannedAgentRequests
    let approvedAgentIDs = requests.compactMap { request -> String? in
      guard store.approveFriendRequest(id: request.id) else { return nil }
      Task { await coordinator.recoverPhoneContactSessionIfNeeded(contactId: request.galaxySSIId) }
      return request.galaxySSIId
    }
    let approvedCount = approvedAgentIDs.count
    let approvedIDs = Set(requests.map(\.id))
    pendingScannedRequests.removeAll { approvedIDs.contains($0.id) }
    pendingFriendRequest = pendingScannedRequests.first
    if approvedCount > 0 {
      _ = coordinator.requestCapabilityManifestRefresh(force: true)
      let message = approvedCount == 1
        ? t("galaxyssi.pairing.agent_request_added", "Agent added to Contacts.")
        : String(
            format: t("galaxyssi.pairing.agent_requests_added", "%d Agents added to Contacts."),
            approvedCount
          )
      setImportStatus(message, isError: false)
      onAgentAdded?(approvedAgentIDs)
      notifyImportCompleted()
    } else {
      setImportStatus(t("galaxyssi.friend_request.not_found", "Friend request not found."), isError: true)
    }
  }

  private func clearPendingScanResult() {
    pendingPairing = nil
    pendingFriendRequest = nil
    pendingScannedRequests = []
    pairedDesktopName = ""
    pairedDesktopAgentNames = []
  }

  private func setImportStatus(_ message: String, isError: Bool) {
    contactImportStatus = message
    contactImportIsError = isError
  }

  private func notifyImportCompleted() {
    onImportCompleted?()
    NotificationCenter.default.post(
      name: .galaxySSIContactImportDidComplete,
      object: nil
    )
  }

  private func requestReceivedStatus(_ request: GalaxySSIFriendRequest) -> String {
    let key: String
    let fallback: String
    switch request.type {
    case "agent":
      key = "galaxyssi.pairing.agent_request_received"
      fallback = "Agent request received: %@"
    case "device":
      key = "galaxyssi.pairing.device_request_received"
      fallback = "Device request received: %@"
    case "hermes":
      key = "galaxyssi.pairing.hermes_request_received"
      fallback = "Hermes request received: %@"
    default:
      key = "galaxyssi.pairing.contact_request_received"
      fallback = "Contact request received: %@"
    }
    return String(format: t(key, fallback), request.name)
  }

  private func requestsReceivedStatus(_ requests: [GalaxySSIFriendRequest]) -> String {
    String(
      format: t("galaxyssi.pairing.agent_requests_received", "%d Agent requests received."),
      requests.count
    )
  }

  private func scannedAgentsSubtitle(count: Int) -> String {
    if count == 1 {
      return t("galaxyssi.pairing.scanned_agent_subtitle", "1 Agent is ready to save as a Contact.")
    }
    return String(
      format: t("galaxyssi.pairing.scanned_agents_subtitle", "%d Agents are ready to save as Contacts."),
      count
    )
  }

  private func scannedAgentsApproveTitle(count: Int) -> String {
    count == 1
      ? t("galaxyssi.pairing.add_agent", "Add Agent")
      : t("galaxyssi.pairing.add_all_agents", "Add All")
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }

  private static func desktopAgentCount(_ pairing: PairingQRCode) -> Int {
    if let source = GalaxySSIContactExchange.connectorAgentSource(from: pairing.raw) {
      return source.agents.count
    }
    return fallbackDesktopAgents.count
  }

  private static func desktopAgentNames(from pairing: PairingQRCode) -> [String] {
    if let source = GalaxySSIContactExchange.connectorAgentSource(from: pairing.raw) {
      let names = source.agents.compactMap { agent -> String? in
        let agentId = agent.string("agent_id")
          .ifBlank(agent.string("mobile_contact_id"))
          .ifBlank(agent.string("id"))
        let kind = agent.string("kind").ifBlank(agent.string("agent_kind"))
        guard agentId != "cloud-model", kind != "cloud-model" else { return nil }
        let displayName = agent.string("display_name")
          .ifBlank(agent.string("name"))
          .ifBlank(agentId)
        return displayName.isEmpty ? nil : displayName
      }
      if !names.isEmpty {
        return names
      }
    }
    return fallbackDesktopAgents.map(\.name)
  }

  private static func desktopAgentIDs(from pairing: PairingQRCode) -> [String] {
    if let source = GalaxySSIContactExchange.connectorAgentSource(from: pairing.raw) {
      return source.agents.compactMap { agent -> String? in
        let agentID = agent.string("agent_id")
          .ifBlank(agent.string("mobile_contact_id"))
          .ifBlank(agent.string("id"))
        let kind = agent.string("kind").ifBlank(agent.string("agent_kind"))
        guard !agentID.isEmpty, agentID != "cloud-model", kind != "cloud-model" else {
          return nil
        }
        if agentID.hasPrefix("\(pairing.desktopId):") {
          return agentID
        }
        let suffix = agentID.split(separator: ":").last.map(String.init) ?? agentID
        return "\(pairing.desktopId):\(suffix)"
      }
    }
    guard !pairing.desktopId.isEmpty else { return [] }
    return fallbackDesktopAgents.map { "\(pairing.desktopId):\($0.id)" }
  }

  private static let fallbackDesktopAgents: [(id: String, name: String)] = [
    ("hermes", "Hermes Agent"),
    ("codex", "Codex Agent"),
    ("claude", "Claude Code"),
    ("openclaw", "OpenClaw"),
    ("local-llm", "Local LLM"),
    ("custom-agent", "Custom Agent")
  ]
}

private struct AddContactHeroView: View {
  var title: String
  var subtitle: String

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      GalaxySSILogoView(size: 48, cornerRadius: 8)
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 22, weight: .bold))
          .foregroundColor(.galaxySSITextPrimary)
        Text(subtitle)
          .font(.system(size: 14))
          .foregroundColor(.galaxySSITextSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
  }
}

private struct AddContactActionRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      AddContactRowContent(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        tint: tint,
        badge: badge,
        showsDisclosure: false
      )
    }
    .buttonStyle(.plain)
  }
}

private struct AddContactNavigationRow<Destination: View>: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  let destination: Destination

  init(
    title: String,
    subtitle: String,
    systemImage: String,
    tint: Color,
    badge: String,
    @ViewBuilder destination: () -> Destination
  ) {
    self.title = title
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.tint = tint
    self.badge = badge
    self.destination = destination()
  }

  var body: some View {
    NavigationLink(destination: destination) {
      AddContactRowContent(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        tint: tint,
        badge: badge,
        showsDisclosure: true
      )
    }
    .buttonStyle(.plain)
  }
}

private struct AddContactRowContent: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  var showsDisclosure: Bool

  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(tint.opacity(0.16))
        Image(systemName: systemImage)
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(tint)
      }
      .frame(width: 42, height: 42)
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.82)
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundColor(.galaxySSITextSecondary)
          .lineLimit(2)
      }
      Spacer(minLength: 8)
      Text(badge)
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(tint)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.horizontal, 8)
        .frame(minHeight: 28)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      if showsDisclosure {
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.galaxySSITextSecondary)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct AddContactPasteCard: View {
  var title: String
  var placeholder: String
  var actionTitle: String
  @Binding var text: String
  var onImport: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(.galaxySSITextPrimary)
      ZStack(alignment: .topLeading) {
        if text.isEmpty {
          Text(placeholder)
            .font(.system(size: 13, design: .monospaced))
            .foregroundColor(.galaxySSITextSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
        TextEditor(text: $text)
          .font(.system(size: 13, design: .monospaced))
          .frame(minHeight: 120)
          .padding(2)
          .background(Color.clear)
      }
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke(Color.galaxySSIInputStroke, lineWidth: 1)
      )
      Button(action: onImport) {
        Label(actionTitle, systemImage: "square.and.arrow.down")
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.white)
          .frame(maxWidth: .infinity, minHeight: 44)
          .background(Color.galaxySSIAccent)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      .buttonStyle(.plain)
    }
    .padding(12)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct AddContactPairedAgentsCard: View {
  var desktopName: String
  var agentNames: [String]
  var title: String
  var subtitle: String
  var viewContactsTitle: String
  var t: (String, String) -> String

  private var visibleAgentNames: ArraySlice<String> {
    agentNames.prefix(6)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 12) {
        AddContactIcon(systemImage: "person.3.fill", tint: .galaxySSIAccent)
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 8) {
            Text(title)
              .font(.system(size: 18, weight: .bold))
              .foregroundColor(.galaxySSITextPrimary)
              .lineLimit(1)
              .minimumScaleFactor(0.82)
            Text("\(agentNames.count)")
              .font(.system(size: 12, weight: .semibold))
              .foregroundColor(.galaxySSIAccent)
              .padding(.horizontal, 8)
              .frame(minHeight: 24)
              .background(Color.galaxySSIAccent.opacity(0.12))
              .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          }
          Text(subtitle)
            .font(.system(size: 13))
            .foregroundColor(.galaxySSITextSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
      }
      VStack(spacing: 8) {
        ForEach(Array(visibleAgentNames.enumerated()), id: \.offset) { _, name in
          AddContactValueRow(
            title: name,
            value: desktopName.ifBlank(t("desktop_control_title", "Control Computer")),
            systemImage: "cpu",
            tint: .galaxySSIInsightText
          )
        }
        if agentNames.count > visibleAgentNames.count {
          AddContactValueRow(
            title: String(
              format: t("galaxyssi.pairing.more_added_agents", "%d more Agents"),
              agentNames.count - visibleAgentNames.count
            ),
            value: t("galaxyssi.pairing.view_contacts_subtitle", "Open Contacts to see the full imported Agent list."),
            systemImage: "ellipsis",
            tint: .galaxySSITextSecondary
          )
        }
        NavigationLink(destination: GalaxySSIConversationHubView(initialTab: .contacts)) {
          HStack(alignment: .center, spacing: 10) {
            AddContactIcon(systemImage: "person.2", tint: .galaxySSIAccent, size: 34)
            VStack(alignment: .leading, spacing: 3) {
              Text(viewContactsTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.galaxySSITextPrimary)
              Text(t("galaxyssi.pairing.view_contacts_subtitle", "Open Contacts to see the full imported Agent list."))
                .font(.system(size: 12))
                .foregroundColor(.galaxySSITextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
              .font(.system(size: 13, weight: .semibold))
              .foregroundColor(.galaxySSITextSecondary)
          }
          .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(12)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct AddContactPairingConfirmCard: View {
  var pairing: PairingQRCode
  var phoneFingerprint: String
  var isSubmitting: Bool
  var confirmTitle: String
  var cancelTitle: String
  var onConfirm: () -> Void
  var onCancel: () -> Void
  var t: (String, String) -> String

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        AddContactIcon(systemImage: "checkmark.shield", tint: .galaxySSIAccent)
        VStack(alignment: .leading, spacing: 4) {
          Text(pairing.desktopName)
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(.galaxySSITextPrimary)
          Text(t("galaxyssi.pairing.confirm_subtitle", "Confirm that both fingerprints match before saving the trust relationship"))
            .font(.system(size: 13))
            .foregroundColor(.galaxySSITextSecondary)
            .fixedSize(horizontal: false, vertical: true)
          Text(t("galaxyssi.pairing.status_pending", "Pending Confirmation"))
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.galaxySSIAccent)
            .padding(.horizontal, 8)
            .frame(minHeight: 22)
            .background(Color.galaxySSIAccent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        Spacer(minLength: 0)
      }
      AddContactSectionCaption(t("galaxyssi.pairing.section_device", "Device"))
      AddContactValueRow(
        title: "Desktop ID",
        value: pairing.desktopId,
        systemImage: "desktopcomputer",
        tint: .galaxySSIInsightText,
        copyValue: pairing.desktopId
      )
      AddContactSectionCaption(t("galaxyssi.pairing.section_fingerprints", "Dual Fingerprints"))
      AddContactValueRow(
        title: t("galaxyssi.security.phone_fingerprint", "Phone Fingerprint"),
        value: phoneFingerprint.addContactChunkedFingerprint,
        systemImage: "iphone",
        tint: .galaxySSIAccent,
        copyValue: phoneFingerprint
      )
      AddContactValueRow(
        title: t("galaxyssi.security.desktop_fingerprint", "Computer Fingerprint"),
        value: pairing.desktopFingerprint.addContactChunkedFingerprint,
        systemImage: "desktopcomputer",
        tint: .galaxySSIInsightText,
        copyValue: pairing.desktopFingerprint
      )
      AddContactSectionCaption(t("galaxyssi.pairing.section_after_confirm", "After Confirmation"))
      AddContactValueRow(
        title: t("galaxyssi.pairing.save_trust", "Save Trust"),
        value: t(
          "galaxyssi.pairing.save_trust_subtitle",
          "Hermes, Codex, Claude, local models, and custom Agents will appear as contacts"
        ),
        systemImage: "link",
        tint: .galaxySSIAccent
      )
      AddContactValueRow(
        title: pairing.access.fullDesktopExecutor
          ? t("galaxyssi.pairing.access_full", "Full Desktop Access")
          : t("galaxyssi.pairing.access_restricted", "Restricted Desktop Access"),
        value: pairing.access.fullDesktopExecutor
          ? t("galaxyssi.pairing.access_full_subtitle", "Desktop tools, control, and external files; sensitive actions require approval")
          : t("galaxyssi.pairing.access_restricted_subtitle", "Agent chat and files explicitly attached to the current task only"),
        systemImage: "lock.shield",
        tint: pairing.access.fullDesktopExecutor ? .galaxySSIAccent : .orange
      )
      AddContactValueRow(
        title: t("galaxyssi.pairing.access_scopes", "Allowed Scopes"),
        value: accessScopeSummary,
        systemImage: "checklist",
        tint: pairing.access.fullDesktopExecutor ? .galaxySSIAccent : .orange
      )
      AddContactValueRow(
        title: t("galaxyssi.pairing.authorization_token", "Desktop Control Authorization"),
        value: authorizationStatus,
        systemImage: "key.fill",
        tint: pairing.controlAuthorizationToken.isEmpty ? .orange : .galaxySSIAccent
      )
      AddContactValueRow(
        title: t("galaxyssi.pairing.agent_count", "Desktop Agents"),
        value: String(
          format: t("galaxyssi.pairing.agent_count_value", "%d Agents will be added"),
          Self.desktopAgentCount(pairing)
        ),
        systemImage: "person.3.fill",
        tint: .galaxySSIInsightText
      )
      HStack(spacing: 10) {
        Button(action: onConfirm) {
          Label(confirmTitle, systemImage: "checkmark.shield")
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(isSubmitting ? Color.galaxySSITextSecondary : Color.galaxySSIAccent)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting)
        Button(action: onCancel) {
          Text(cancelTitle)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.galaxySSITextSecondary)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(12)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var accessScopeSummary: String {
    let labels = pairing.access.scopes.sorted { lhs, rhs in
      let leftRank = Self.orderedAccessScopes.firstIndex(of: lhs) ?? Int.max
      let rightRank = Self.orderedAccessScopes.firstIndex(of: rhs) ?? Int.max
      if leftRank == rightRank {
        return lhs < rhs
      }
      return leftRank < rightRank
    }.map(scopeLabel)
    return labels.isEmpty
      ? t("galaxyssi.pairing.access_scopes_none", "No scopes declared")
      : labels.joined(separator: " / ")
  }

  private var authorizationStatus: String {
    pairing.controlAuthorizationToken.isEmpty
      ? t("galaxyssi.pairing.authorization_missing", "Not included in QR; desktop control may require re-pairing")
      : t("galaxyssi.pairing.authorization_included", "Included in the encrypted pairing claim")
  }

  private static let orderedAccessScopes = [
    "agent.chat",
    "agent.attachments.explicit",
    "desktop.task_workspace",
    "desktop.executor.full",
    "desktop.control",
    "desktop.native_tools",
    "desktop.files.external",
  ]

  private static func desktopAgentCount(_ pairing: PairingQRCode) -> Int {
    if let agents = pairing.raw["connector_agents"] as? [[String: Any]], !agents.isEmpty {
      return agents.count
    }
    return 6
  }

  private func scopeLabel(_ scope: String) -> String {
    switch scope {
    case "agent.chat":
      return t("desktop_control_scope_agent_chat", "Agent Chat")
    case "agent.attachments.explicit":
      return t("desktop_control_scope_explicit_attachments", "Explicit Attachments")
    case "desktop.task_workspace":
      return t("desktop_control_scope_task_workspace", "Task Workspace")
    case "desktop.executor.full":
      return t("galaxyssi.pairing.scope_desktop_executor", "View Screen")
    case "desktop.control":
      return t("galaxyssi.pairing.scope_desktop_control", "Click and Control")
    case "desktop.native_tools":
      return t("galaxyssi.pairing.scope_desktop_native_tools", "Type Text and Native Tools")
    case "desktop.files.external":
      return t("galaxyssi.pairing.scope_desktop_external_files", "Select External Files")
    default:
      return scope
    }
  }
}

private struct AddContactBulkAgentImportCard: View {
  var count: Int
  var title: String
  var subtitle: String
  var approveTitle: String
  var cancelTitle: String
  var onApprove: () -> Void
  var onCancel: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        AddContactIcon(systemImage: "person.3.fill", tint: .galaxySSIAccent)
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 8) {
            Text(title)
              .font(.system(size: 18, weight: .bold))
              .foregroundColor(.galaxySSITextPrimary)
              .lineLimit(1)
              .minimumScaleFactor(0.82)
            Text("\(count)")
              .font(.system(size: 12, weight: .semibold))
              .foregroundColor(.galaxySSIAccent)
              .padding(.horizontal, 8)
              .frame(minHeight: 24)
              .background(Color.galaxySSIAccent.opacity(0.12))
              .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          }
          Text(subtitle)
            .font(.system(size: 13))
            .foregroundColor(.galaxySSITextSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
      }
      HStack(spacing: 10) {
        Button(action: onApprove) {
          Label(approveTitle, systemImage: "checkmark.circle.fill")
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color.galaxySSIAccent)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        Button(action: onCancel) {
          Text(cancelTitle)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.galaxySSITextSecondary)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(12)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct AddContactFriendRequestCard: View {
  var request: GalaxySSIFriendRequest
  var approveTitle: String
  var rejectTitle: String
  var waitingTitle: String
  var allowsDecision: Bool
  var onApprove: () -> Void
  var onReject: () -> Void
  var t: (String, String) -> String

  private var kindPresentation: GalaxySSIContactKindPresentation? {
    GalaxySSIContactKindPresentation.forRequest(request, t: t)
  }

  private var deviceIdentifier: String {
    request.desktopId.ifBlank(request.deviceId)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        AddContactIcon(
          systemImage: kindPresentation?.systemImage ?? "person.2.fill",
          tint: kindPresentation?.foreground ?? .galaxySSIAccent
        )
        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 6) {
            Text(request.name)
              .font(.system(size: 18, weight: .bold))
              .foregroundColor(.galaxySSITextPrimary)
              .lineLimit(1)
              .minimumScaleFactor(0.82)
            if let kindPresentation {
              GalaxySSIContactKindBadge(presentation: kindPresentation)
            }
          }
          Text(request.galaxySSIId)
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(.galaxySSITextSecondary)
            .lineLimit(2)
        }
        Spacer(minLength: 0)
      }
      AddContactValueRow(
        title: t("galaxyssi.settings.fingerprint", "Fingerprint"),
        value: request.identityFingerprint.addContactChunkedFingerprint,
        systemImage: "checkmark.shield",
        tint: .galaxySSIAccent,
        copyValue: request.identityFingerprint
      )
      if !request.mqttInboxTopic.isEmpty {
        AddContactValueRow(
          title: t("galaxyssi.contact.messaging", "Messaging"),
          value: request.mqttInboxTopic,
          systemImage: "antenna.radiowaves.left.and.right",
          tint: .galaxySSIInsightText,
          copyValue: request.mqttInboxTopic
        )
      }
      if !request.agentKind.isEmpty {
        AddContactValueRow(
          title: t("galaxyssi.contact.agent_kind", "Agent Kind"),
          value: request.agentKind,
          systemImage: "sparkles",
          tint: kindPresentation?.foreground ?? .galaxySSIAccent
        )
      }
      if !deviceIdentifier.isEmpty {
        AddContactValueRow(
          title: request.type == "device"
            ? t("galaxyssi.contact.device_id", "Device ID")
            : t("galaxyssi.contact.desktop_id", "Desktop ID"),
          value: deviceIdentifier,
          systemImage: request.type == "device" ? "iphone.gen3" : "desktopcomputer",
          tint: .galaxySSIInsightText,
          copyValue: deviceIdentifier
        )
      }
      if allowsDecision {
        HStack(spacing: 10) {
          Button(action: onApprove) {
            Label(approveTitle, systemImage: "checkmark.circle.fill")
              .font(.system(size: 15, weight: .semibold))
              .foregroundColor(.white)
              .frame(maxWidth: .infinity, minHeight: 44)
              .background(Color.galaxySSIAccent)
              .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          }
          .buttonStyle(.plain)
          Button(action: onReject) {
            Label(rejectTitle, systemImage: "xmark.circle")
              .font(.system(size: 15, weight: .semibold))
              .foregroundColor(.red)
              .frame(maxWidth: .infinity, minHeight: 44)
          }
          .buttonStyle(.plain)
        }
      } else {
        Label(waitingTitle, systemImage: "clock")
          .font(.system(size: 14, weight: .semibold))
          .foregroundColor(.orange)
          .frame(maxWidth: .infinity, minHeight: 44)
          .background(Color.orange.opacity(0.1))
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
    }
    .padding(12)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct AddContactFriendRequestRow: View {
  var request: GalaxySSIFriendRequest
  var approveTitle: String
  var rejectTitle: String
  var waitingTitle: String
  var allowsDecision: Bool
  var onApprove: () -> Void
  var onReject: () -> Void
  var t: (String, String) -> String

  private var kindPresentation: GalaxySSIContactKindPresentation? {
    GalaxySSIContactKindPresentation.forRequest(request, t: t)
  }

  var body: some View {
    HStack(spacing: 12) {
      AddContactIcon(
        systemImage: kindPresentation?.systemImage ?? "person.2.fill",
        tint: kindPresentation?.foreground ?? .galaxySSIAccent,
        size: 38
      )
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          Text(request.name)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.galaxySSITextPrimary)
            .lineLimit(1)
          if let kindPresentation {
            GalaxySSIContactKindBadge(presentation: kindPresentation)
          }
        }
        Text(request.galaxySSIId)
          .font(.system(size: 12, design: .monospaced))
          .foregroundColor(.galaxySSITextSecondary)
          .lineLimit(1)
      }
      Spacer(minLength: 8)
      if allowsDecision {
        Button(action: onApprove) {
          Text(approveTitle)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.galaxySSIAccent)
            .padding(.horizontal, 8)
            .frame(minHeight: 30)
        }
        .buttonStyle(.plain)
        Button(action: onReject) {
          Text(rejectTitle)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.red)
            .padding(.horizontal, 8)
            .frame(minHeight: 30)
        }
        .buttonStyle(.plain)
      } else {
        Label(waitingTitle, systemImage: "clock")
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(.orange)
          .padding(.horizontal, 8)
          .frame(minHeight: 30)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
  }
}

private struct AddContactValueRow: View {
  var title: String
  var value: String
  var systemImage: String
  var tint: Color
  var copyValue: String?

  init(
    title: String,
    value: String,
    systemImage: String,
    tint: Color,
    copyValue: String? = nil
  ) {
    self.title = title
    self.value = value
    self.systemImage = systemImage
    self.tint = tint
    self.copyValue = copyValue
  }

  var body: some View {
    Button {
      if let copyValue, !copyValue.isEmpty {
        UIPasteboard.general.string = copyValue
      }
    } label: {
      HStack(alignment: .top, spacing: 10) {
        AddContactIcon(systemImage: systemImage, tint: tint, size: 34)
        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.galaxySSITextPrimary)
          Text(value.ifBlank("-"))
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(.galaxySSITextSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
        if copyValue != nil {
          Image(systemName: "doc.on.doc")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.galaxySSITextSecondary)
        }
      }
      .padding(.vertical, 4)
    }
    .buttonStyle(.plain)
  }
}

private struct AddContactSectionCaption: View {
  var title: String

  init(_ title: String) {
    self.title = title
  }

  var body: some View {
    Text(title)
      .font(.system(size: 12, weight: .semibold))
      .foregroundColor(.galaxySSITextSecondary)
      .padding(.top, 2)
  }
}

private struct AddContactIcon: View {
  var systemImage: String
  var tint: Color
  var size: CGFloat = 42

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(tint.opacity(0.16))
      Image(systemName: systemImage)
        .font(.system(size: size > 38 ? 18 : 15, weight: .semibold))
        .foregroundColor(tint)
    }
    .frame(width: size, height: size)
  }
}

private extension String {
  var addContactChunkedFingerprint: String {
    String(filter { $0.isLetter || $0.isNumber }.prefix(64))
      .addContactChunked(into: 32)
      .joined(separator: "\n")
  }

  func addContactChunked(into size: Int) -> [String] {
    var chunks: [String] = []
    var index = startIndex
    while index < endIndex {
      let next = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
      chunks.append(String(self[index..<next]))
      index = next
    }
    return chunks
  }
}
