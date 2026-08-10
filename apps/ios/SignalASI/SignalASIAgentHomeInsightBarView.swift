import SwiftUI

struct SignalASIAgentHomeInsightBarView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage

  var count: Int

  private var title: String {
    String(
      format: SignalASILocalization.string(
        "agent_global_new_insights",
        fallback: "SignalASI has %d new findings",
        language: interfaceLanguage
      ),
      count
    )
  }

  var body: some View {
    NavigationLink(destination: SignalASIGlobalAgentInsightInboxView()) {
      HStack(spacing: 9) {
        Image(systemName: "sparkles")
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(.signalASIInsightText)
          .frame(width: 20, height: 20)
        Text(title)
          .font(.system(size: 13, weight: .bold))
          .foregroundColor(.signalASIInsightText)
          .lineLimit(1)
          .truncationMode(.tail)
        Spacer(minLength: 4)
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .bold))
          .foregroundColor(.signalASIInsightText)
          .frame(width: 18, height: 18)
      }
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity, minHeight: 44)
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
