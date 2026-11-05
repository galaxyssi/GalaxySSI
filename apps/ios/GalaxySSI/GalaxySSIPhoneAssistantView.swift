import CallKit
import SwiftUI

enum GalaxySSIPhoneDialTarget {
  static func url(for input: String) -> URL? {
    guard input.utf8.count <= 64 else { return nil }
    let value = input.filter { !" -().".contains($0) }
    let digits = value.hasPrefix("+") ? value.dropFirst() : value[...]
    guard !digits.isEmpty, digits.utf8.count <= 24,
          digits.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
    return URL(string: "tel:\(value)")
  }
}

private final class GalaxySSIPhoneCallObservation: NSObject, ObservableObject, CXCallObserverDelegate {
  enum Status { case idle, active, held }
  @Published private(set) var status = Status.idle
  private var observer: CXCallObserver?

  func start() {
    guard observer == nil else { return }
    let observer = CXCallObserver()
    self.observer = observer
    observer.setDelegate(self, queue: .main)
    update(observer.calls)
  }

  func stop() {
    observer?.setDelegate(nil, queue: nil)
    observer = nil
    status = .idle
  }

  func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
    guard observer === callObserver else { return }
    update(callObserver.calls)
  }

  private func update(_ calls: [CXCall]) {
    let visible = calls.filter { !$0.hasEnded }
    status = visible.isEmpty ? .idle : visible.allSatisfy(\.isOnHold) ? .held : .active
  }
}

struct GalaxySSIPhoneAssistantView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.openURL) private var openURL
  @StateObject private var calls = GalaxySSIPhoneCallObservation()
  @State private var number = ""
  @State private var handoffFailed = false

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(title: t("phone_assistant_title", "Phone"), leading: { GalaxySSIBackButton() },
                      trailing: { Color.clear })
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          GalaxySSISecurityStatusRow(
            title: callStatus,
            subtitle: t("phone_assistant_audio_unavailable", "Call audio unavailable"),
            systemImage: "phone",
            tint: calls.status == .idle ? .gray : .galaxySSIAccent,
            badge: ""
          )
          TextField(t("phone_assistant_number", "Phone number"), text: $number)
            .keyboardType(.phonePad)
            .textContentType(.telephoneNumber)
            .textFieldStyle(.roundedBorder)
            .onChange(of: number) { value in
              if value.count > 64 { number = String(value.prefix(64)) }
              handoffFailed = false
            }
          Button {
            guard scenePhase == .active, let url = GalaxySSIPhoneDialTarget.url(for: number) else { return }
            openURL(url) { accepted in
              handoffFailed = !accepted
            }
          } label: {
            Label(t("phone_assistant_dial", "Dial"), systemImage: "phone.arrow.up.right")
              .frame(minHeight: 44)
          }
          .buttonStyle(.borderedProminent)
          .disabled(scenePhase != .active || GalaxySSIPhoneDialTarget.url(for: number) == nil)
          if handoffFailed {
            Text(t("phone_assistant_handoff_failed", "System dialing unavailable"))
              .font(.footnote)
              .foregroundColor(.secondary)
          }
        }
        .padding(14)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear { if scenePhase == .active { calls.start() } }
    .onChange(of: scenePhase) { phase in
      if phase == .active { calls.start() }
      else { clear() }
    }
    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIRuntimePlaintextWillClear)) { _ in clear() }
    .onDisappear(perform: clear)
  }

  private var callStatus: String {
    switch calls.status {
    case .idle: return t("phone_assistant_idle", "No visible call")
    case .active: return t("phone_assistant_active", "Call in progress")
    case .held: return t("phone_assistant_held", "Call on hold")
    }
  }

  private func clear() {
    calls.stop()
    number.removeAll(keepingCapacity: false)
    handoffFailed = false
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}
