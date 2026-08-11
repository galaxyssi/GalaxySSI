import SwiftUI

struct SignalASIDeviceContactsView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore

  private var deviceContacts: [SignalASIContact] {
    store.contactList(matching: "")
      .filter { contact in
        contact.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "device" ||
          contact.agentKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "device"
      }
      .sorted { left, right in
        left.displayName.localizedCaseInsensitiveCompare(right.displayName) == .orderedAscending
      }
  }

  private var unrepresentedPairedLinks: [ServerLink] {
    store.serverLinks
      .filter(\.paired)
      .filter { link in
        !deviceContacts.contains { contact in
          contact.desktopId == link.desktopId || contact.signalASIId == link.desktopId
        }
      }
      .sorted { left, right in
        left.desktopName.localizedCaseInsensitiveCompare(right.desktopName) == .orderedAscending
      }
  }

  private var deviceCount: Int {
    deviceContacts.count + unrepresentedPairedLinks.count
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("signalasi.device.contacts_title", "My Devices"),
        leading: { SignalASIBackButton() },
        trailing: { Color.clear }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          SignalASIDeviceContactsHeroView(
            title: t("signalasi.device.contacts_title", "My Devices"),
            subtitle: t(
              "signalasi.device.contacts_subtitle",
              "Verified device contacts and paired desktop connections"
            ),
            count: String(format: t("signalasi.device.contacts_count", "%d devices"), deviceCount)
          )

          if !deviceContacts.isEmpty {
            sectionTitle(t("signalasi.device.contacts_verified_section", "Verified Devices"))
            VStack(spacing: 8) {
              ForEach(deviceContacts) { contact in
                NavigationLink(destination: ContactDetailView(contactId: contact.id)) {
                  SignalASIDeviceContactRow(
                    title: contact.displayName.ifBlank(contact.name),
                    subtitle: contact.desktopName.ifBlank(
                      contact.setupDetail.ifBlank(t("signalasi.device.contact_subtitle", "SignalASI device"))
                    ),
                    badge: statusLabel(for: contact),
                    tint: contact.trustState == .verified ? .signalASIAccent : .orange
                  )
                }
                .buttonStyle(.plain)
              }
            }
          }

          if !unrepresentedPairedLinks.isEmpty {
            sectionTitle(t("signalasi.device.contacts_paired_section", "Paired Desktops"))
            VStack(spacing: 8) {
              ForEach(unrepresentedPairedLinks) { link in
                NavigationLink(destination: DeviceManagementView()) {
                  SignalASIDeviceContactRow(
                    title: link.desktopName.ifBlank(t("signalasi.device.pc_agent", "PC Agent")),
                    subtitle: link.accessProfile.ifBlank(link.desktopId),
                    badge: t("signalasi.status.paired", "Paired"),
                    tint: .blue
                  )
                }
                .buttonStyle(.plain)
              }
            }
          }

          if deviceCount == 0 {
            SignalASIDeviceContactsEmptyView(
              title: t("signalasi.device.contacts_empty_title", "No Device Contacts"),
              subtitle: t(
                "signalasi.device.contacts_empty_subtitle",
                "Scan a desktop QR code to securely add a device contact."
              )
            )
          }

          sectionTitle(t("signalasi.device.contacts_actions_section", "Device Actions"))
          VStack(spacing: 8) {
            SignalASIDeviceContactActionRow(
              title: t("signalasi.device.contacts_pair", "Pair a Desktop"),
              subtitle: t(
                "signalasi.device.contacts_pair_subtitle",
                "Scan and verify a SignalASI Desktop pairing QR code"
              ),
              systemImage: "qrcode.viewfinder",
              tint: .signalASIAccent
            ) {
              PairingView()
            }
            SignalASIDeviceContactActionRow(
              title: t("signalasi.device.management_title", "Device Management"),
              subtitle: t(
                "signalasi.device.management_subtitle",
                "Configure Home Assistant, file sync, and remote control"
              ),
              systemImage: "slider.horizontal.3",
              tint: .blue
            ) {
              DeviceManagementView()
            }
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

  private func statusLabel(for contact: SignalASIContact) -> String {
    if contact.trustState == .verified {
      return t("signalasi.status.verified", "Verified")
    }
    if contact.setupStatus.lowercased() == "ready" {
      return t("signalasi.status.ready", "Ready")
    }
    return t("signalasi.status.needs_setup", "Needs Setup")
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.signalASITextSecondary)
      .padding(.horizontal, 4)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct SignalASIDeviceContactsHeroView: View {
  var title: String
  var subtitle: String
  var count: String

  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(Color.blue.opacity(0.16))
        Image(systemName: "desktopcomputer")
          .font(.system(size: 24, weight: .semibold))
          .foregroundColor(.blue)
      }
      .frame(width: 52, height: 52)
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 8) {
          Text(title)
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(.signalASITextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
          Text(count)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.blue)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 7)
            .frame(minHeight: 22)
            .background(Color.blue.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
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

private struct SignalASIDeviceContactRow: View {
  var title: String
  var subtitle: String
  var badge: String
  var tint: Color

  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(tint.opacity(0.16))
        Image(systemName: "desktopcomputer")
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
      Image(systemName: "chevron.right")
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(.signalASITextSecondary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct SignalASIDeviceContactActionRow<Destination: View>: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  let destination: Destination

  init(
    title: String,
    subtitle: String,
    systemImage: String,
    tint: Color,
    @ViewBuilder destination: () -> Destination
  ) {
    self.title = title
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.tint = tint
    self.destination = destination()
  }

  var body: some View {
    NavigationLink(destination: destination) {
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
          Text(subtitle)
            .font(.system(size: 12))
            .foregroundColor(.signalASITextSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 8)
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.signalASITextSecondary)
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

private struct SignalASIDeviceContactsEmptyView: View {
  var title: String
  var subtitle: String

  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: "desktopcomputer")
        .font(.system(size: 28, weight: .semibold))
        .foregroundColor(.signalASITextSecondary)
      Text(title)
        .font(.system(size: 17, weight: .semibold))
        .foregroundColor(.signalASITextPrimary)
      Text(subtitle)
        .font(.system(size: 13))
        .foregroundColor(.signalASITextSecondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 28)
    .padding(.horizontal, 18)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
