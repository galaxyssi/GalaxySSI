import SwiftUI

struct GalaxySSIAgentHomeInsightBarView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage

  var count: Int

  private var title: String {
    String(
      format: GalaxySSILocalization.string(
        "agent_global_new_insights",
        fallback: "GalaxySSI has %d new findings",
        language: interfaceLanguage
      ),
      count
    )
  }

  var body: some View {
    NavigationLink(destination: GalaxySSIGlobalAgentInsightInboxView()) {
      HStack(spacing: 9) {
        Image(systemName: "sparkles")
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(.galaxySSIInsightText)
          .frame(width: 20, height: 20)
        Text(title)
          .font(.system(size: 13, weight: .bold))
          .foregroundColor(.galaxySSIInsightText)
          .lineLimit(1)
          .truncationMode(.tail)
        Spacer(minLength: 4)
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .bold))
          .foregroundColor(.galaxySSIInsightText)
          .frame(width: 18, height: 18)
      }
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity, minHeight: 44)
      .background(Color.galaxySSIInsightBackground)
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke(Color.galaxySSIInsightStroke, lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(title))
  }
}
