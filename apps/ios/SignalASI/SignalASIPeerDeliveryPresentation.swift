import Foundation

enum SignalASIPeerDeliveryPresentation {
  static func title(
    for status: ChatDeliveryStatus,
    isPeerMessage: Bool,
    language: String
  ) -> String {
    guard isPeerMessage else {
      return SignalASIChatDeliveryStatus.title(status, language: language)
    }
    switch status {
    case .failed:
      return SignalASIChatDeliveryStatus.title(.failed, language: language)
    case .sent, .delivered, .read:
      return SignalASIChatDeliveryStatus.title(.sent, language: language)
    case .local, .queued:
      return SignalASIChatDeliveryStatus.title(.queued, language: language)
    }
  }
}
