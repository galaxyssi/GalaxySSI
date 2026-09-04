import SwiftUI
import UIKit

private func galaxySSIColor(light: UInt32, dark: UInt32) -> UIColor {
  UIColor { traits in
    galaxySSIColor(traits.userInterfaceStyle == .dark ? dark : light)
  }
}

private func galaxySSIColor(_ rgb: UInt32) -> UIColor {
  UIColor(
    red: CGFloat(Double((rgb >> 16) & 0xFF) / 255.0),
    green: CGFloat(Double((rgb >> 8) & 0xFF) / 255.0),
    blue: CGFloat(Double(rgb & 0xFF) / 255.0),
    alpha: 1.0
  )
}

extension Color {
  static var galaxySSIPageBackground: Color { Color(galaxySSIColor(light: 0xF6F7F8, dark: 0x15171B)) }
  static var galaxySSIBarBackground: Color { Color(galaxySSIColor(light: 0xFFFFFF, dark: 0x202329)) }
  static var galaxySSISurface: Color { Color(galaxySSIColor(light: 0xFFFFFF, dark: 0x252930)) }
  static var galaxySSISearchBackground: Color { Color(galaxySSIColor(light: 0xE5E5EA, dark: 0x2B3038)) }
  static var galaxySSITextPrimary: Color { Color(galaxySSIColor(light: 0x111111, dark: 0xF2F4F7)) }
  static var galaxySSITextSecondary: Color { Color(galaxySSIColor(light: 0x8E8E93, dark: 0xA5ABB6)) }
  static var galaxySSIAgentSessionTitle: Color { Color(galaxySSIColor(light: 0x505052, dark: 0xCCD0D7)) }
  static var galaxySSIAccent: Color { Color(galaxySSIColor(light: 0x14C66A, dark: 0x19D36B)) }
  static var galaxySSISentBubble: Color { Color(galaxySSIColor(light: 0x95EC69, dark: 0x2E8B57)) }
  static var galaxySSIIncomingBubble: Color { Color(galaxySSIColor(light: 0xFFFFFF, dark: 0x252930)) }
  static var galaxySSIButtonSoft: Color { Color(galaxySSIColor(light: 0xE9EAEC, dark: 0x363B44)) }
  static var galaxySSIInputStroke: Color { Color(galaxySSIColor(light: 0xC7C7CC, dark: 0x363B44)) }
  static var galaxySSIUnreadRed: Color { Color(galaxySSIColor(light: 0xFF3B30, dark: 0xFF5A5F)) }
  static var galaxySSISeparator: Color { Color(galaxySSIColor(light: 0xE5E5EA, dark: 0x343841)) }
  static var galaxySSIInsightBackground: Color { Color(galaxySSIColor(light: 0xF2F6FE, dark: 0x202A36)) }
  static var galaxySSIInsightStroke: Color { Color(galaxySSIColor(light: 0xD8E6FB, dark: 0x34475C)) }
  static var galaxySSIInsightText: Color { Color(galaxySSIColor(light: 0x315B86, dark: 0xB8D5F2)) }
  static var galaxySSIAgentRecordingLight: Color { Color(galaxySSIColor(light: 0xDFF8D8, dark: 0x1F4637)) }
  static var galaxySSIAgentRecordingMid: Color { Color(galaxySSIColor(light: 0xA6ED82, dark: 0x246F43)) }
  static var galaxySSIAgentRecordingDeep: Color { Color(galaxySSIColor(light: 0x65D45C, dark: 0x198D43)) }
  static var galaxySSIAgentVoiceCancel: Color { Color(galaxySSIColor(light: 0xFF3B30, dark: 0xFF5A5F)) }
}

struct GalaxySSILogoView: View {
  var size: CGFloat
  var cornerRadius: CGFloat = 9

  var body: some View {
    Image("GalaxySSILogo")
      .resizable()
      .scaledToFill()
      .frame(width: size, height: size)
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }
}

struct GalaxySSITopBar<Leading: View, Trailing: View>: View {
  var title: String
  var onTitleTap: (() -> Void)? = nil
  let leading: Leading
  let trailing: Trailing

  init(
    title: String,
    onTitleTap: (() -> Void)? = nil,
    @ViewBuilder leading: () -> Leading,
    @ViewBuilder trailing: () -> Trailing
  ) {
    self.title = title
    self.onTitleTap = onTitleTap
    self.leading = leading()
    self.trailing = trailing()
  }

  var body: some View {
    HStack(spacing: 0) {
      leading
        .frame(width: 40, height: 56)
      if let onTitleTap {
        Button(action: onTitleTap) {
          titleLabel
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
      } else {
        titleLabel
      }
      trailing
        .frame(width: 40, height: 56)
    }
    .padding(.horizontal, 16)
    .frame(height: 56)
    .background(Color.galaxySSIBarBackground)
  }

  private var titleLabel: some View {
    Text(title)
      .font(.system(size: 17, weight: .bold))
      .foregroundColor(.galaxySSITextPrimary)
      .frame(maxWidth: .infinity, minHeight: 56)
  }
}

struct GalaxySSIBackButton: View {
  @Environment(\.presentationMode) private var presentationMode

  var body: some View {
    Button {
      presentationMode.wrappedValue.dismiss()
    } label: {
      Image(systemName: "chevron.left")
        .font(.system(size: 22, weight: .semibold))
        .foregroundColor(.galaxySSITextPrimary)
    }
  }
}

struct GalaxySSIAndroidIconButton: View {
  var systemName: String
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 20, weight: .semibold))
        .foregroundColor(.galaxySSITextPrimary)
        .frame(width: 40, height: 40)
    }
    .buttonStyle(.plain)
  }
}
