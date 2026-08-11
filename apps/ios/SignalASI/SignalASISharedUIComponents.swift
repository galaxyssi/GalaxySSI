import SwiftUI
import UIKit

private func signalASIColor(light: UInt32, dark: UInt32) -> UIColor {
  UIColor { traits in
    signalASIColor(traits.userInterfaceStyle == .dark ? dark : light)
  }
}

private func signalASIColor(_ rgb: UInt32) -> UIColor {
  UIColor(
    red: CGFloat(Double((rgb >> 16) & 0xFF) / 255.0),
    green: CGFloat(Double((rgb >> 8) & 0xFF) / 255.0),
    blue: CGFloat(Double(rgb & 0xFF) / 255.0),
    alpha: 1.0
  )
}

extension Color {
  static var signalASIPageBackground: Color { Color(signalASIColor(light: 0xF6F7F8, dark: 0x15171B)) }
  static var signalASIBarBackground: Color { Color(signalASIColor(light: 0xFFFFFF, dark: 0x202329)) }
  static var signalASISurface: Color { Color(signalASIColor(light: 0xFFFFFF, dark: 0x252930)) }
  static var signalASISearchBackground: Color { Color(signalASIColor(light: 0xE5E5EA, dark: 0x2B3038)) }
  static var signalASITextPrimary: Color { Color(signalASIColor(light: 0x111111, dark: 0xF2F4F7)) }
  static var signalASITextSecondary: Color { Color(signalASIColor(light: 0x8E8E93, dark: 0xA5ABB6)) }
  static var signalASIAgentSessionTitle: Color { Color(signalASIColor(light: 0x505052, dark: 0xCCD0D7)) }
  static var signalASIAccent: Color { Color(signalASIColor(light: 0x14C66A, dark: 0x19D36B)) }
  static var signalASISentBubble: Color { Color(signalASIColor(light: 0x95EC69, dark: 0x2E8B57)) }
  static var signalASIIncomingBubble: Color { Color(signalASIColor(light: 0xFFFFFF, dark: 0x252930)) }
  static var signalASIButtonSoft: Color { Color(signalASIColor(light: 0xE9EAEC, dark: 0x363B44)) }
  static var signalASIInputStroke: Color { Color(signalASIColor(light: 0xC7C7CC, dark: 0x363B44)) }
  static var signalASIUnreadRed: Color { Color(signalASIColor(light: 0xFF3B30, dark: 0xFF5A5F)) }
  static var signalASISeparator: Color { Color(signalASIColor(light: 0xE5E5EA, dark: 0x343841)) }
  static var signalASIInsightBackground: Color { Color(signalASIColor(light: 0xF2F6FE, dark: 0x202A36)) }
  static var signalASIInsightStroke: Color { Color(signalASIColor(light: 0xD8E6FB, dark: 0x34475C)) }
  static var signalASIInsightText: Color { Color(signalASIColor(light: 0x315B86, dark: 0xB8D5F2)) }
  static var signalASIAgentRecordingLight: Color { Color(signalASIColor(light: 0xDFF8D8, dark: 0x1F4637)) }
  static var signalASIAgentRecordingMid: Color { Color(signalASIColor(light: 0xA6ED82, dark: 0x246F43)) }
  static var signalASIAgentRecordingDeep: Color { Color(signalASIColor(light: 0x65D45C, dark: 0x198D43)) }
  static var signalASIAgentVoiceCancel: Color { Color(signalASIColor(light: 0xFF3B30, dark: 0xFF5A5F)) }
}

struct SignalASILogoView: View {
  var size: CGFloat
  var cornerRadius: CGFloat = 9

  var body: some View {
    Image("SignalASILogo")
      .resizable()
      .scaledToFill()
      .frame(width: size, height: size)
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }
}

struct SignalASITopBar<Leading: View, Trailing: View>: View {
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
    .background(Color.signalASIBarBackground)
  }

  private var titleLabel: some View {
    Text(title)
      .font(.system(size: 17, weight: .bold))
      .foregroundColor(.signalASITextPrimary)
      .frame(maxWidth: .infinity, minHeight: 56)
  }
}

struct SignalASIBackButton: View {
  @Environment(\.presentationMode) private var presentationMode

  var body: some View {
    Button {
      presentationMode.wrappedValue.dismiss()
    } label: {
      Image(systemName: "chevron.left")
        .font(.system(size: 22, weight: .semibold))
        .foregroundColor(.signalASITextPrimary)
    }
  }
}

struct SignalASIAndroidIconButton: View {
  var systemName: String
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 20, weight: .semibold))
        .foregroundColor(.signalASITextPrimary)
        .frame(width: 40, height: 40)
    }
    .buttonStyle(.plain)
  }
}
