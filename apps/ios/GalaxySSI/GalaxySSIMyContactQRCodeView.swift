import SwiftUI
import UIKit

struct MyContactQRCodeView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var store: GalaxySSIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var copiedMessage = ""
  @State private var qrText = ""
  @State private var qrGenerationError = ""
  @State private var sharePresented = false

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("galaxyssi.contact.my_qr_title", "My QR Code"),
        leading: {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 17, weight: .semibold))
              .foregroundColor(.galaxySSITextPrimary)
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
              .foregroundColor(.galaxySSIAccent)
              .frame(width: 40, height: 40)
          }
          .buttonStyle(.plain)
          .disabled(!hasShareableQRCode)
          .accessibilityLabel(Text(t("galaxyssi.contact.share_qr", "Share QR Code")))
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          MyContactQRHeroView(
            name: store.profile.name,
            galaxySSIId: contactCardValue("galaxyssi_id", fallback: store.profile.galaxySSIId),
            fingerprint: contactCardValue("identity_fingerprint", fallback: store.profile.identityFingerprint),
            badge: t("galaxyssi.contact.my_qr_title", "My QR Code")
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
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .onAppear(perform: refreshQRText)
    .sheet(isPresented: $sharePresented) {
      GalaxySSIContactQRShareSheet(items: shareItems)
    }
  }

  private var qrCard: some View {
    VStack(alignment: .center, spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(Color.white)
        if let image = GalaxySSIQRCodeImageRenderer.image(from: qrText) {
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
        .foregroundColor(qrGenerationError.isEmpty ? .galaxySSITextSecondary : .red)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity)
    .padding(16)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var identitySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("galaxyssi.contact.section_identity", "Identity"))
      GalaxySSISecurityActionRow(
        title: t("settings_galaxyssi_id", "GalaxySSI ID"),
        subtitle: contactCardValue("galaxyssi_id", fallback: store.profile.galaxySSIId),
        systemImage: "link",
        tint: .blue,
        badge: t("common_copy", "Copy"),
        monospacedSubtitle: true
      ) {
        copy(
          contactCardValue("galaxyssi_id", fallback: store.profile.galaxySSIId),
          message: t("galaxyssi.contact.my_qr_id_copied", "GalaxySSI ID copied")
        )
      }
      copiedStatusRow
    }
  }

  private var payloadSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("galaxyssi.contact.payload", "Payload"))
      if hasShareableQRCode {
        GalaxySSISecurityActionRow(
          title: t("galaxyssi.contact.copy_payload", "Copy Payload"),
          subtitle: qrText,
          systemImage: "doc.on.doc",
          tint: .purple,
          badge: t("common_copy", "Copy"),
          monospacedSubtitle: true
        ) {
          copy(qrText, message: t("galaxyssi.contact.my_qr_payload_copied", "QR payload copied"))
        }
      } else {
        GalaxySSISecurityStatusRow(
          title: t("galaxyssi.contact.qr_unavailable", "QR Code Unavailable"),
          subtitle: qrGenerationError.ifBlank(t(
            "galaxyssi.contact.qr_unavailable_subtitle",
            "A signed identity card is required before this QR code can be shared."
          )),
          systemImage: "exclamationmark.triangle.fill",
          tint: .orange,
          badge: t("galaxyssi.status.unavailable", "Unavailable")
        )
      }
    }
  }

  @ViewBuilder
  private var copiedStatusRow: some View {
    if !copiedMessage.isEmpty {
      GalaxySSISecurityStatusRow(
        title: t("common_status", "Status"),
        subtitle: copiedMessage,
        systemImage: "checkmark.circle",
        tint: .galaxySSIAccent,
        badge: t("galaxyssi.common.copied", "Copied")
      )
    }
  }

  private func refreshQRText() {
    guard qrText.isEmpty else { return }
    do {
      let generated = try coordinator.myContactQRText()
      guard GalaxySSIQRCodeImageRenderer.image(from: generated) != nil else {
        throw GalaxySSIError.invalidPayload("Contact QR payload exceeds the supported QR capacity.")
      }
      qrText = generated
      qrGenerationError = ""
    } catch {
      qrText = ""
      qrGenerationError = t(
        "galaxyssi.contact.qr_generation_failed",
        "Could not create the contact QR code. Please try again."
      )
    }
  }

  private var hasShareableQRCode: Bool {
    !qrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && qrText != "{}"
  }

  private var shareItems: [Any] {
    var items: [Any] = [qrText]
    if let image = GalaxySSIQRCodeImageRenderer.image(from: qrText) {
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
    let object = GalaxySSIContactExchange.normalizeCompactPhoneContactQR(rawObject) ?? rawObject
    guard
          let value = object[key] as? String,
          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return fallback
    }
    return value
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct GalaxySSIContactQRShareSheet: UIViewControllerRepresentable {
  let items: [Any]

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: items, applicationActivities: nil)
  }

  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct MyContactQRHeroView: View {
  var name: String
  var galaxySSIId: String
  var fingerprint: String
  var badge: String

  var body: some View {
    HStack(alignment: .center, spacing: 14) {
      GalaxySSIIdenticonView(
        pattern: GalaxySSIIdenticon.fromIdentityFingerprint(fingerprint)
      )
      .frame(width: 72, height: 72)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 8) {
          Text(name.ifBlank("GalaxySSI"))
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(.galaxySSITextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
          Text(badge)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.galaxySSIAccent)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 7)
            .frame(minHeight: 22)
            .background(Color.galaxySSIAccent.opacity(0.12))
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
