import SwiftUI
import UIKit

@MainActor
struct GalaxySSIGlassesWifiQRView: View {
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @State private var ssid = ""
  @State private var password = ""
  @State private var image: UIImage?
  @State private var failed = false
  @State private var capture = GalaxySSIScreenAssistantCapture.noWindow
  @State private var expiry = UUID()

  private var mayDisplay: Bool {
    scene == .active && capture == .clear && UIApplication.shared.isProtectedDataAvailable
  }

  var body: some View {
    Form {
      if mayDisplay, let image {
        Section {
          Image(uiImage: image)
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .padding(20)
            .frame(maxWidth: 340)
            .background(Color.white)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(t("code", "Glasses Wi-Fi setup QR"))
          Text(t("sensitive", "This QR contains the Wi-Fi password. Show it only to your glasses."))
            .font(.footnote)
          Button(t("hide", "Hide code")) { clear() }
        } header: { Text(ssid) }
      } else if mayDisplay {
        Section {
          TextField(t("ssid", "Wi-Fi name (SSID)"), text: $ssid)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
          SecureField(t("password", "WPA2 password"), text: $password)
            .textInputAutocapitalization(.never)
          Button(t("show", "Show Wi-Fi QR"), action: show)
            .disabled(!GalaxySSIGlassesWifiQR.validSSID(ssid) || !GalaxySSIGlassesWifiQR.validPassword(password))
          if !password.isEmpty, !GalaxySSIGlassesWifiQR.validPassword(password) {
            Text(t("password_length", "Use a WPA2 password with 8 to 63 characters.")).font(.footnote)
          }
          if failed { Text(t("failed", "Could not create the Wi-Fi code.")) }
        }
      } else if capture == .captured {
        Text(t("captured", "Wi-Fi setup is hidden while the screen is recorded or mirrored."))
      }
    }
    .privacySensitive()
    .background(GalaxySSIScreenCaptureProbe(capture: $capture).allowsHitTesting(false))
    .navigationTitle(t("title", "Glasses Wi-Fi QR"))
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarHidden(false)
    .onChange(of: scene) { if $0 != .active { clear() } }
    .onChange(of: capture) { if $0 != .clear { clear() } }
    .onDisappear { clear() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in clear() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in clear() }
    .task(id: expiry) {
      let id = expiry
      guard image != nil else { return }
      do { try await Task.sleep(nanoseconds: 60_000_000_000) } catch { return }
      if expiry == id, !Task.isCancelled { clear() }
    }
  }

  private func show() {
    guard mayDisplay, let payload = GalaxySSIGlassesWifiQR.payload(ssid: ssid, password: password),
          let rendered = GalaxySSIQRCodeImageRenderer.image(from: payload) else { failed = true; return }
    password = ""
    failed = false
    image = rendered
    expiry = UUID()
  }

  private func clear() {
    image = nil
    ssid = ""
    password = ""
    failed = false
    expiry = UUID()
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.glasses_wifi_qr." + key, fallback: fallback, language: language)
  }
}
