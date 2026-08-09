import SwiftUI

struct SignalASIAgentEmptyStateView: View {
  var title: String
  var subtitle: String

  var body: some View {
    VStack(spacing: 10) {
      SignalASILogoView(size: 48, cornerRadius: 10)
      Text(title)
        .font(.system(size: 18, weight: .semibold))
        .foregroundColor(.signalASITextPrimary)
      Text(subtitle)
        .font(.system(size: 13))
        .foregroundColor(.signalASITextSecondary)
    }
    .frame(maxWidth: .infinity, minHeight: 180)
    .accessibilityElement(children: .combine)
  }
}

struct SignalASIAgentLoadOlderButton: View {
  var title: String
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      Label(title, systemImage: "arrow.up")
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(.signalASIInsightText)
        .frame(maxWidth: .infinity, minHeight: 40)
        .background(Color.signalASIInsightBackground)
        .overlay(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(Color.signalASIInsightStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(title))
  }
}

struct SignalASIAgentLatestButton: View {
  var title: String
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      Label(title, systemImage: "arrow.down")
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(.signalASITextPrimary)
        .padding(.horizontal, 12)
        .frame(minHeight: 40)
        .background(Color.signalASIBarBackground)
        .overlay(
          Capsule(style: .continuous)
            .stroke(Color.signalASIInputStroke, lineWidth: 0.8)
        )
        .clipShape(Capsule(style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(title))
  }
}
