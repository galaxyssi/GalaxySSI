import SwiftUI
import UIKit

enum GalaxySSIHealthTheme {
  static let accentUIColor = UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 135 / 255, green: 230 / 255, blue: 191 / 255, alpha: 1)
      : UIColor(red: 0, green: 108 / 255, blue: 86 / 255, alpha: 1)
  }
  static let actionInkUIColor = UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 7 / 255, green: 53 / 255, blue: 44 / 255, alpha: 1) : .white
  }
  static let accent = Color(uiColor: accentUIColor)
  static let actionInk = Color(uiColor: actionInkUIColor)
}

extension View {
  func galaxySSIHealthTheme() -> some View {
    accentColor(GalaxySSIHealthTheme.accent).tint(GalaxySSIHealthTheme.accent)
      .listStyle(.plain)
      .textFieldStyle(GalaxySSIHealthInputStyle())
      .navigationBarTitleDisplayMode(.inline)
      .background(Color(uiColor: .systemBackground).ignoresSafeArea())
  }
  func galaxySSIHealthFunctionsToolbar() -> some View { modifier(GalaxySSIHealthFunctionsToolbar()) }
}

private struct GalaxySSIHealthFunctionsKey: EnvironmentKey {
  static let defaultValue: (() -> AnyView)? = nil
}
extension EnvironmentValues {
  var galaxySSIHealthFunctions: (() -> AnyView)? {
    get { self[GalaxySSIHealthFunctionsKey.self] }
    set { self[GalaxySSIHealthFunctionsKey.self] = newValue }
  }
}
private struct GalaxySSIHealthFunctionsToolbar: ViewModifier {
  @Environment(\.galaxySSIHealthFunctions) private var functions
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  func body(content: Content) -> some View {
    content.toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        if let functions {
          NavigationLink(destination: functions) {
            Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44)
          }.accessibilityLabel(title).help(title)
        }
      }
    }
  }
  private var title: String {
    GalaxySSILocalization.string("galaxyssi.health.functions", fallback: "Health functions", language: language)
  }
}

struct GalaxySSIHealthCommandStyle: ButtonStyle {
  @Environment(\.isEnabled) private var enabled
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.subheadline.weight(.semibold))
      .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 48)
      .foregroundColor(enabled ? GalaxySSIHealthTheme.actionInk : .secondary)
      .background(enabled ? GalaxySSIHealthTheme.accent.opacity(configuration.isPressed ? 0.82 : 1) : Color(uiColor: .tertiarySystemFill),
        in: RoundedRectangle(cornerRadius: 8))
      .contentShape(RoundedRectangle(cornerRadius: 8))
  }
}

private struct GalaxySSIHealthInputStyle: TextFieldStyle {
  func _body(configuration: TextField<Self._Label>) -> some View {
    Input(content: configuration)
  }
  private struct Input<Content: View>: View {
    let content: Content
    @FocusState private var focused: Bool
    @Environment(\.isEnabled) private var enabled
    var body: some View {
      content.focused($focused).foregroundColor(enabled ? .primary : .secondary)
        .padding(12).frame(minHeight: 48)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(
          focused && enabled ? GalaxySSIHealthTheme.accent : Color(uiColor: .separator), lineWidth: 1))
    }
  }
}
