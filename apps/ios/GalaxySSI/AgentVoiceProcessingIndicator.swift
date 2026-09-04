import SwiftUI

struct AgentVoiceProcessingIndicator: View {
  var title: String
  var subtitle: String

  @State private var isAnimating = false

  var body: some View {
    HStack(spacing: 11) {
      HStack(spacing: 5) {
        ForEach(0..<3, id: \.self) { index in
          Circle()
            .fill(Color.galaxySSIAccent)
            .frame(width: 7, height: 7)
            .scaleEffect(isAnimating ? 1 : 0.82)
            .opacity(isAnimating ? 1 : 0.32)
            .animation(
              .easeInOut(duration: 0.45)
                .repeatForever(autoreverses: true)
                .delay(Double(index) * 0.14),
              value: isAnimating
            )
        }
      }
      .frame(width: 42, height: 32)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.82)
        Text(subtitle)
          .font(.system(size: 11))
          .foregroundColor(.galaxySSITextSecondary)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .combine)
    .onAppear { isAnimating = true }
    .onDisappear { isAnimating = false }
  }
}
