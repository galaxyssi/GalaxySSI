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

struct SignalASIAgentRouteLogo: View {
  var label: String
  var size: CGFloat = 20

  var body: some View {
    Group {
      if let assetName = assetName {
        Image(assetName)
          .resizable()
          .scaledToFit()
          .clipShape(RoundedRectangle(cornerRadius: max(3, size * 0.2), style: .continuous))
      } else {
        Circle()
          .fill(Color.signalASIAccent)
          .overlay(
            Image(systemName: "person.2.fill")
              .font(.system(size: max(7, size * 0.42), weight: .bold))
              .foregroundColor(.white)
          )
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }

  private var assetName: String? {
    let normalized = label.lowercased()
    if normalized.contains("codex") { return "CodexLogo" }
    if normalized.contains("claude") || normalized.contains("anthropic") {
      return "ClaudeLogo"
    }
    if normalized.contains("hermes") { return "HermesLogo" }
    if normalized.contains("deepseek") { return "CloudProviderDeepSeek" }
    if normalized.contains("openrouter") { return "CloudProviderOpenRouter" }
    if normalized.contains("qwen") { return "CloudProviderQwen" }
    if normalized.contains("gemini") || normalized.contains("google") {
      return "CloudProviderGemini"
    }
    if normalized.contains("openai") || normalized.contains("gpt") {
      return "CloudProviderOpenAI"
    }
    return nil
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
