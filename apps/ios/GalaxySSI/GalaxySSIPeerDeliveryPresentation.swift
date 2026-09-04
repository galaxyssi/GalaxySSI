import Foundation

enum GalaxySSIPeerDeliveryPresentation {
  static func title(
    for status: ChatDeliveryStatus,
    isPeerMessage: Bool,
    language: String
  ) -> String {
    guard isPeerMessage else {
      return GalaxySSIChatDeliveryStatus.title(status, language: language)
    }
    switch status {
    case .failed:
      return GalaxySSIChatDeliveryStatus.title(.failed, language: language)
    case .sent, .delivered, .read:
      return GalaxySSIChatDeliveryStatus.title(.sent, language: language)
    case .local, .queued:
      return GalaxySSIChatDeliveryStatus.title(.queued, language: language)
    }
  }
}
