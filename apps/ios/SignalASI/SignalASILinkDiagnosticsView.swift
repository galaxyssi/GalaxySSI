import SwiftUI

struct SignalASILinkDiagnosticsView: View {
  @State private var snapshot = SignalASILinkTransportDiagnostics.snapshot()

  var body: some View {
    List {
      Section("Summary") {
        metricRow(
          "Replay Events",
          value: snapshot.replayCount,
          subtitle: "Encrypted and pending replay handling",
          systemImage: "arrow.clockwise",
          tint: .blue
        )
        metricRow(
          "Duplicate Events",
          value: snapshot.duplicateCount,
          subtitle: "Duplicate messages, receipts, and chunks",
          systemImage: "doc.on.doc",
          tint: .orange
        )
        metricRow(
          "Old Counter Events",
          value: snapshot.oldCounterCount,
          subtitle: "Rejected stale encrypted counters",
          systemImage: "shield",
          tint: .purple
        )
        metricRow(
          "Transport Failures",
          value: snapshot.failureCount,
          subtitle: "Decrypt and fragment rejection events",
          systemImage: "exclamationmark.triangle",
          tint: .red
        )
      }

      Section("Recent Events") {
        if snapshot.recentEvents.isEmpty {
          Label("No Transport Anomalies", systemImage: "checkmark.shield")
            .foregroundColor(.secondary)
        } else {
          ForEach(Array(snapshot.recentEvents.prefix(20))) { event in
            eventRow(event)
          }
        }
      }
    }
    .navigationTitle("Link Diagnostics")
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button {
          SignalASILinkTransportDiagnostics.clear()
          refresh()
        } label: {
          Label("Clear", systemImage: "trash")
        }
        .disabled(snapshot.totalEvents == 0)
      }
    }
    .onAppear(perform: refresh)
  }

  private func refresh() {
    snapshot = SignalASILinkTransportDiagnostics.snapshot()
  }

  private func metricRow(
    _ title: String,
    value: Int64,
    subtitle: String,
    systemImage: String,
    tint: Color
  ) -> some View {
    HStack(alignment: .center, spacing: 12) {
      Image(systemName: systemImage)
        .foregroundColor(tint)
        .frame(width: 24)
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
        Text(subtitle)
          .font(.caption)
          .foregroundColor(.secondary)
      }
      Spacer()
      Text("\(value)")
        .font(.headline.monospacedDigit())
    }
  }

  private func eventRow(_ event: SignalASILinkDiagnosticEvent) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: event.kind.systemImage)
        .foregroundColor(event.kind.tint)
        .frame(width: 24)
      VStack(alignment: .leading, spacing: 4) {
        Text(event.kind.displayTitle)
        Text(eventSubtitle(event))
          .font(.caption)
          .foregroundColor(.secondary)
        if !event.detailCode.isEmpty {
          Text(event.detailCode)
            .font(.system(.caption2, design: .monospaced))
            .foregroundColor(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }
    }
  }

  private func eventSubtitle(_ event: SignalASILinkDiagnosticEvent) -> String {
    let date = Date(timeIntervalSince1970: Double(event.recordedAtMillis) / 1_000)
      .formatted(date: .abbreviated, time: .standard)
    let references = [event.endpointRef, event.messageRef]
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .joined(separator: " / ")
    return references.isEmpty ? "\(date) / Unknown reference" : "\(date) / \(references)"
  }
}

private extension SignalASILinkDiagnosticKind {
  var displayTitle: String {
    switch self {
    case .encryptedReplay: return "Encrypted Replay"
    case .pendingReplay: return "Pending Replay"
    case .duplicateMessage: return "Duplicate Message"
    case .duplicateReceipt: return "Duplicate Receipt"
    case .oldCounter: return "Old Counter"
    case .decryptFailure: return "Decrypt Failure"
    case .chunkDuplicate: return "Chunk Duplicate"
    case .fragmentRejected: return "Fragment Rejected"
    }
  }

  var systemImage: String {
    switch self {
    case .encryptedReplay, .pendingReplay:
      return "arrow.clockwise"
    case .duplicateMessage, .duplicateReceipt, .chunkDuplicate:
      return "doc.on.doc"
    case .oldCounter:
      return "shield"
    case .decryptFailure, .fragmentRejected:
      return "exclamationmark.triangle"
    }
  }

  var tint: Color {
    switch self {
    case .encryptedReplay, .pendingReplay:
      return .blue
    case .duplicateMessage, .duplicateReceipt, .chunkDuplicate:
      return .orange
    case .oldCounter:
      return .purple
    case .decryptFailure, .fragmentRejected:
      return .red
    }
  }
}
