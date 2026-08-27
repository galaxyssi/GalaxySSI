import SwiftUI
import UIKit

struct MyContactQRCodeView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var store: SignalASIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var copiedMessage = ""
  @State private var qrText = ""
  @State private var qrGenerationError = ""
  @State private var sharePresented = false

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("signalasi.contact.my_qr_title", "My QR Code"),
        leading: {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 17, weight: .semibold))
              .foregroundColor(.signalASITextPrimary)
              .frame(width: 40, height: 40)
          }
          .buttonStyle(.plain)
        },
        trailing: {
          Button {
            sharePresented = true
          } label: {
            Image(systemName: "square.and.arrow.up")
              .font(.system(size: 17, weight: .semibold))
              .foregroundColor(.signalASIAccent)
              .frame(width: 40, height: 40)
          }
          .buttonStyle(.plain)
          .disabled(!hasShareableQRCode)
          .accessibilityLabel(Text(t("signalasi.contact.share_qr", "Share QR Code")))
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          MyContactQRHeroView(
            name: store.profile.name,
            signalASIId: contactCardValue("signalasi_id", fallback: store.profile.signalASIId),
            fingerprint: contactCardValue("identity_fingerprint", fallback: store.profile.identityFingerprint),
            badge: t("signalasi.contact.my_qr_title", "My QR Code")
          )
          qrCard
          identitySection
          payloadSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .onAppear(perform: refreshQRText)
    .sheet(isPresented: $sharePresented) {
      SignalASIContactQRShareSheet(items: shareItems)
    }
  }

  private var qrCard: some View {
    VStack(alignment: .center, spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(Color.white)
        if let image = SignalASIQRCodeImageRenderer.image(from: qrText) {
          Image(uiImage: image)
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .padding(10)
        } else {
          Image(systemName: "qrcode")
            .font(.system(size: 72, weight: .regular))
            .foregroundColor(.black.opacity(0.35))
        }
      }
      .frame(width: 260, height: 260)
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke(Color.black.opacity(0.08), lineWidth: 1)
      )
      Text(qrGenerationError.ifBlank(
        t("contact_scan_confirm_identity", "Both sides must confirm identity after scanning")
      ))
        .font(.system(size: 13))
        .foregroundColor(qrGenerationError.isEmpty ? .signalASITextSecondary : .red)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity)
    .padding(16)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var identitySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("signalasi.contact.section_identity", "Identity"))
      SignalASISecurityActionRow(
        title: t("settings_signalasi_id", "SignalASI ID"),
        subtitle: contactCardValue("signalasi_id", fallback: store.profile.signalASIId),
        systemImage: "link",
        tint: .blue,
        badge: t("common_copy", "Copy"),
        monospacedSubtitle: true
      ) {
        copy(
          contactCardValue("signalasi_id", fallback: store.profile.signalASIId),
          message: t("signalasi.contact.my_qr_id_copied", "SignalASI ID copied")
        )
      }
      SignalASISecurityActionRow(
        title: t("contact_my_fingerprint", "My Fingerprint"),
        subtitle: SignalASISecurityFormatter.fingerprint(
          contactCardValue("identity_fingerprint", fallback: store.profile.identityFingerprint),
          unknown: t("Unavailable", "Unavailable")
        ),
        systemImage: "checkmark.shield",
        tint: .signalASIAccent,
        badge: t("common_copy", "Copy"),
        monospacedSubtitle: true
      ) {
        copy(
          contactCardValue("identity_fingerprint", fallback: store.profile.identityFingerprint),
          message: t("signalasi.contact.my_qr_fingerprint_copied", "Fingerprint copied")
        )
      }
      copiedStatusRow
    }
  }

  private var payloadSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("signalasi.contact.payload", "Payload"))
      if hasShareableQRCode {
        SignalASISecurityActionRow(
          title: t("signalasi.contact.copy_payload", "Copy Payload"),
          subtitle: qrText,
          systemImage: "doc.on.doc",
          tint: .purple,
          badge: t("common_copy", "Copy"),
          monospacedSubtitle: true
        ) {
          copy(qrText, message: t("signalasi.contact.my_qr_payload_copied", "QR payload copied"))
        }
      } else {
        SignalASISecurityStatusRow(
          title: t("signalasi.contact.qr_unavailable", "QR Code Unavailable"),
          subtitle: qrGenerationError.ifBlank(t(
            "signalasi.contact.qr_unavailable_subtitle",
            "A signed identity card is required before this QR code can be shared."
          )),
          systemImage: "exclamationmark.triangle.fill",
          tint: .orange,
          badge: t("signalasi.status.unavailable", "Unavailable")
        )
      }
    }
  }

  @ViewBuilder
  private var copiedStatusRow: some View {
    if !copiedMessage.isEmpty {
      SignalASISecurityStatusRow(
        title: t("common_status", "Status"),
        subtitle: copiedMessage,
        systemImage: "checkmark.circle",
        tint: .signalASIAccent,
        badge: t("signalasi.common.copied", "Copied")
      )
    }
  }

  private func refreshQRText() {
    guard qrText.isEmpty else { return }
    do {
      qrText = try coordinator.myContactQRText()
      qrGenerationError = ""
    } catch {
      qrText = ""
      qrGenerationError = t(
        "signalasi.contact.qr_unavailable_subtitle",
        "A signed identity card is required before this QR code can be shared."
      )
    }
  }

  private var hasShareableQRCode: Bool {
    !qrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && qrText != "{}"
  }

  private var shareItems: [Any] {
    var items: [Any] = [qrText]
    if let image = SignalASIQRCodeImageRenderer.image(from: qrText) {
      items.insert(image, at: 0)
    }
    return items
  }

  private func copy(_ value: String, message: String) {
    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    UIPasteboard.general.string = value
    copiedMessage = message
  }

  private func contactCardValue(_ key: String, fallback: String) -> String {
    guard let data = qrText.data(using: .utf8),
          let rawObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return fallback
    }
    let object = SignalASIContactExchange.normalizeCompactPhoneContactQR(rawObject) ?? rawObject
    guard
          let value = object[key] as? String,
          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return fallback
    }
    return value
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct SignalASIContactQRShareSheet: UIViewControllerRepresentable {
  let items: [Any]

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: items, applicationActivities: nil)
  }

  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct MyContactQRHeroView: View {
  var name: String
  var signalASIId: String
  var fingerprint: String
  var badge: String

  var body: some View {
    HStack(alignment: .center, spacing: 14) {
      SignalASIIdenticonView(
        pattern: SignalASIIdenticon.fromIdentityFingerprint(fingerprint)
      )
      .frame(width: 72, height: 72)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 8) {
          Text(name.ifBlank("SignalASI"))
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(.signalASITextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
          Text(badge)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.signalASIAccent)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 7)
            .frame(minHeight: 22)
            .background(Color.signalASIAccent.opacity(0.12))
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
