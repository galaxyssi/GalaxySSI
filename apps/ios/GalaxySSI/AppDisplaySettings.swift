import Foundation

enum AppTextScaleMode: String, Codable, CaseIterable, Identifiable {
  case system
  case standard
  case comfortable
  case large
  case extraLarge = "extra_large"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AppTextScaleMode {
    let candidate = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return allCases.first { $0.rawValue == candidate } ?? .comfortable
  }

  var displayName: String {
    switch self {
    case .system: return "System"
    case .standard: return "Standard"
    case .comfortable: return "Comfortable"
    case .large: return "Large"
    case .extraLarge: return "Extra Large"
    }
  }

  var detail: String {
    switch self {
    case .system:
      return "Follow the iOS system text size."
    case .standard:
      return "Use the app's compact default text size."
    case .comfortable:
      return "Use the app's default comfortable text size."
    case .large:
      return "Increase text for easier reading."
    case .extraLarge:
      return "Use the largest app text size."
    }
  }
}

struct AppDisplaySettings: Codable, Equatable {
  var textScale: AppTextScaleMode

  static let `default` = AppDisplaySettings()

  init(textScale: AppTextScaleMode = .comfortable) {
    self.textScale = textScale
  }

  enum CodingKeys: String, CodingKey {
    case textScale = "text_scale"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(textScale: AppTextScaleMode.fromWireValue(try container.decodeIfPresent(String.self, forKey: .textScale)))
  }
}
