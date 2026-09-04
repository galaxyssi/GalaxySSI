import Foundation

enum GalaxySSIChatDeliveryStatus {
  static func title(_ status: ChatDeliveryStatus, language: String) -> String {
    switch status {
    case .local:
      return localized("delivery_status_local_saved", fallback: "Saved locally", language: language)
    case .queued:
      return localized("delivery_status_queued", fallback: "Queued", language: language)
    case .sent:
      return localized("delivery_status_sent", fallback: "Sent", language: language)
    case .delivered:
      return localized("delivery_status_delivered", fallback: "Delivered", language: language)
    case .read:
      return localized("delivery_status_read", fallback: "Read", language: language)
    case .failed:
      return localized("delivery_status_failed", fallback: "Failed", language: language)
    }
  }

  private static func localized(
    _ key: String,
    fallback: String,
    language: String
  ) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}
