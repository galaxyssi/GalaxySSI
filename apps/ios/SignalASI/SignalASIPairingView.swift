import SwiftUI
import UIKit

struct PairingView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var qrText = ""
  @State private var errorText = ""
  @State private var pairingNoticeIsError = false
  @State private var scannerPresented = false
  @State private var pendingPairing: PairingQRCode?

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("signalasi.pairing.title", "Pairing"),
        leading: {
          SignalASIBackButton()
        },
        trailing: {
          Button {
            scannerPresented = true
          } label: {
            Image(systemName: "qrcode.viewfinder")
              .font(.system(size: 19, weight: .semibold))
              .foregroundColor(.signalASITextPrimary)
              .frame(width: 40, height: 40)
          }
          .buttonStyle(.plain)
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          SignalASISecurityHeroView(
            title: t("signalasi.pairing.title", "Pairing"),
            subtitle: t(
              "signalasi.pairing.confirm_subtitle",
              "Confirm that both fingerprints match before saving the trust relationship"
            ),
            systemImage: "checkmark.shield",
            tint: .signalASIAccent,
            badge: String(
              format: t("signalasi.pairing.desktop_count", "%d Desktop"),
              store.serverLinks.count
            )
          )
          desktopSection
          qrSection
          if let pendingPairing {
            pairingConfirmSection(pendingPairing)
          }
          statusSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .sheet(isPresented: $scannerPresented) {
      QRCodeScannerView(
        onCode: { value in
          qrText = value
          scannerPresented = false
          handleScannedQR(value)
        },
        onError: { message in
          scannerPresented = false
          errorText = message
          pairingNoticeIsError = true
        }
      )
    }
  }

  private var desktopSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("signalasi.pairing.section_desktop", "Desktop"))
      if store.serverLinks.isEmpty {
        SignalASISecurityStatusRow(
          title: t("signalasi.pairing.no_desktops", "No paired desktops"),
          subtitle: t("signalasi.pairing.no_desktops_subtitle", "Scan a SignalASI Desktop QR code to create a trusted link."),
          systemImage: "desktopcomputer",
          tint: .signalASITextSecondary,
          badge: t("signalasi.status.needs_setup", "Needs Setup")
        )
      } else {
        ForEach(store.serverLinks) { link in
          SignalASISecurityStatusRow(
            title: link.desktopName.ifBlank(link.desktopId),
            subtitle: SignalASISecurityFormatter.fingerprint(
              link.desktopFingerprint,
              unknown: t("Unavailable", "Unavailable")
            ),
            systemImage: "desktopcomputer",
            tint: link.paired ? .signalASIAccent : .orange,
            badge: link.paired
              ? t("signalasi.pairing.status_paired", "Paired")
              : t("signalasi.pairing.status_pending", "Pending"),
            monospacedSubtitle: true
          )
          SignalASISecurityActionRow(
            title: t("signalasi.pairing.remove_desktop", "Remove Desktop Link"),
            subtitle: link.desktopId,
            systemImage: "trash",
            tint: .red,
            badge: t("Delete", "Delete"),
            monospacedSubtitle: true
          ) {
            store.removeServer(desktopId: link.desktopId)
            errorText = String(
              format: t("signalasi.pairing.desktop_removed", "%@ removed."),
              link.desktopName.ifBlank(link.desktopId)
            )
            pairingNoticeIsError = false
          }
        }
      }
    }
  }

  private var qrSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("signalasi.pairing.section_qr", "QR"))
      SignalASISecurityActionRow(
        title: t("signalasi.pairing.action_scan", "Scan"),
        subtitle: t("signalasi.pairing.scan_subtitle", "Scan a SignalASI Desktop or contact QR code."),
        systemImage: "qrcode.viewfinder",
        tint: .signalASIAccent,
        badge: t("signalasi.pairing.action_scan", "Scan")
      ) {
        scannerPresented = true
      }
      VStack(alignment: .leading, spacing: 8) {
        Text(t("signalasi.pairing.paste_qr_payload", "Paste QR Payload"))
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.signalASITextSecondary)
        TextEditor(text: $qrText)
          .font(.system(size: 12, design: .monospaced))
          .foregroundColor(.signalASITextPrimary)
          .frame(minHeight: 116)
          .padding(8)
          .background(Color.signalASISearchBackground)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        Button {
          handleEnteredQR()
        } label: {
          Label(t("signalasi.pairing.action_pair", "Pair"), systemImage: "checkmark.shield")
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(canSubmitQR ? Color.signalASIAccent : Color.signalASITextSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSubmitQR)
      }
      .padding(12)
      .background(Color.signalASISurface)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
  }

  private func pairingConfirmSection(_ pairing: PairingQRCode) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("signalasi.pairing.confirm_title", "Confirm Pairing"))
      SignalASISecurityHeroView(
        title: pairing.desktopName,
        subtitle: t(
          "signalasi.pairing.confirm_subtitle",
          "Confirm that both fingerprints match before saving the trust relationship"
        ),
        systemImage: "checkmark.shield",
        tint: .signalASIAccent,
        badge: t("signalasi.pairing.status_pending", "Pending Confirmation")
      )
      SignalASISecuritySectionTitle(title: t("signalasi.pairing.section_device", "Device"))
      copyRow(
        title: "Desktop ID",
        value: pairing.desktopId,
        systemImage: "desktopcomputer",
        tint: .signalASIInsightText,
        message: t("signalasi.security_center.copied_desktop_id", "Desktop ID copied")
      )
      SignalASISecuritySectionTitle(title: t("signalasi.pairing.section_fingerprints", "Dual Fingerprints"))
      copyRow(
        title: t("signalasi.security.phone_fingerprint", "Phone Fingerprint"),
        value: store.profile.identityFingerprint,
        displayValue: SignalASISecurityFormatter.fingerprint(
          store.profile.identityFingerprint,
          unknown: t("Unavailable", "Unavailable")
        ),
        systemImage: "iphone",
        tint: .signalASIAccent,
        message: t("signalasi.security_center.copied_phone_fingerprint", "Phone fingerprint copied")
      )
      copyRow(
        title: t("signalasi.security.desktop_fingerprint", "Computer Fingerprint"),
        value: pairing.desktopFingerprint,
        displayValue: SignalASISecurityFormatter.fingerprint(
          pairing.desktopFingerprint,
          unknown: t("Unavailable", "Unavailable")
        ),
        systemImage: "desktopcomputer",
        tint: .signalASIInsightText,
        message: t("signalasi.security_center.copied_desktop_fingerprint", "Desktop fingerprint copied")
      )
      SignalASISecuritySectionTitle(title: t("signalasi.pairing.section_after_confirm", "After Confirmation"))
      SignalASISecurityStatusRow(
        title: t("signalasi.pairing.save_trust", "Save Trust"),
        subtitle: t(
          "signalasi.pairing.save_trust_subtitle",
          "Hermes, Codex, Claude, local models, and custom Agents will appear as contacts"
        ),
        systemImage: "link",
        tint: .signalASIAccent,
        badge: t("status_enabled", "Enabled")
      )
      SignalASISecurityStatusRow(
        title: pairing.access.fullDesktopExecutor
          ? t("signalasi.pairing.access_full", "Desktop Executor")
          : t("signalasi.pairing.access_restricted", "Restricted Desktop Access"),
        subtitle: pairing.access.fullDesktopExecutor
          ? t("signalasi.pairing.access_full_subtitle", "Desktop tools, control, and external files; sensitive actions require approval")
          : t("signalasi.pairing.access_restricted_subtitle", "Agent chat and files explicitly attached to the current task only"),
        systemImage: "lock.shield",
        tint: pairing.access.fullDesktopExecutor ? .signalASIAccent : .orange,
        badge: t("status_enabled", "Enabled")
      )
      SignalASISecurityPrimaryButton(
        title: t("signalasi.pairing.confirm_title", "Confirm Pairing"),
        systemImage: "checkmark.shield",
        tint: .signalASIAccent
      ) {
        Task { await submitPairing(qrText) }
      }
      Button {
        pendingPairing = nil
        errorText = ""
        pairingNoticeIsError = false
      } label: {
        Text(t("common_cancel", "Cancel"))
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(.signalASITextSecondary)
          .frame(maxWidth: .infinity, minHeight: 44)
      }
      .buttonStyle(.plain)
    }
  }

  private func copyRow(
    title: String,
    value: String,
    displayValue: String? = nil,
    systemImage: String,
    tint: Color,
    message: String
  ) -> some View {
    SignalASISecurityActionRow(
      title: title,
      subtitle: displayValue ?? value,
      systemImage: systemImage,
      tint: tint,
      badge: t("common_copy", "Copy"),
      monospacedSubtitle: true
    ) {
      copy(value, message: message)
    }
  }

  @ViewBuilder
  private var statusSection: some View {
    let message = errorText.ifBlank(coordinator.pairingStatus)
    if !message.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        SignalASISecuritySectionTitle(title: t("signalasi.pairing.section_status", "Status"))
        SignalASISecurityStatusRow(
          title: t("common_status", "Status"),
          subtitle: message,
          systemImage: pairingNoticeIsError ? "xmark.circle" : "checkmark.circle",
          tint: pairingNoticeIsError ? .red : .signalASIAccent,
          badge: pairingNoticeIsError
            ? t("signalasi.status.needs_setup", "Needs Setup")
            : t("signalasi.status.ready", "Ready")
        )
      }
    }
  }

  private var canSubmitQR: Bool {
    !qrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func handleEnteredQR() {
    let value = qrText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return }
    handleScannedQR(value)
  }

  private func handleScannedQR(_ value: String) {
    do {
      errorText = ""
      pairingNoticeIsError = false
      switch try SignalASIContactExchange.classifyQRCode(value) {
      case .desktopPairing(let pairing):
        pendingPairing = pairing
        errorText = t("signalasi.pairing.ready_to_confirm", "Review fingerprints, then save trust.")
      case .contact(let request):
        let stored = store.addFriendRequest(request)
        pendingPairing = nil
        errorText = String(
          format: t("signalasi.friend_request.added", "Friend request added for %@."),
          stored.name
        )
      }
    } catch {
      pendingPairing = nil
      errorText = error.localizedDescription
      pairingNoticeIsError = true
    }
  }

  private func submitPairing(_ contents: String? = nil) async {
    do {
      let value = (contents ?? qrText).trimmingCharacters(in: .whitespacesAndNewlines)
      guard !value.isEmpty else { return }
      errorText = ""
      pairingNoticeIsError = false
      try await coordinator.pair(using: value)
      errorText = String(
        format: t("signalasi.pairing.desktop_added", "%@ added"),
        pendingPairing?.desktopName ?? t("signalasi.pairing.title", "Pairing")
      )
      pairingNoticeIsError = false
      pendingPairing = nil
    } catch {
      errorText = error.localizedDescription
      pairingNoticeIsError = true
    }
  }

  private func copy(_ value: String, message: String) {
    UIPasteboard.general.string = value
    errorText = message
    pairingNoticeIsError = false
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
