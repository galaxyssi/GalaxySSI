import SwiftUI

struct GalaxySSIAgentScanStatusView: View {
  var message: String
  var isError: Bool
  var dismissTitle: String
  var retryTitle: String
  var onRetry: () -> Void
  var onDismiss: () -> Void

  private var tint: Color {
    isError ? .orange : .galaxySSIAccent
  }

  var body: some View {
    HStack(alignment: .top, spacing: 9) {
      Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
        .font(.system(size: 16, weight: .semibold))
        .foregroundColor(tint)
        .frame(width: 22, height: 22)
      Text(message)
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(.galaxySSITextPrimary)
        .lineLimit(3)
        .fixedSize(horizontal: false, vertical: true)
      if isError {
        Button(action: onRetry) {
          Image(systemName: "qrcode.viewfinder")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(tint)
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(retryTitle))
      }
      Spacer(minLength: 4)
      Button(action: onDismiss) {
        Image(systemName: "xmark")
          .font(.system(size: 11, weight: .bold))
          .foregroundColor(.galaxySSITextSecondary)
          .frame(width: 28, height: 28)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(dismissTitle))
    }
    .padding(.horizontal, 11)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background((isError ? Color.orange : Color.galaxySSIAccent).opacity(0.10))
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(tint.opacity(0.35), lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
