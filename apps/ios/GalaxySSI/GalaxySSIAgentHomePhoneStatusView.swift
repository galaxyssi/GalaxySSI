import Foundation
import Combine
import SwiftUI
import UIKit

struct GalaxySSIAgentHomePhoneStatusView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var t: (String, String) -> String

  @State private var snapshot = AgentIOSDefaultDeviceMemoryStatusProvider().snapshot()
  @State private var storageSnapshot: AgentMcpJSONObject = [:]
  @State private var batterySnapshot: AgentMcpJSONObject = [:]
  @State private var networkSnapshot: AgentMcpJSONObject = [:]
  @State private var lastRefreshDate: Date?

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(spacing: 9) {
        NavigationLink(destination: GalaxySSISystemStatusView()) {
          HStack(spacing: 9) {
            Image(systemName: snapshot.lowMemory ? "exclamationmark.triangle.fill" : "memorychip")
              .font(.system(size: 17, weight: .semibold))
              .foregroundColor(snapshot.lowMemory ? .orange : .galaxySSIAccent)
              .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
              Text(t("galaxyssi.agent.readiness.phone_memory", "Phone memory"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.galaxySSITextSecondary)
                .lineLimit(1)
              Text(memoryValue)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.galaxySSITextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
              Text(pressureValue)
                .font(.system(size: 10.5))
                .foregroundColor(snapshot.lowMemory ? .orange : .galaxySSITextSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
              .font(.system(size: 11, weight: .bold))
              .foregroundColor(.galaxySSITextSecondary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)

        Button(action: refresh) {
          Image(systemName: "arrow.clockwise")
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.galaxySSIAccent)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(t("galaxyssi.agent.readiness.phone_refresh", "Refresh phone status")))
      }

      NavigationLink(destination: GalaxySSISystemStatusView()) {
        statusMetrics
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(phoneStatusAccessibilityLabel))

      if let lastRefreshDate = lastRefreshDate {
        Text(
          String(
            format: t("galaxyssi.agent.readiness.phone_updated", "Updated %@"),
            refreshTime(for: lastRefreshDate)
          )
        )
        .font(.system(size: 9.5))
        .foregroundColor(.galaxySSITextSecondary)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
    .background(Color.galaxySSISurface)
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(
          (snapshot.lowMemory ? Color.orange : Color.galaxySSIAccent).opacity(0.55),
          lineWidth: 1
        )
    )
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .onAppear(perform: refresh)
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
      refresh()
    }
    .onReceive(
      Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    ) { _ in
      guard UIApplication.shared.applicationState == .active else { return }
      refresh()
    }
  }

  private var memoryValue: String {
    String(
      format: t(
        "galaxyssi.agent.readiness.phone_memory_value",
        "%@ free / %@"
      ),
      formatBytes(snapshot.availableBytes),
      formatBytes(snapshot.totalBytes)
    )
  }

  private var pressureValue: String {
    let pressure = t(
      "galaxyssi.agent.readiness.memory_pressure_\(snapshot.pressure)",
      snapshot.pressure.capitalized
    )
    if snapshot.lowMemory {
      return t(
        "galaxyssi.agent.readiness.phone_memory_low",
        "Low memory"
      ) + " / " + pressure
    }
    return t(
      "galaxyssi.agent.readiness.phone_memory_normal",
      "Memory normal"
    ) + " / " + pressure
  }

  private var batteryValue: String {
    guard let percent = batterySnapshot["percent"]?.intValue else {
      return t("galaxyssi.agent.readiness.phone_battery_unknown", "Unknown")
    }
    return String(
      format: t("galaxyssi.agent.readiness.phone_battery_value", "%d%%"),
      Int(percent)
    )
  }

  private var batteryTint: Color {
    guard let percent = batterySnapshot["percent"]?.intValue else { return .galaxySSITextSecondary }
    return percent <= 20 ? .orange : .galaxySSIAccent
  }

  private var storageValue: String {
    String(
      format: t("galaxyssi.agent.readiness.phone_storage_value", "%@ free"),
      formatBytes(storageSnapshot["available_bytes"]?.intValue ?? 0)
    )
  }

  private var storageTint: Color {
    storageSnapshot["low_storage"]?.boolValue == true ? .orange : .galaxySSIAccent
  }

  private var networkConnected: Bool {
    networkSnapshot["connected"]?.boolValue == true
  }

  private var networkValue: String {
    networkConnected
      ? t("galaxyssi.agent.readiness.phone_network_connected", "Connected")
      : t("galaxyssi.agent.readiness.phone_network_offline", "Offline")
  }

  private var phoneStatusAccessibilityLabel: String {
    "\(t("galaxyssi.agent.readiness.phone_memory", "Phone memory")): \(memoryValue), \(pressureValue); " +
      "\(t("galaxyssi.agent.readiness.phone_battery", "Battery")): \(batteryValue); " +
      "\(t("galaxyssi.agent.readiness.phone_storage", "Storage")): \(storageValue); " +
      "\(t("galaxyssi.agent.readiness.phone_network", "Network")): \(networkValue)"
  }

  @ViewBuilder
  private var statusMetrics: some View {
    if usesAccessibilityDynamicType {
      VStack(alignment: .leading, spacing: 7) {
        batteryMetric
        storageMetric
        networkMetric
      }
    } else {
      HStack(spacing: 9) {
        batteryMetric
        storageMetric
        networkMetric
      }
    }
  }

  private var batteryMetric: some View {
    statusMetric(
      title: t("galaxyssi.agent.readiness.phone_battery", "Battery"),
      value: batteryValue,
      systemImage: "battery.75",
      tint: batteryTint
    )
  }

  private var storageMetric: some View {
    statusMetric(
      title: t("galaxyssi.agent.readiness.phone_storage", "Storage"),
      value: storageValue,
      systemImage: "internaldrive",
      tint: storageTint
    )
  }

  private var networkMetric: some View {
    statusMetric(
      title: t("galaxyssi.agent.readiness.phone_network", "Network"),
      value: networkValue,
      systemImage: "antenna.radiowaves.left.and.right",
      tint: networkConnected ? .galaxySSIAccent : .orange
    )
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
          .foregroundColor(.galaxySSITextSecondary)
          .lineLimit(1)
      }
      Text(value)
        .font(.system(size: 10.5, weight: .bold))
        .foregroundColor(.galaxySSITextPrimary)
        .lineLimit(usesAccessibilityDynamicType ? 2 : 1)
        .minimumScaleFactor(usesAccessibilityDynamicType ? 1 : 0.65)
    }
    .frame(
      maxWidth: .infinity,
      minHeight: usesAccessibilityDynamicType ? 34 : nil,
      alignment: .leading
    )
  }

  private var usesAccessibilityDynamicType: Bool {
    dynamicTypeSize.isAccessibilitySize
  }

  private func refresh() {
    snapshot = AgentIOSDefaultDeviceMemoryStatusProvider().snapshot()
    let nowMillis = Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    let provider = AgentIOSDefaultHardwareStatusProvider()
    storageSnapshot = provider.storageStatus(nowMillis: nowMillis)
    batterySnapshot = provider.batteryStatus(nowMillis: nowMillis)
    networkSnapshot = provider.networkStatus(nowMillis: nowMillis)
    lastRefreshDate = Date()
  }

  private func refreshTime(for date: Date) -> String {
    DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
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
