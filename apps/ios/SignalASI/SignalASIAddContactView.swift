import SwiftUI
import UIKit

struct AddContactView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var myQRCodePresented = false
  @State private var contactScannerPresented = false
  @State private var manualPastePresented = false
  @State private var contactImportStatus = ""
  @State private var contactImportIsError = false
  @State private var scannedQRCodeText = ""
  @State private var pastedQRCodeText = ""
  @State private var pendingPairing: PairingQRCode?
  @State private var pendingFriendRequest: SignalASIFriendRequest?
  @State private var pairingInFlight = false
  @State private var scannerAutoOpened = false

  private let autoOpenScanner: Bool

  init(autoOpenScanner: Bool = false) {
    self.autoOpenScanner = autoOpenScanner
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("signalasi.add_contact.title", "Add"),
        leading: {
          SignalASIBackButton()
        },
        trailing: {
          Button {
            myQRCodePresented = true
          } label: {
            Image(systemName: "qrcode")
              .font(.system(size: 19, weight: .semibold))
              .foregroundColor(.signalASITextPrimary)
          }
          .buttonStyle(.plain)
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          AddContactHeroView(
            title: t("signalasi.add_contact.hero_title", "Add Contact"),
            subtitle: t(
              "signalasi.add_contact.hero_subtitle",
              "Scan trusted contacts, or add multiple cloud models directly on the phone."
            )
          )
          sectionTitle(t("signalasi.add_contact.section_methods", "Methods"))
          VStack(spacing: 8) {
            AddContactActionRow(
              title: t("signalasi.add_contact.scan_title", "Scan to Add Contact"),
              subtitle: t("signalasi.add_contact.scan_subtitle", "Add Hermes, computers, friends, or devices"),
              systemImage: "qrcode.viewfinder",
              tint: .signalASIAccent,
              badge: t("signalasi.pairing.action_scan", "Scan")
            ) {
              contactScannerPresented = true
            }
            AddContactNavigationRow(
              title: t("signalasi.add_contact.cloud_title", "Add Cloud Model"),
              subtitle: t(
                "signalasi.add_contact.cloud_subtitle",
                "Provider, model, and API key are configured directly on the phone."
              ),
              systemImage: "cloud.fill",
              tint: .signalASIInsightText,
              badge: t("signalasi.add_contact.title", "Add")
            ) {
              CloudModelProviderSelectionView()
            }
            AddContactActionRow(
              title: t("signalasi.add_contact.my_qr_title", "My QR Code"),
              subtitle: t("signalasi.add_contact.my_qr_subtitle", "Show this device identity"),
              systemImage: "qrcode",
              tint: .signalASITextPrimary,
              badge: t("signalasi.common.show", "Show")
            ) {
              myQRCodePresented = true
            }
            AddContactActionRow(
              title: t("signalasi.add_contact.paste_title", "Paste QR Payload"),
              subtitle: t("signalasi.add_contact.paste_subtitle", "Use a copied SignalASI QR code when camera scan is unavailable"),
              systemImage: "doc.on.clipboard",
              tint: .orange,
              badge: t("signalasi.common.import", "Import")
            ) {
              manualPastePresented.toggle()
            }
          }
          if manualPastePresented {
            AddContactPasteCard(
              title: t("signalasi.add_contact.paste_title", "Paste QR Payload"),
              placeholder: t("signalasi.add_contact.paste_placeholder", "Paste SignalASI QR JSON here"),
              actionTitle: t("signalasi.common.import", "Import"),
              text: $pastedQRCodeText
            ) {
              importScannedQR(pastedQRCodeText)
            }
          }
          if let pendingPairing {
            sectionTitle(t("signalasi.pairing.confirm_title", "Confirm Pairing"))
            AddContactPairingConfirmCard(
              pairing: pendingPairing,
              phoneFingerprint: store.profile.identityFingerprint,
              isSubmitting: pairingInFlight,
              confirmTitle: t("signalasi.pairing.confirm_title", "Confirm Pairing"),
              cancelTitle: t("signalasi.common.cancel", "Cancel"),
              onConfirm: {
                Task { await confirmDesktopPairing() }
              },
              onCancel: clearPendingScanResult,
              t: t
            )
          }
          if let pendingFriendRequest {
            sectionTitle(t("signalasi.friend_request.pending", "Pending Verification"))
            AddContactFriendRequestCard(
              request: pendingFriendRequest,
              approveTitle: t("signalasi.friend_request.approve", "Approve"),
              rejectTitle: t("signalasi.friend_request.reject", "Reject"),
              onApprove: {
                approveFriendRequest(pendingFriendRequest)
              },
              onReject: {
                rejectFriendRequest(pendingFriendRequest)
              },
              t: t
            )
          }
          if !store.pendingFriendRequests.isEmpty {
            sectionTitle(t("signalasi.new_friends", "New Friends"))
            VStack(spacing: 0) {
              ForEach(store.pendingFriendRequests) { request in
                AddContactFriendRequestRow(
                  request: request,
                  approveTitle: t("signalasi.friend_request.approve", "Approve"),
                  rejectTitle: t("signalasi.friend_request.reject", "Reject"),
                  onApprove: {
                    approveFriendRequest(request)
                  },
                  onReject: {
                    rejectFriendRequest(request)
                  }
                )
                if request.id != store.pendingFriendRequests.last?.id {
                  Divider()
                    .background(Color.signalASISeparator)
                    .padding(.leading, 58)
                }
              }
            }
            .background(Color.signalASISurface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          }
          if !contactImportStatus.isEmpty {
            Text(contactImportStatus)
              .font(.system(size: 13))
              .foregroundColor(contactImportIsError ? .red : .signalASITextSecondary)
              .padding(.horizontal, 4)
              .padding(.top, 4)
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .sheet(isPresented: $myQRCodePresented) {
      MyContactQRCodeView()
    }
    .sheet(isPresented: $contactScannerPresented) {
      QRCodeScannerView(
        onCode: { value in
          contactScannerPresented = false
          importScannedQR(value)
        },
        onError: { message in
          contactScannerPresented = false
          setImportStatus(message, isError: true)
        }
      )
    }
    .onAppear {
      guard autoOpenScanner, !scannerAutoOpened else { return }
      scannerAutoOpened = true
      contactScannerPresented = true
    }
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.signalASITextSecondary)
      .padding(.horizontal, 4)
      .padding(.top, 2)
  }

  private func importScannedQR(_ value: String) {
    let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else {
      setImportStatus(t("signalasi.pairing.invalid_qr", "Invalid QR code"), isError: true)
      return
    }
    scannedQRCodeText = cleaned
    pastedQRCodeText = cleaned
    do {
      switch try SignalASIContactExchange.classifyQRCode(cleaned) {
      case .desktopPairing(let pairing):
        pendingPairing = pairing
        pendingFriendRequest = nil
        setImportStatus(
          t("signalasi.pairing.ready_to_confirm", "Review fingerprints, then save trust."),
          isError: false
        )
      case .contact(let request):
        let stored = store.addFriendRequest(request)
        pendingPairing = nil
        pendingFriendRequest = stored
        setImportStatus(
          String(
            format: t("signalasi.pairing.contact_request_received", "Contact request received: %@"),
            stored.name
          ),
          isError: false
        )
      }
    } catch {
      clearPendingScanResult()
      setImportStatus(
        String(format: t("signalasi.pairing.scan_failed", "Scan failed: %@"), error.localizedDescription),
        isError: true
      )
    }
  }

  private func confirmDesktopPairing() async {
    guard let pairing = pendingPairing else { return }
    pairingInFlight = true
    setImportStatus(
      String(format: t("signalasi.pairing.desktop_claim_sending", "Adding %@..."), pairing.desktopName),
      isError: false
    )
    do {
      try await coordinator.pair(using: scannedQRCodeText)
      pendingPairing = nil
      setImportStatus(
        String(
          format: t("signalasi.pairing.desktop_claim_sent", "%@ added. Agents are ready in Contacts."),
          pairing.desktopName
        ),
        isError: false
      )
    } catch {
      setImportStatus(error.localizedDescription, isError: true)
    }
    pairingInFlight = false
  }

  private func approveFriendRequest(_ request: SignalASIFriendRequest) {
    if store.approveFriendRequest(id: request.id) {
      if pendingFriendRequest?.id == request.id {
        pendingFriendRequest = nil
      }
      setImportStatus(t("signalasi.friend_request.added_to_contacts", "Added to Contacts"), isError: false)
    } else {
      setImportStatus(t("signalasi.friend_request.not_found", "Friend request not found."), isError: true)
    }
  }

  private func rejectFriendRequest(_ request: SignalASIFriendRequest) {
    if store.rejectFriendRequest(id: request.id) {
      if pendingFriendRequest?.id == request.id {
        pendingFriendRequest = nil
      }
      setImportStatus(t("signalasi.common.rejected", "Rejected"), isError: false)
    } else {
      setImportStatus(t("signalasi.friend_request.not_found", "Friend request not found."), isError: true)
    }
  }

  private func clearPendingScanResult() {
    pendingPairing = nil
    pendingFriendRequest = nil
  }

  private func setImportStatus(_ message: String, isError: Bool) {
    contactImportStatus = message
    contactImportIsError = isError
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct AddContactHeroView: View {
  var title: String
  var subtitle: String

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      SignalASILogoView(size: 48, cornerRadius: 8)
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 22, weight: .bold))
          .foregroundColor(.signalASITextPrimary)
        Text(subtitle)
          .font(.system(size: 14))
          .foregroundColor(.signalASITextSecondary)
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
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.82)
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundColor(.signalASITextSecondary)
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
          .foregroundColor(.signalASITextSecondary)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .background(Color.signalASISurface)
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
        .foregroundColor(.signalASITextPrimary)
      ZStack(alignment: .topLeading) {
        if text.isEmpty {
          Text(placeholder)
            .font(.system(size: 13, design: .monospaced))
            .foregroundColor(.signalASITextSecondary)
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
          .stroke(Color.signalASIInputStroke, lineWidth: 1)
      )
      Button(action: onImport) {
        Label(actionTitle, systemImage: "square.and.arrow.down")
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.white)
          .frame(maxWidth: .infinity, minHeight: 44)
          .background(Color.signalASIAccent)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      .buttonStyle(.plain)
    }
    .padding(12)
    .background(Color.signalASISurface)
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
        AddContactIcon(systemImage: "checkmark.shield", tint: .signalASIAccent)
        VStack(alignment: .leading, spacing: 4) {
          Text(pairing.desktopName)
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(.signalASITextPrimary)
          Text(t("signalasi.pairing.confirm_subtitle", "Confirm that both fingerprints match before saving the trust relationship"))
            .font(.system(size: 13))
            .foregroundColor(.signalASITextSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
      }
      AddContactSectionCaption(t("signalasi.pairing.section_device", "Device"))
      AddContactValueRow(
        title: "Desktop ID",
        value: pairing.desktopId,
        systemImage: "desktopcomputer",
        tint: .signalASIInsightText,
        copyValue: pairing.desktopId
      )
      AddContactSectionCaption(t("signalasi.pairing.section_fingerprints", "Dual Fingerprints"))
      AddContactValueRow(
        title: t("signalasi.security.phone_fingerprint", "Phone Fingerprint"),
        value: phoneFingerprint.addContactChunkedFingerprint,
        systemImage: "iphone",
        tint: .signalASIAccent,
        copyValue: phoneFingerprint
      )
      AddContactValueRow(
        title: t("signalasi.security.desktop_fingerprint", "Computer Fingerprint"),
        value: pairing.desktopFingerprint.addContactChunkedFingerprint,
        systemImage: "desktopcomputer",
        tint: .signalASIInsightText,
        copyValue: pairing.desktopFingerprint
      )
      AddContactSectionCaption(t("signalasi.pairing.section_after_confirm", "After Confirmation"))
      AddContactValueRow(
        title: t("signalasi.pairing.save_trust", "Save Trust"),
        value: t(
          "signalasi.pairing.save_trust_subtitle",
          "Hermes, Codex, Claude, local models, and custom Agents will appear as contacts"
        ),
        systemImage: "link",
        tint: .signalASIAccent
      )
      AddContactValueRow(
        title: pairing.access.fullDesktopExecutor
          ? t("signalasi.pairing.access_full", "Desktop Executor")
          : t("signalasi.pairing.access_restricted", "Restricted Desktop Access"),
        value: pairing.access.fullDesktopExecutor
          ? t("signalasi.pairing.access_full_subtitle", "Desktop tools, control, and external files; sensitive actions require approval")
          : t("signalasi.pairing.access_restricted_subtitle", "Agent chat and files explicitly attached to the current task only"),
        systemImage: "lock.shield",
        tint: pairing.access.fullDesktopExecutor ? .signalASIAccent : .orange
      )
      HStack(spacing: 10) {
        Button(action: onConfirm) {
          Label(confirmTitle, systemImage: "checkmark.shield")
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(isSubmitting ? Color.signalASITextSecondary : Color.signalASIAccent)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting)
        Button(action: onCancel) {
          Text(cancelTitle)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.signalASITextSecondary)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(12)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct AddContactFriendRequestCard: View {
  var request: SignalASIFriendRequest
  var approveTitle: String
  var rejectTitle: String
  var onApprove: () -> Void
  var onReject: () -> Void
  var t: (String, String) -> String

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        AddContactIcon(systemImage: "person.2.fill", tint: .signalASIAccent)
        VStack(alignment: .leading, spacing: 3) {
          Text(request.name)
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(.signalASITextPrimary)
          Text(request.signalASIId)
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(.signalASITextSecondary)
            .lineLimit(2)
        }
        Spacer(minLength: 0)
      }
      AddContactValueRow(
        title: t("signalasi.settings.fingerprint", "Fingerprint"),
        value: request.identityFingerprint.addContactChunkedFingerprint,
        systemImage: "checkmark.shield",
        tint: .signalASIAccent,
        copyValue: request.identityFingerprint
      )
      if !request.mqttInboxTopic.isEmpty {
        AddContactValueRow(
          title: t("signalasi.contact.messaging", "Messaging"),
          value: request.mqttInboxTopic,
          systemImage: "antenna.radiowaves.left.and.right",
          tint: .signalASIInsightText,
          copyValue: request.mqttInboxTopic
        )
      }
      HStack(spacing: 10) {
        Button(action: onApprove) {
          Label(approveTitle, systemImage: "checkmark.circle.fill")
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color.signalASIAccent)
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
    }
    .padding(12)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct AddContactFriendRequestRow: View {
  var request: SignalASIFriendRequest
  var approveTitle: String
  var rejectTitle: String
  var onApprove: () -> Void
  var onReject: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      AddContactIcon(systemImage: "person.2.fill", tint: .signalASIAccent, size: 38)
      VStack(alignment: .leading, spacing: 3) {
        Text(request.name)
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(1)
        Text(request.signalASIId)
          .font(.system(size: 12, design: .monospaced))
          .foregroundColor(.signalASITextSecondary)
          .lineLimit(1)
      }
      Spacer(minLength: 8)
      Button(action: onApprove) {
        Text(approveTitle)
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(.signalASIAccent)
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
            .foregroundColor(.signalASITextPrimary)
          Text(value.ifBlank("-"))
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(.signalASITextSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
        if copyValue != nil {
          Image(systemName: "doc.on.doc")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.signalASITextSecondary)
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
      .foregroundColor(.signalASITextSecondary)
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
