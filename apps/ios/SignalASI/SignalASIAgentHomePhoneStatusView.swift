import Foundation
import SwiftUI
import UIKit

struct SignalASIAgentHomePhoneStatusView: View {
  var t: (String, String) -> String

  @State private var snapshot = AgentIOSDefaultDeviceMemoryStatusProvider().snapshot()

  var body: some View {
    NavigationLink(destination: SignalASISystemStatusView()) {
      HStack(spacing: 9) {
        Image(systemName: snapshot.lowMemory ? "exclamationmark.triangle.fill" : "memorychip")
          .font(.system(size: 17, weight: .semibold))
          .foregroundColor(snapshot.lowMemory ? .orange : .signalASIAccent)
          .frame(width: 24, height: 24)

        VStack(alignment: .leading, spacing: 2) {
          Text(t("signalasi.agent.readiness.phone_memory", "Phone memory"))
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.signalASITextSecondary)
            .lineLimit(1)
          Text(memoryValue)
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(.signalASITextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
          Text(pressureValue)
            .font(.system(size: 10.5))
            .foregroundColor(snapshot.lowMemory ? .orange : .signalASITextSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
        }

        Spacer(minLength: 6)
        Image(systemName: "chevron.right")
          .font(.system(size: 11, weight: .bold))
          .foregroundColor(.signalASITextSecondary)
      }
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
      .background(Color.signalASISurface)
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke(
            (snapshot.lowMemory ? Color.orange : Color.signalASIAccent).opacity(0.55),
            lineWidth: 1
          )
      )
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Text(
      "\(t("signalasi.agent.readiness.phone_memory", "Phone memory")): \(memoryValue), \(pressureValue)"
    ))
    .onAppear(perform: refresh)
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
      refresh()
    }
  }

  private var memoryValue: String {
    String(
      format: t(
        "signalasi.agent.readiness.phone_memory_value",
        "%@ free / %@"
      ),
      formatBytes(snapshot.availableBytes),
      formatBytes(snapshot.totalBytes)
    )
  }

  private var pressureValue: String {
    let pressure = t(
      "signalasi.agent.readiness.memory_pressure_\(snapshot.pressure)",
      snapshot.pressure.capitalized
    )
    if snapshot.lowMemory {
      return t(
        "signalasi.agent.readiness.phone_memory_low",
        "Low memory"
      ) + " · " + pressure
    }
    return t(
      "signalasi.agent.readiness.phone_memory_normal",
      "Memory normal"
    ) + " · " + pressure
  }

  private func refresh() {
    snapshot = AgentIOSDefaultDeviceMemoryStatusProvider().snapshot()
  }

  private func formatBytes(_ value: Int64) -> String {
    let bytes = Double(max(0, value))
    if bytes >= 1_024 * 1_024 * 1_024 {
      return String(format: "%.1f GB", bytes / (1_024 * 1_024 * 1_024))
    }
    if bytes >= 1_024 * 1_024 {
      return String(format: "%.1f MB", bytes / (1_024 * 1_024))
    }
    return String(format: "%.1f KB", bytes / 1_024)
  }
}
