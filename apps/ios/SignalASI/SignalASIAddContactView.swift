import SwiftUI

struct AddContactView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var myQRCodePresented = false
  @State private var contactScannerPresented = false
  @State private var addCloudModelPresented = false
  @State private var contactImportStatus = ""
  @State private var contactImportIsError = false

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("signalasi.add_contact.title", "Add"),
        leading: {
          SignalASIBackButton()
        },
        trailing: {
          Color.clear
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
            AddContactActionRow(
              title: t("signalasi.add_contact.cloud_title", "Add Cloud Model"),
              subtitle: t(
                "signalasi.add_contact.cloud_subtitle",
                "Provider, model, and API key are configured directly on the phone."
              ),
              systemImage: "cloud.fill",
              tint: .signalASIInsightText,
              badge: t("signalasi.add_contact.title", "Add")
            ) {
              addCloudModelPresented = true
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
          contactImportStatus = message
          contactImportIsError = true
        }
      )
    }
    .sheet(isPresented: $addCloudModelPresented) {
      AddCloudModelView()
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
    do {
      switch try SignalASIContactExchange.classifyQRCode(value) {
      case .desktopPairing(let pairing):
        contactImportStatus = String(
          format: t("signalasi.pairing.desktop_claim_sending", "Adding %@..."),
          pairing.desktopName
        )
        contactImportIsError = false
        Task { await pairDesktopQRCode(value, desktopName: pairing.desktopName) }
      case .contact(let request):
        let stored = store.addFriendRequest(request)
        contactImportStatus = String(
          format: t("signalasi.friend_request.added", "Friend request added for %@."),
          stored.name
        )
        contactImportIsError = false
      }
    } catch {
      contactImportStatus = error.localizedDescription
      contactImportIsError = true
    }
  }

  private func pairDesktopQRCode(_ value: String, desktopName: String) async {
    do {
      try await coordinator.pair(using: value)
      contactImportStatus = String(
        format: t("signalasi.pairing.desktop_claim_sent", "%@ added. Waiting for desktop confirmation."),
        desktopName
      )
      contactImportIsError = false
    } catch {
      contactImportStatus = error.localizedDescription
      contactImportIsError = true
    }
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
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 11)
      .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
      .background(Color.signalASISurface)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}
