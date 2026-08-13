import Foundation
import SwiftUI
import UIKit

struct SignalASIAgentHomePhoneStatusView: View {
  var t: (String, String) -> String

  @State private var snapshot = AgentIOSDefaultDeviceMemoryStatusProvider().snapshot()
  @State private var storageSnapshot: AgentMcpJSONObject = [:]
  @State private var batterySnapshot: AgentMcpJSONObject = [:]
  @State private var networkSnapshot: AgentMcpJSONObject = [:]

  var body: some View {
    NavigationLink(destination: SignalASISystemStatusView()) {
      VStack(alignment: .leading, spacing: 9) {
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

        HStack(spacing: 8) {
          statusMetric(
            title: t("signalasi.agent.readiness.phone_battery", "Battery"),
            value: batteryValue,
            systemImage: "battery.75",
            tint: batteryTint
          )
          statusMetric(
            title: t("signalasi.agent.readiness.phone_storage", "Storage"),
            value: storageValue,
            systemImage: "internaldrive",
            tint: storageTint
          )
          statusMetric(
            title: t("signalasi.agent.readiness.phone_network", "Network"),
            value: networkValue,
            systemImage: "antenna.radiowaves.left.and.right",
            tint: networkConnected ? .signalASIAccent : .orange
          )
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
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
      "\(t("signalasi.agent.readiness.phone_memory", "Phone memory")): \(memoryValue), \(pressureValue); " +
        "\(t("signalasi.agent.readiness.phone_battery", "Battery")): \(batteryValue); " +
        "\(t("signalasi.agent.readiness.phone_storage", "Storage")): \(storageValue); " +
        "\(t("signalasi.agent.readiness.phone_network", "Network")): \(networkValue)"
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

  private var batteryValue: String {
    guard let percent = batterySnapshot["percent"]?.intValue else {
      return t("signalasi.agent.readiness.phone_battery_unknown", "Unknown")
    }
    return String(
      format: t("signalasi.agent.readiness.phone_battery_value", "%d%%"),
      Int(percent)
    )
  }

  private var batteryTint: Color {
    guard let percent = batterySnapshot["percent"]?.intValue else { return .signalASITextSecondary }
    return percent <= 20 ? .orange : .signalASIAccent
  }

  private var storageValue: String {
    String(
      format: t("signalasi.agent.readiness.phone_storage_value", "%@ free"),
      formatBytes(storageSnapshot["available_bytes"]?.intValue ?? 0)
    )
  }

  private var storageTint: Color {
    storageSnapshot["low_storage"]?.boolValue == true ? .orange : .signalASIAccent
  }

  private var networkConnected: Bool {
    networkSnapshot["connected"]?.boolValue == true
  }

  private var networkValue: String {
    networkConnected
      ? t("signalasi.agent.readiness.phone_network_connected", "Connected")
      : t("signalasi.agent.readiness.phone_network_offline", "Offline")
  }

  private func statusMetric(
    title: String,
    value: String,
    systemImage: String,
    tint: Color
  ) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 4) {
        Image(systemName: systemImage)
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(tint)
        Text(title)
          .font(.system(size: 9.5, weight: .semibold))
          .foregroundColor(.signalASITextSecondary)
          .lineLimit(1)
      }
      Text(value)
        .font(.system(size: 10.5, weight: .bold))
        .foregroundColor(.signalASITextPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.65)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func refresh() {
    snapshot = AgentIOSDefaultDeviceMemoryStatusProvider().snapshot()
    let nowMillis = Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    let provider = AgentIOSDefaultHardwareStatusProvider()
    storageSnapshot = provider.storageStatus(nowMillis: nowMillis)
    batterySnapshot = provider.batteryStatus(nowMillis: nowMillis)
    networkSnapshot = provider.networkStatus(nowMillis: nowMillis)
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
